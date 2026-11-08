#!/usr/bin/env python3
"""CI only: an iPhone simulator that boots while the build runs.

    python3 -I scripts/ci-simulator.py start <name>      # create one, start booting it, write UDID to $GITHUB_ENV
    python3 -I scripts/ci-simulator.py wait <name> [s]   # wait for $UDID to finish booting (default 300 s)
    python3 -I scripts/ci-simulator.py --selftest

`start` picks the newest iOS runtime the image already has (never one it would download) that is no newer than the
selected Xcode's simulator SDK (an iPhone on iOS 27.2 beside Xcode 27.1 hung booting twice, spoonjoy-apple#218), creates the first iPhone
it can on it, and boots it in a detached process that runs `simctl bootstatus -b` and records its exit code. It
returns at once, so `xcodebuild build-for-testing` runs while the simulator boots.

`wait` waits for that record with its own limit. A boot that fails, aborts inside CoreSimulator or hangs past the
limit (spoonjoy-apple#218: create hung 6 min; bootstatus exited 134 and 142) is the machine, not the app: it deletes
that device, creates a fresh one, boots it with the same limit and writes the new UDID, as a warning titled
"Infrastructure retry". A second failure fails the step. `simctl create` has its own 90 s limit and cleanup calls 30 s,
for the same reason. `simctl list runtimes` gets 3 tries of 60 s with CoreSimulator restarted between them (#74).
Worst case for `wait <name> 240`: 240 + 60 + 180 + 270 + 240 s, inside a 16-minute step limit.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DEVICES = ["iPhone 17 Pro", "iPhone 16 Pro", "iPhone 16"]
CREATE_LIMIT = 90
LIST_LIMIT = 60
LIST_TRIES = 3


def state_dir():
    d = Path(os.environ.get("RUNNER_TEMP") or tempfile.gettempdir()) / "ci-simulator"
    d.mkdir(parents=True, exist_ok=True)
    return d


def version(v):
    return [int(p) for p in v.split(".")]


def newest_ios_runtime(runtimes, sdk):
    top = version(sdk)[:2]
    ios = [r for r in runtimes if r.get("platform") == "iOS" and r.get("isAvailable") and version(r["version"])[:2] <= top]
    if not ios:
        raise SystemExit(f"ci-simulator: the image has no available iOS runtime at or below the iOS {sdk} SDK")
    return max(ios, key=lambda r: version(r["version"]))["identifier"]


def simctl(*args, timeout=60):
    return subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True, timeout=timeout)


def quietly(*args):
    """A cleanup call on a device that may itself be hung: a timeout or failure is only a warning."""
    try:
        simctl(*args, timeout=30)
    except subprocess.TimeoutExpired:
        print(f"::warning::simctl {' '.join(args)} hung past 30 s; going on with a fresh device.")


def kick_coresimulator():
    """Restart a wedged CoreSimulator service; launchd starts a fresh one on the next simctl call."""
    subprocess.run(["killall", "-9", "com.apple.CoreSimulator.CoreSimulatorService"], capture_output=True, timeout=30)


def list_runtimes(run=simctl, kick=kick_coresimulator, tries=LIST_TRIES):
    """`simctl list runtimes`, with a CoreSimulator restart between tries: it can hang on a fresh runner (#74)."""
    for attempt in range(1, tries + 1):
        try:
            out = run("list", "runtimes", "-j", timeout=LIST_LIMIT)
            if out.returncode == 0:
                return json.loads(out.stdout)["runtimes"]
            why = f"exited {out.returncode}"
        except subprocess.TimeoutExpired:
            why = f"hung past {LIST_LIMIT} s"
        if attempt < tries:
            print(f"::warning title=Infrastructure retry::simctl list runtimes {why}; restarting CoreSimulator (#74).")
            kick()
    raise SystemExit(f"::error title=Simulator could not start::simctl list runtimes {why}, {tries} times, with "
                     f"CoreSimulator restarted between. This runner's simulator service is broken; no app code ran (#74).")


def create(name):
    sdk = subprocess.run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], capture_output=True, text=True,
                         check=True, timeout=60).stdout.strip()
    runtime = newest_ios_runtime(list_runtimes(), sdk)
    for device in DEVICES:
        try:
            out = simctl("create", name, device, runtime, timeout=CREATE_LIMIT)
        except subprocess.TimeoutExpired:
            print(f"::warning title=Infrastructure retry::simctl create {device} on {runtime} hung past {CREATE_LIMIT} s; trying the next device type.")
            continue
        if out.returncode == 0 and out.stdout.strip():
            udid = out.stdout.strip()
            print(f"Using {device} on {runtime}: {udid}")
            return udid
    raise SystemExit(f"ci-simulator: could not create any of {DEVICES} on {runtime}")


def boot(udid):
    d = state_dir()
    log = open(d / f"{udid}.log", "ab")
    status = d / f"{udid}.status"
    # Detached, so it outlives this step: the build step runs while it boots.
    subprocess.Popen(
        ["sh", "-c", 'xcrun simctl boot "$1" || true; xcrun simctl bootstatus "$1" -b; echo $? > "$2"', "boot", udid, str(status)],
        stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, start_new_session=True)


def wait_boot(udid, limit, clock=time.monotonic, nap=time.sleep):
    """The boot's exit code, or None if it has not finished within the limit."""
    status = state_dir() / f"{udid}.status"
    end = clock() + limit
    while clock() < end:
        if status.exists() and status.read_text().strip():
            return int(status.read_text().strip())
        nap(2)
    return None


def export(udid):
    env = os.environ.get("GITHUB_ENV")
    if env:
        with open(env, "a") as f:
            f.write(f"UDID={udid}\n")


def describe(code, limit):
    return f"no boot within {limit} s" if code is None else f"bootstatus exited {code}"


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    if len(argv) >= 2 and argv[0] == "start":
        udid = create(argv[1])
        export(udid)
        boot(udid)
        return 0
    if len(argv) >= 2 and argv[0] == "wait":
        name, limit = argv[1], int(argv[2]) if len(argv) > 2 else 300
        udid = os.environ["UDID"]
        code = wait_boot(udid, limit)
        if code == 0:
            print(f"{udid} booted")
            return 0
        tail = (state_dir() / f"{udid}.log").read_text(errors="replace")[-2000:]
        print(f"::warning title=Infrastructure retry::Simulator {udid}: {describe(code, limit)}. Deleting it and booting a fresh one (spoonjoy-apple#218).")
        print(tail)
        quietly("shutdown", udid)
        quietly("delete", udid)
        udid = create(name)
        export(udid)
        boot(udid)
        code = wait_boot(udid, limit)
        if code == 0:
            print(f"{udid} booted")
            return 0
        print((state_dir() / f"{udid}.log").read_text(errors="replace")[-2000:])
        print(f"::error title=Simulator did not boot::A fresh simulator also failed: {describe(code, limit)}. No app code ran.")
        return 1
    print(__doc__, file=sys.stderr)
    return 2


def selftest():
    runtimes = [
        {"platform": "iOS", "isAvailable": True, "version": "26.2", "identifier": "iOS-26-2"},
        {"platform": "iOS", "isAvailable": True, "version": "26.10", "identifier": "iOS-26-10"},
        {"platform": "iOS", "isAvailable": False, "version": "27.0", "identifier": "iOS-27-0"},
        {"platform": "watchOS", "isAvailable": True, "version": "30.0", "identifier": "watchOS-30"},
    ]
    assert newest_ios_runtime(runtimes, "26.10") == "iOS-26-10", "numeric, available, iOS only"
    assert newest_ios_runtime(runtimes, "26.2") == "iOS-26-2", "never newer than the SDK"
    assert newest_ios_runtime(runtimes, "26.10.1") == "iOS-26-10", "patch versions don't matter"
    try:
        newest_ios_runtime(runtimes[2:], "30.0")
        raise AssertionError("no runtime must fail")
    except SystemExit:
        pass
    os.environ["RUNNER_TEMP"] = tempfile.mkdtemp()
    now = [0.0]
    clock, nap = (lambda: now[0]), (lambda s: now.__setitem__(0, now[0] + s))
    assert wait_boot("hung", 10, clock, nap) is None, "a hang times out"
    (state_dir() / "ok.status").write_text("0\n")
    assert wait_boot("ok", 10, clock, nap) == 0
    (state_dir() / "abort.status").write_text("134\n")
    assert wait_boot("abort", 10, clock, nap) == 134
    assert describe(None, 300) == "no boot within 300 s" and describe(142, 300) == "bootstatus exited 142"
    ok = subprocess.CompletedProcess([], 0, json.dumps({"runtimes": runtimes}), "")
    calls, kicks = [], []

    def flaky(*args, timeout):
        calls.append(args)
        if len(calls) < 3:
            raise subprocess.TimeoutExpired(args, timeout)
        return ok
    assert list_runtimes(flaky, lambda: kicks.append(1)) == runtimes and len(calls) == 3 and len(kicks) == 2, \
        "two hangs, two restarts, then the list"

    def hung(*args, timeout):
        raise subprocess.TimeoutExpired(args, timeout)
    try:
        list_runtimes(hung, lambda: None)
        raise AssertionError("three hangs must fail")
    except SystemExit as e:
        assert "could not start" in str(e)
    print("ci-simulator: selftest passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
