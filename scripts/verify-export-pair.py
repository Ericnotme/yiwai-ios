#!/usr/bin/env python3
"""Verify explicitly selected synthetic build-17 exports; never scan a Mac.

Input is either repeated --file paths relative to --evidence-dir, or the exact
files listed by one CI actual-exports.json via --collector-report. The collector
report's SHA256/size are checked. No globbing, deletion, or simulator access.
This verifies artifact contents, not UI success or source/run provenance.
"""
import argparse
import datetime
import hashlib
import json
import math
import re
from pathlib import Path
import sys
import uuid

COURSE_SHA256 = "32d1a4aa8e8f68db758320d932cd6b9b720add88ddc42efbef701ddb495750dc"
ORIGINAL_PGN = "1. e4 {Local original comment} (1. d4 d5) e5 2. Nf3 Nc6 *"
NOTE = "Look for the opponent's threat.\nA local memory."
MOVES = ["e2e4", "e7e5", "g1f3", "b8c6"]
INITIAL_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
LIMIT = 10 * 1024 * 1024
EXPORT_NAME = re.compile(r"Yiwai-Time-Capsule-([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}Z)-([0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12})\.json")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def bounded_path(root, value):
    relative = Path(value)
    require(not relative.is_absolute() and ".." not in relative.parts,
            "Input path must be relative and cannot contain '..': " + str(value))
    path = root / relative
    require(not path.is_symlink(), "Symlink file not accepted: " + str(value))
    resolved = path.resolve(strict=True)
    require(resolved.is_relative_to(root), "Input escapes the evidence directory: " + str(value))
    require(resolved.is_file(), "Not a regular evidence file: " + str(value))
    require(resolved.stat().st_size <= LIMIT, "Evidence file exceeds 10 MB: " + str(value))
    return resolved


def decode(raw):
    def no_constant(value):
        raise ValueError("Non-JSON numeric constant: " + value)

    def unique_keys(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate JSON key: " + key)
            result[key] = value
        return result

    return json.loads(raw, parse_constant=no_constant, object_pairs_hook=unique_keys)


def finite_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def verify_default_name(relative_path):
    require(isinstance(relative_path, str) and relative_path,
            "Missing original relative path for default-name verification")
    relative = Path(relative_path)
    require(not relative.is_absolute() and ".." not in relative.parts,
            "Original export path must be relative and cannot contain '..'")
    match = EXPORT_NAME.fullmatch(relative.name)
    require(match is not None, "Original filename is not the build-17 UTC/UUID default: " + relative.name)
    timestamp, identifier = match.groups()
    datetime.datetime.strptime(timestamp, "%Y-%m-%dT%H%M%SZ")
    parsed = uuid.UUID(identifier)
    require(parsed.version == 4 and str(parsed).upper() == identifier,
            "Default export filename must contain a complete random UUID")
    return {"filename": relative.name, "timestampUTC": timestamp, "operationID": identifier}


def verify_capsule(data, course):
    require(isinstance(data, dict), "Capsule must be a JSON object")
    require(data.get("format") == "yiwai-local-time-capsule", "Wrong capsule format")
    require(data.get("schemaVersion") == 6, "Expected schema 6")
    require(data.get("appVersion") == "0.4.4 (17)", "Expected exact appVersion 0.4.4 (17)")
    require(finite_number(data.get("exportedAt")) and data["exportedAt"] > 0,
            "Missing valid export timestamp")
    require(data.get("fortressLessons") == course,
            "Course definitions differ from the pinned four-chapter, 16-question catalog")
    progress = data.get("fortressProgress")
    require(isinstance(progress, dict) and progress.get("schemaVersion") == 1
            and progress.get("records") == [], "Expected the reset fixture's empty fortressProgress")
    conditions = data.get("conditionStudy")
    require(isinstance(conditions, dict) and conditions.get("schemaVersion") == 1,
            "Missing conditionStudy schema 1")
    games = data.get("games")
    runs = conditions.get("runs")
    require(isinstance(games, list) and isinstance(runs, list), "Games/runs must be arrays")

    if games == []:
        require(data.get("gamePGN") == [], "Conditions fixture must have no game PGN")
        require(len(runs) == 1 and isinstance(runs[0], dict), "Expected one ended condition run")
        run = runs[0]
        require(run.get("phase") == "comparison" and run.get("demonstration") is False,
                "Expected a non-demonstration comparison run")
        require(run.get("paused") is False, "Ended condition run is still paused")
        require(finite_number(run.get("feedbackAt")) and run["feedbackAt"] > 0,
                "Condition run has no feedbackAt: it was not explicitly ended")
        require(finite_number(run.get("startedAt")) and run["feedbackAt"] >= run["startedAt"],
                "Invalid condition-run time ordering")
        trials = run.get("trials")
        require(isinstance(trials, list) and len(trials) == 12, "Expected exactly 12 condition trials")
        require(all(isinstance(t, dict) and t.get("firstAnswer") is None for t in trials),
                "Conditions fixture must retain 0 first answers")
        ids = [t.get("id") for t in trials]
        require(all(isinstance(i, str) and i for i in ids) and len(set(ids)) == 12,
                "Condition trials lack 12 distinct IDs")
        positions = [t.get("position") for t in trials]
        require(all(isinstance(p, dict) and isinstance(p.get("id"), str)
                    and p.get("fen") and p.get("pgn") and isinstance(p.get("proofMoves"), list)
                    for p in positions), "Condition trial definitions are incomplete")
        require(len({p["id"] for p in positions}) == 12, "Condition positions are not distinct")
        require(run.get("retries") == [] and run.get("recalls") == [],
                "Unexpected retry/recall data in reset conditions fixture")
        return "conditions", {"trials": 12, "firstAnswers": 0, "explicitlyEnded": True}

    require(len(games) == 1 and isinstance(games[0], dict), "Expected exactly one PGN game")
    require(runs == [], "PGN fixture contains unexpected condition runs")
    game = games[0]
    require(game.get("source") == "pgn" and game.get("initialFEN") == INITIAL_FEN,
            "Wrong PGN fixture source or start position")
    require(game.get("originalPGN") == ORIGINAL_PGN, "Original PGN/comments/variation changed")
    require(game.get("personalNote") == NOTE, "Exact two-line personal note changed")
    require(game.get("moves") == MOVES, "Exact four half-moves changed")
    pgn = data.get("gamePGN")
    require(isinstance(pgn, list) and len(pgn) == 1 and isinstance(pgn[0], dict),
            "Expected one corresponding mainline PGN")
    require(pgn[0].get("recordID") == game.get("id") and bool(game.get("id")),
            "Mainline PGN recordID does not match the game")
    mainline = pgn[0].get("mainlinePGN")
    require(isinstance(mainline, str) and mainline.split("\n\n", 1)[-1].strip()
            == "1. e4 e5 2. Nf3 Nc6 *", "Mainline PGN is not the exact four-move fixture")
    return "pgn_notes", {"games": 1, "originalPGNCommentsVariationVerified": True,
                         "twoLineNoteVerified": True, "halfMoves": MOVES,
                         "mainlineAndRecordIDVerified": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument("--file", action="append", help="Explicit file relative to evidence directory; repeat")
    inputs.add_argument("--collector-report", help="CI collector JSON relative to evidence directory")
    parser.add_argument("--require-default-filenames", action="store_true",
                        help="Require two distinct actual build-17 UTC/UUID default names (collector relativePath, never artifactFile)")
    parser.add_argument("--course", type=Path,
                        default=Path(__file__).with_name("expected-fortress-course-v1.json"))
    parser.add_argument("--output", type=Path, help="New receipt path; existing files are not overwritten")
    args = parser.parse_args()
    receipt = {"checkedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "result": "FAIL", "scope": "Explicit evidence files only; no directory scan or simulator access",
               "evidenceDirectory": str(args.evidence_dir.resolve()),
               "expectedFixtureCounts": {"conditions": 1, "pgn_notes": 1},
               "courseReferenceSHA256": COURSE_SHA256,
               "defaultFilenamesRequired": args.require_default_filenames,
               "files": [], "counts": {"conditions": 0, "pgn_notes": 0}, "errors": [],
               "limitations": "Content verification does not prove UI completion, exact run/source provenance, full UI suite success, or release readiness."}
    try:
        root = args.evidence_dir.resolve(strict=True)
        require(root.is_dir(), "Evidence directory is not a directory")
        raw_course = args.course.read_bytes()
        require(hashlib.sha256(raw_course).hexdigest() == COURSE_SHA256, "Pinned course reference SHA256 mismatch")
        course = decode(raw_course)
        chapters = course.get("chapters", [])
        require(len(chapters) == 4 and all(len(c.get("questions", [])) == 4 for c in chapters),
                "Pinned catalog must contain four chapters of four questions")
        if args.collector_report:
            report_path = bounded_path(root, args.collector_report)
            report = decode(report_path.read_bytes())
            require(isinstance(report, dict) and report.get("available") is True,
                    "Collector did not confirm its scoped source directory was available")
            require(report.get("rejected") == [], "Collector rejected one or more output files")
            entries = report.get("files")
            require(isinstance(entries, list), "Collector files is not an array")
            receipt["collectorReport"] = {"path": str(report_path),
                                          "sha256": hashlib.sha256(report_path.read_bytes()).hexdigest(),
                                          "device": report.get("device"), "scope": report.get("scope")}
            selections = []
            for entry in entries:
                require(isinstance(entry, dict), "Invalid collector entry")
                filename = entry.get("artifactFile")
                require(isinstance(filename, str) and filename == Path(filename).name,
                        "Collector artifactFile must be a plain filename")
                selections.append((str(Path(args.collector_report).parent / "actual-exports" / filename), entry))
        else:
            selections = [(value, None) for value in args.file]
        seen = set()
        seen_names, seen_ids = set(), set()
        for value, metadata in selections:
            item = {"selectedPath": value}
            try:
                path = bounded_path(root, value)
                require(path not in seen, "Same file selected twice")
                seen.add(path)
                raw = path.read_bytes()
                digest = hashlib.sha256(raw).hexdigest()
                item.update(path=str(path), bytes=len(raw), sha256=digest)
                if metadata is not None:
                    require(metadata.get("sha256") == digest and metadata.get("bytes") == len(raw),
                            "Collector SHA256/byte count does not match the actual file")
                    item["originalRelativePath"] = metadata.get("relativePath")
                if args.require_default_filenames:
                    name_check = verify_default_name(metadata.get("relativePath") if metadata is not None else value)
                    require(name_check["filename"] not in seen_names, "Default filename was reused")
                    require(name_check["operationID"] not in seen_ids, "Export operation UUID was reused")
                    seen_names.add(name_check["filename"])
                    seen_ids.add(name_check["operationID"])
                    item["defaultFilename"] = name_check
                data = decode(raw)
                category, checks = verify_capsule(data, course)
                receipt["counts"][category] += 1
                item.update(fixture=category, appVersion=data["appVersion"], schemaVersion=6,
                            exportedAt=data["exportedAt"], chapters=4, questions=16, checks=checks, result="PASS")
            except (OSError, ValueError, TypeError, KeyError) as error:
                item.update(result="FAIL", error=str(error))
                receipt["errors"].append(value + ": " + str(error))
            receipt["files"].append(item)
        for kind, expected in receipt["expectedFixtureCounts"].items():
            if receipt["counts"][kind] != expected:
                receipt["errors"].append(f"Expected exactly {expected} {kind} fixture; found {receipt['counts'][kind]}")
        if not receipt["errors"]:
            receipt["result"] = "PASS"
    except (OSError, ValueError, TypeError, KeyError) as error:
        receipt["errors"].append(str(error))
    rendered = json.dumps(receipt, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        try:
            with args.output.open("x", encoding="utf-8") as destination:
                destination.write(rendered)
        except OSError as error:
            print("Cannot create new receipt: " + str(error), file=sys.stderr)
            return 2
    print(rendered, end="")
    return 0 if receipt["result"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
