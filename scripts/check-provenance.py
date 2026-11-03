#!/usr/bin/env python3
"""Checks core-provenance.json: every vendored file still has the SHA-256 it was pinned with, and that hash is the one
ouro-ui-core's release at coreTag publishes, both in its dist-manifest.json and in the release asset itself.

    python3 -I scripts/check-provenance.py            # local hashes and the release (needs the network)
    python3 -I scripts/check-provenance.py --offline  # local hashes only

Exit codes: 0 ok, 1 error (the check could not run), 2 usage, 3 findings (a hash differs).
"""
import hashlib
import json
import os
import sys
import urllib.request

CORE = "https://github.com/ourostack/ouro-ui-core/releases/download"
TOOL = "check-provenance"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def main(argv: list[str]) -> int:
    args = argv[1:]
    if any(a not in ("--offline",) for a in args):
        print(f"{TOOL}: {' '.join(args)}: unknown argument. Fix: python3 -I scripts/check-provenance.py [--offline].", file=sys.stderr)
        return 2
    offline = "--offline" in args
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    try:
        with open(os.path.join(root, "core-provenance.json"), "rb") as f:
            provenance = json.load(f)
        tag = provenance["coreTag"]
        files = provenance["files"]
    except (OSError, KeyError, ValueError) as error:
        print(f"{TOOL}: core-provenance.json: cannot read it ({error}). Fix: restore it from git.", file=sys.stderr)
        return 1

    findings = 0
    manifest = None
    if not offline:
        try:
            manifest = json.loads(fetch(f"{CORE}/{tag}/dist-manifest.json"))["files"]
        except Exception as error:  # network or a missing release: the check could not run
            print(f"{TOOL}: {tag}: cannot download dist-manifest.json ({error}). Fix: check the tag exists at https://github.com/ourostack/ouro-ui-core/releases.", file=sys.stderr)
            return 1

    for path, pinned in files.items():
        try:
            with open(os.path.join(root, path), "rb") as f:
                local = sha256(f.read())
        except OSError:
            print(f"{TOOL}: {path}: missing. Fix: download it from {CORE}/{tag}/{os.path.basename(path)}.")
            findings += 1
            continue
        if local != pinned:
            print(f"{TOOL}: {path}: its SHA-256 is {local}, not the pinned {pinned}. Fix: never edit a vendored file; restore it from the {tag} release, or bump coreTag in a token-bump PR.")
            findings += 1
        else:
            print(f"ok    {path} matches its pin")
        if manifest is None:
            continue
        name = os.path.basename(path)
        keys = [k for k in manifest if os.path.basename(k) == name]
        if len(keys) != 1:
            print(f"{TOOL}: {path}: {tag}'s dist-manifest.json has {len(keys)} files named {name}. Fix: pin a file core releases.")
            findings += 1
            continue
        if manifest[keys[0]] != pinned:
            print(f"{TOOL}: {path}: pinned {pinned}, but {tag} released {keys[0]} as {manifest[keys[0]]}. Fix: copy the file from the {tag} release and pin its hash.")
            findings += 1
            continue
        try:
            asset = sha256(fetch(f"{CORE}/{tag}/{name}"))
        except Exception as error:
            print(f"{TOOL}: {name}: cannot download the {tag} asset ({error}). Fix: check the release still has it.", file=sys.stderr)
            return 1
        if asset != pinned:
            print(f"{TOOL}: {path}: the {tag} release asset hashes to {asset}, not {pinned}. Fix: report it on ourostack/ouro-ui-core; a release asset must match its manifest.")
            findings += 1
        else:
            print(f"ok    {path} matches {tag}'s {keys[0]} and its release asset")

    if findings:
        print(f"{findings} provenance finding(s).")
        return 3
    print(f"core-provenance.json: every vendored file is ouro-ui-core {tag}, byte for byte.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
