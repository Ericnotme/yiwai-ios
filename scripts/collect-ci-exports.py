#!/usr/bin/env python3
"""Collect synthetic exports from one recorded CI simulator, without following links.

Never run against a personal simulator. Only matching filenames below the exact
selected data/Containers/Shared/AppGroup are read. Content acceptance is a separate
mandatory verify-export-pair.py step; this collector does not claim tests passed.
"""
import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import uuid

LIMIT = 10 * 1024 * 1024
PATTERNS = ("Yiwai-Time-Capsule*.json", "-Conditions-UITest-*.json", "-UITest-*.json")
DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW


def require(condition, message):
    if not condition:
        raise ValueError(message)


def absolute_directory(path):
    """Open each path component with no-follow, including the selected boundary."""
    path = Path(path)
    require(path.is_absolute() and ".." not in path.parts, "Expected an absolute bounded directory")
    fd = os.open(path.anchor, DIRECTORY_FLAGS)
    try:
        for part in path.parts[1:]:
            child = os.open(part, DIRECTORY_FLAGS, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def read_regular(parent_fd, name):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent_fd)
    try:
        before = os.fstat(fd)
        require(stat.S_ISREG(before.st_mode), "Not a regular file")
        require(before.st_size <= LIMIT, "File exceeds 10 MB")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            raw = stream.read(LIMIT + 1)
        after = os.fstat(fd)
        require(len(raw) <= LIMIT and len(raw) == before.st_size, "File size changed while reading")
        require((before.st_size, before.st_mtime_ns, before.st_ctime_ns) ==
                (after.st_size, after.st_mtime_ns, after.st_ctime_ns), "File changed while reading")
        return raw
    finally:
        os.close(fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selected-device", type=Path, required=True)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    args = parser.parse_args()
    # This is not a personal-Mac discovery tool. Local validation uses only a
    # separately constructed synthetic directory and an explicit fake CI env.
    require(os.environ.get("GITHUB_ACTIONS") == "true", "CI-only collector; do not scan a personal Mac")
    evidence = args.evidence_dir.absolute()
    evidence_fd = absolute_directory(evidence)
    report = {"available": False, "device": None,
              "scope": "Recorded simulator data/Containers/Shared/AppGroup only; synthetic export filename patterns",
              "filenamePatterns": list(PATTERNS), "files": [], "rejected": [],
              "skippedSymlinks": [], "entriesVisited": 0}
    groups_fd = destination_fd = None
    try:
        selected_path = args.selected_device.absolute()
        require(selected_path.parent == evidence, "Selected-device record must be in this evidence directory")
        selected = json.loads(read_regular(evidence_fd, selected_path.name))
        device = selected["udid"]
        require(str(uuid.UUID(device)).upper() == device.upper(), "Invalid simulator UUID")
        data = Path(selected["dataPath"])
        require(data.is_absolute() and ".." not in data.parts and data.name == "data"
                and data.parent.name == device and data.parent.parent.name == "Devices",
                "Unexpected recorded simulator dataPath")
        report["device"] = device
        report["selectedDeviceRecordSHA256"] = hashlib.sha256(read_regular(evidence_fd, selected_path.name)).hexdigest()
        report["sourceDataPath"] = str(data)
        groups = data / "Containers" / "Shared" / "AppGroup"
        groups_fd = absolute_directory(groups)
        report["available"] = True
        # Exclusive creation prevents this invocation from mixing/replacing a prior collection.
        os.mkdir("actual-exports", mode=0o700, dir_fd=evidence_fd)
        destination_fd = os.open("actual-exports", DIRECTORY_FLAGS, dir_fd=evidence_fd)

        def walk(directory_fd, parents=()):
            require(len(parents) <= 50, "Collection nesting limit exceeded")
            with os.scandir(directory_fd) as entries:
                names = sorted(entry.name for entry in entries)
            for name in names:
                report["entriesVisited"] += 1
                require(report["entriesVisited"] <= 200000, "Collection entry limit exceeded")
                relative = "/".join((*parents, name))
                candidate = any(fnmatch.fnmatchcase(name, pattern) for pattern in PATTERNS)
                try:
                    info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
                    if stat.S_ISLNK(info.st_mode):
                        report["skippedSymlinks"].append(relative)
                        if candidate:
                            report["rejected"].append({"relativePath": relative, "reason": "Candidate is a symlink"})
                        continue
                    if stat.S_ISDIR(info.st_mode):
                        child = os.open(name, DIRECTORY_FLAGS, dir_fd=directory_fd)
                        try:
                            walk(child, (*parents, name))
                        finally:
                            os.close(child)
                    elif candidate:
                        raw = read_regular(directory_fd, name)
                        digest = hashlib.sha256(raw).hexdigest()
                        # Path hash preserves two identical files at distinct source paths;
                        # the verifier then rejects duplicate fixtures instead of hiding one.
                        path_hash = hashlib.sha256(relative.encode("utf-8")).hexdigest()[:16]
                        artifact = path_hash + "-" + digest[:16] + "-" + name[-120:]
                        out = os.open(artifact, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                      0o600, dir_fd=destination_fd)
                        with os.fdopen(out, "wb") as stream:
                            stream.write(raw)
                        copied = read_regular(destination_fd, artifact)
                        require(copied == raw, "Copied file does not match source bytes")
                        report["files"].append({"relativePath": relative, "artifactFile": artifact,
                                                "bytes": len(raw), "sha256": digest})
                except (OSError, ValueError) as error:
                    report["rejected"].append({"relativePath": relative, "reason": str(error)})

        walk(groups_fd)
    except (OSError, ValueError, TypeError, KeyError) as error:
        report["rejected"].append({"reason": str(error)})
    finally:
        if destination_fd is not None:
            os.close(destination_fd)
        if groups_fd is not None:
            os.close(groups_fd)
        rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
        try:
            out = os.open("actual-exports.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                          0o600, dir_fd=evidence_fd)
            with os.fdopen(out, "w", encoding="utf-8") as stream:
                stream.write(rendered)
        finally:
            os.close(evidence_fd)
    print(json.dumps({"actualExportFiles": len(report["files"]), "available": report["available"],
                      "rejected": len(report["rejected"]), "skippedSymlinks": len(report["skippedSymlinks"])}))
    return 0 if report["available"] and not report["rejected"] else 1


if __name__ == "__main__":
    sys.exit(main())
