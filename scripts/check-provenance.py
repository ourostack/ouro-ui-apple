#!/usr/bin/env python3
"""Checks core-provenance.json: every vendored file still has the SHA-256 it was pinned with, and that hash is the one
ouro-ui-core's release at coreTag publishes, both in its dist-manifest.json and in the release asset itself.

    python3 -I scripts/check-provenance.py            # local hashes and the release (needs the network)
    python3 -I scripts/check-provenance.py --offline  # local hashes only

A second section, "tree", pins files core keeps in its repository rather than in a release asset (A2UI's catalogs and
conformance cases): each local path maps to its path in ouro-ui-core at the section's coreTag, and the check compares
the SHA-256 with the file at that tag.

Exit codes: 0 ok, 1 error (the check could not run), 2 usage, 3 findings (a hash differs).
"""
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

CORE = "https://github.com/ourostack/ouro-ui-core/releases/download"
TOOL = "check-provenance"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


API = "https://api.github.com/repos/ourostack/ouro-ui-core/releases"


class KeepTokenHome(urllib.request.HTTPRedirectHandler):
    """Drops the token when the API redirects an asset to its storage host: it is for api.github.com only."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None and urllib.parse.urlsplit(newurl).hostname != "api.github.com":
            new.remove_header("Authorization")
        return new


urllib.request.install_opener(urllib.request.build_opener(KeepTokenHome))


def request(url: str, accept: "str | None" = None) -> urllib.request.Request:
    """A request with the job's token when it has one (GITHUB_TOKEN), so API downloads don't share an anonymous limit."""
    headers = {"User-Agent": TOOL}
    if accept:
        headers["Accept"] = accept
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.Request(url, headers=headers)


def fetch(url: str, attempts: int = 3, wait: float = 2.0, accept: "str | None" = None) -> bytes:
    """Downloads url. GitHub's own hiccups (a 5xx, a dropped connection, a timeout) are tried again, up to `attempts`
    times, waiting `wait`, then twice that; a 4xx is the answer and fails at once (#96)."""
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(request(url, accept), timeout=60) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code < 500 or attempt == attempts:
                raise
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            if attempt == attempts:
                raise
        time.sleep(wait * 2 ** (attempt - 1))
    raise AssertionError("unreachable")


def release_asset(tag: str, name: str, assets: dict[str, str]) -> bytes:
    """A release asset, through the REST API's asset endpoint first. On 2026-11-08 every github.com/.../releases/download
    link answered 504 for hours while the API's endpoint served the same files (#96); the download link is the fallback."""
    if name in assets:
        try:
            return fetch(assets[name], accept="application/octet-stream")
        except Exception:
            pass
    return fetch(f"{CORE}/{tag}/{name}")


def asset_urls(tag: str) -> dict[str, str]:
    """The release's assets by name, as API URLs; empty when the API can't say, so downloads fall back to the links."""
    try:
        return {a["name"]: a["url"] for a in json.loads(fetch(f"{API}/tags/{tag}"))["assets"]}
    except Exception:
        return {}


def unreachable(error: Exception) -> bool:
    """Whether a download failed on GitHub's side rather than on a missing file: a 5xx or no answer at all."""
    if isinstance(error, urllib.error.HTTPError):
        return error.code >= 500
    return isinstance(error, (urllib.error.URLError, TimeoutError, ConnectionError))


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
            assets = asset_urls(tag)
            manifest = json.loads(release_asset(tag, "dist-manifest.json", assets))["files"]
        except Exception as error:  # network or a missing release: the check could not run
            fix = ("GitHub failed 3 times running; rerun the job, the release is likely fine" if unreachable(error)
                   else "check the tag exists at https://github.com/ourostack/ouro-ui-core/releases")
            print(f"{TOOL}: {tag}: cannot download dist-manifest.json ({error}). Fix: {fix}.", file=sys.stderr)
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
            asset = sha256(release_asset(tag, name, assets))
        except Exception as error:
            fix = ("GitHub failed 3 times running; rerun the job, the release is likely fine" if unreachable(error)
                   else "check the release still has it")
            print(f"{TOOL}: {name}: cannot download the {tag} asset ({error}). Fix: {fix}.", file=sys.stderr)
            return 1
        if asset != pinned:
            print(f"{TOOL}: {path}: the {tag} release asset hashes to {asset}, not {pinned}. Fix: report it on ourostack/ouro-ui-core; a release asset must match its manifest.")
            findings += 1
        else:
            print(f"ok    {path} matches {tag}'s {keys[0]} and its release asset")

    tree = provenance.get("tree")
    if tree:
        ttag = tree["coreTag"]
        for path, pin in tree["files"].items():
            try:
                with open(os.path.join(root, path), "rb") as f:
                    local = sha256(f.read())
            except OSError:
                print(f"{TOOL}: {path}: missing. Fix: copy {pin['from']} from ouro-ui-core {ttag}.")
                findings += 1
                continue
            if local != pin["sha256"]:
                print(f"{TOOL}: {path}: its SHA-256 is {local}, not the pinned {pin['sha256']}. Fix: never edit a vendored file; copy {pin['from']} from ouro-ui-core {ttag}.")
                findings += 1
                continue
            print(f"ok    {path} matches its pin")
            if offline:
                continue
            try:
                remote = sha256(fetch(f"https://raw.githubusercontent.com/ourostack/ouro-ui-core/{ttag}/{pin['from']}"))
            except Exception as error:
                fix = "GitHub failed 3 times running; rerun the job" if unreachable(error) else f"check {pin['from']} exists at {ttag}"
                print(f"{TOOL}: {pin['from']}: cannot download it at {ttag} ({error}). Fix: {fix}.", file=sys.stderr)
                return 1
            if remote != pin["sha256"]:
                print(f"{TOOL}: {path}: pinned {pin['sha256']}, but ouro-ui-core {ttag}'s {pin['from']} is {remote}. Fix: copy it from {ttag} and pin its hash.")
                findings += 1
            else:
                print(f"ok    {path} matches ouro-ui-core {ttag}'s {pin['from']}")

    if findings:
        print(f"{findings} provenance finding(s).")
        return 3
    print(f"core-provenance.json: every vendored file is ouro-ui-core {tag}, byte for byte.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
