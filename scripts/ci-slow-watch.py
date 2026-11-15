#!/usr/bin/env python3
"""CI only: stop a UI test run whose runner is far slower than the suite's measured times (#199).

    python3 -I scripts/ci-slow-watch.py <suite> <xcodebuild log> <verdict file>   # in the background, beside xcodebuild
    python3 -I scripts/ci-slow-watch.py --selftest

A broken simulator service is caught in a minute and the shard is requeued on a fresh runner (#74). A runner that only
runs slowly was not: on #190, Ouro Feel shard 2's tests took up to 26 times their measured time (`testLateOrLingeringChrome`,
measured 20.6 s, took 535 s) until the job's 40-minute limit cancelled it, and a rerun passed.

This reads the log as xcodebuild writes it. When a test that `scripts/ui-shards.py` has a measured time for has run more
than RATIO times that and at least MARGIN seconds over it, finished or still running, it writes the reason to the
verdict file and stops xcodebuild. The shard then marks the runner broken (scripts/ci-broken-runner.sh), so it's
requeued on a fresh runner. A test with no measured time is never judged. A shard requeued after a slow runner that is
slow again fails, with this reason in its log.
"""
import importlib.util
import os
import re
import subprocess
import sys
import time
from pathlib import Path

RATIO = 4
MARGIN = 120
# A manual run proves the requeue (ci.yml's `slow_shard`): the first measured test to end counts as too slow.
FORCE = os.environ.get("OURO_SLOW_FORCE") == "1"
STARTED = re.compile(r"Test Case '-\[\w+\.(\w+) (\w+)\]' started")
ENDED = re.compile(r"Test Case '-\[\w+\.(\w+) (\w+)\]' (?:passed|failed) \(([0-9.]+) seconds\)")


def measured(suite):
    spec = importlib.util.spec_from_file_location("ui_shards", Path(__file__).with_name("ui-shards.py"))
    shards = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(shards)
    return {test: s for shard in shards.SUITES[suite]["shards"].values() for test, s in shard["tests"].items()}


def too_slow(test, seconds, times, force=False):
    """The reason `test`, `seconds` in, shows a slow runner, or None."""
    m = times.get(test)
    if m is not None and force:
        return f"A manual run asked to treat this runner as too slow ({test} ran {seconds:.0f} s, measured {m:g} s)"
    if m is None or seconds <= RATIO * m or seconds - m < MARGIN:
        return None
    return f"{test} ran {seconds:.0f} s, {seconds / m:.1f} times its measured {m:g} s: the runner is too slow"


def verdict(lines, times, now, started):
    """Reads `lines`; `started` maps a running test to when its start line was read. Returns a reason or None."""
    for line in lines:
        if m := ENDED.search(line):
            test = f"{m.group(1)}/{m.group(2)}"
            started.pop(test, None)
            if why := too_slow(test, float(m.group(3)), times, FORCE):
                return why
        elif m := STARTED.search(line):
            started[f"{m.group(1)}/{m.group(2)}"] = now
    for test, since in started.items():
        if why := too_slow(test, now - since, times):
            return why + " (still running)"
    return None


def watch(suite, log, out, nap=5):
    times, started, seen = measured(suite), {}, 0
    while True:
        time.sleep(nap)
        try:
            with open(log, errors="replace") as f:
                f.seek(seen)
                text = f.read()
                seen = f.tell()
        except FileNotFoundError:
            text = ""
        if why := verdict(text.splitlines(), times, time.monotonic(), started):
            Path(out).write_text(why + "\n")
            print(f"::warning title=Slow runner::{why} (#199). Stopping xcodebuild.", flush=True)
            subprocess.run(["pkill", "-TERM", "-f", "xcodebuild test-without-building"], check=False)
            return 0


def selftest():
    times = {"FeelCatchesTests/testLateOrLingeringChrome": 20.6, "FeelCatchesTests/testTapLanding": 256.3}
    end = "Test Case '-[OuroFeelFixtureUITests.FeelCatchesTests {}]' {} ({} seconds)."
    start = "Test Case '-[OuroFeelFixtureUITests.FeelCatchesTests {}]' started."
    assert verdict([end.format("testLateOrLingeringChrome", "passed", "535.401")], times, 0, {}), "#190's 26 times"
    assert verdict([end.format("testLateOrLingeringChrome", "failed", "535.4")], times, 0, {}), "failed or passed"
    assert not verdict([end.format("testLateOrLingeringChrome", "passed", "80.0")], times, 0, {}), "under the ratio"
    assert not verdict([end.format("testTapLanding", "passed", "700.0")], times, 0, {}), "2.7 times is a busy runner"
    assert not verdict([end.format("testSomethingNew", "passed", "900.0")], times, 0, {}), "unmeasured is never judged"
    running = {}
    assert not verdict([start.format("testLateOrLingeringChrome")], times, 1000, running)
    assert not verdict([], times, 1100, running), "100 s in: under the margin"
    why = verdict([], times, 1150, running)
    assert why and why.endswith("(still running)"), "150 s in, still running: over both"
    assert not verdict([end.format("testLateOrLingeringChrome", "passed", "30.0")], times, 1150, running) and not running, \
        "an end clears its start"
    assert not verdict(["Test Case '-[X.Y testZ]' passed (1 seconds)."], times, 0, {})
    assert measured("feel"), "the feel suite has measured times"
    assert too_slow("FeelCatchesTests/testTapLanding", 10, times, force=True).startswith("A manual run"), "forced"
    assert not too_slow("FeelCatchesTests/testSomethingNew", 10, times, force=True), "forced, still only measured tests"
    print("ci-slow-watch: selftest passed")
    return 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(selftest())
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    sys.exit(watch(*sys.argv[1:]))
