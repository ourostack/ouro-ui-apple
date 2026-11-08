#!/usr/bin/env python3
"""Proves check-provenance's download retry without the network (#96): GitHub's 5xx, dropped connections and timeouts
are tried again up to three times; a 4xx fails at once.

    python3 -I scripts/test-check-provenance.py
"""
import importlib.util
import io
import os
import sys
import urllib.error

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("check_provenance", os.path.join(here, "check-provenance.py"))
cp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cp)


class Answer:
    def __init__(self, body: bytes): self.body = body
    def __enter__(self): return self
    def __exit__(self, *a): return False
    def read(self): return self.body


def scripted(*outcomes):
    """A urlopen that answers each call with the next outcome: an exception is raised, bytes are returned."""
    calls = []
    def urlopen(req, timeout):
        calls.append(req.full_url)
        outcome = outcomes[len(calls) - 1]
        if isinstance(outcome, Exception):
            raise outcome
        return Answer(outcome)
    return urlopen, calls


def http(code): return urllib.error.HTTPError("https://example.invalid/u", code, "x", {}, io.BytesIO())


failures = 0
def check(name, ok):
    global failures
    print(("ok    " if ok else "FAIL  ") + name)
    failures += 0 if ok else 1


cp.time.sleep = lambda s: None

cp.urllib.request.urlopen, calls = scripted(http(504), b"data")
check("a 504 then an answer returns the answer", cp.fetch("https://example.invalid/u") == b"data" and len(calls) == 2)

cp.urllib.request.urlopen, calls = scripted(urllib.error.URLError("reset"), TimeoutError(), b"data")
check("a dropped connection and a timeout are tried again", cp.fetch("https://example.invalid/u") == b"data" and len(calls) == 3)

cp.urllib.request.urlopen, calls = scripted(http(502), http(503), http(504))
try:
    cp.fetch("https://example.invalid/u"); check("three 5xx fail", False)
except urllib.error.HTTPError as e:
    check("three 5xx fail after three tries, and read as GitHub's side", len(calls) == 3 and cp.unreachable(e))

cp.urllib.request.urlopen, calls = scripted(http(404), b"never")
try:
    cp.fetch("https://example.invalid/u"); check("a 404 fails", False)
except urllib.error.HTTPError as e:
    check("a 404 fails at once, and reads as a missing file", len(calls) == 1 and not cp.unreachable(e))

cp.urllib.request.urlopen, calls = scripted(http(504), http(504), http(504), b"from the link")
body = cp.release_asset("v9", "a.json", {"a.json": "https://api.github.com/repos/o/r/releases/assets/1"})
check("an asset whose API endpoint keeps failing comes from the download link",
      body == b"from the link" and calls[0].startswith("https://api.github.com/") and calls[-1].endswith("/v9/a.json"))

cp.urllib.request.urlopen, calls = scripted(b"from the api")
check("an asset comes from the API endpoint first",
      cp.release_asset("v9", "a.json", {"a.json": "https://api.github.com/x"}) == b"from the api" and len(calls) == 1)

api = cp.request("https://api.github.com/x")
cp.os.environ["GITHUB_TOKEN"] = "t"
api = cp.request("https://api.github.com/x")
moved = cp.KeepTokenHome().redirect_request(api, None, 302, "Found", {}, "https://release-assets.githubusercontent.com/a")
check("the token goes to the API and never follows a redirect to another host",
      api.has_header("Authorization") and not moved.has_header("Authorization")
      and not cp.request("https://github.com/x").has_header("Authorization"))

sys.exit(1 if failures else 0)
