#!/usr/bin/env python3
"""Verify the application inputs and the exact Stockfish build network."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'release-manifest.json').read_text())
for name, expected in manifest['sourceFileHashes'].items():
    actual = hashlib.sha256((root / 'YiwaiPractice' / name).read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit('Hash mismatch: ' + name)
net = manifest['network']
if hashlib.sha256((root / net['file']).read_bytes()).hexdigest() != net['sha256']:
    raise SystemExit('NNUE hash mismatch')
print('Verified', len(manifest['sourceFileHashes']), 'application files and exact NNUE network')
