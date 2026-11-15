#!/usr/bin/env python3
"""CI only: which shards of this run a broken runner stopped, to requeue them on fresh runners (#74).

    python3 -I scripts/ci-requeue-plan.py <gallery|feel> <run id>    # GH_TOKEN and GH_REPO set; writes `shards` to $GITHUB_OUTPUT
    python3 -I scripts/ci-requeue-plan.py --selftest

A shard whose runner's simulator service is broken (scripts/ci-broken-runner.sh) ends green without running its tests
and prints MARK. This reads the log of every shard of the suite that ended green in the run's latest attempt and lists
those that carry MARK, as the requeue job's matrix: `[{"shard": 3, "device": "iPhone"}]` for the gallery, `[{"shard":
2}]` or `[{"shard": "ipad"}]` for Ouro Feel, `[]` when none. A log it cannot read fails the job, so the required check
fails closed rather than counting an untested shard as passed.
"""
import json
import os
import re
import subprocess
import sys

MARK = "ouro-ci: broken runner, requeue this shard (#74)"
SUITES = {
    "gallery": [(re.compile(r"^Gallery UI shard (\d+) of \d+ on (\w+) \("), lambda m: {"shard": int(m[1]), "device": m[2]})],
    "feel": [(re.compile(r"^Ouro Feel shard (\d+) of \d+ \("), lambda m: {"shard": int(m[1])}),
             (re.compile(r"^Ouro Feel on an iPad\b"), lambda m: {"shard": "ipad"})],
}


def entry(suite, name):
    """The matrix entry a first-run shard job of `suite` named `name` ran, or None for any other job."""
    if "requeued" in name:
        return None
    for pattern, make in SUITES[suite]:
        m = pattern.match(name)
        if m:
            return make(m)
    return None


def plan(suite, jobs, log):
    """`jobs`: [{"id", "name", "conclusion"}]; `log(id)`: that job's log text. The shards to requeue, in job order."""
    out = []
    for job in jobs:
        e = entry(suite, job["name"])
        if e is not None and job.get("conclusion") == "success" and MARK in log(job["id"]):
            out.append(e)
    return out


def gh(*args):
    return subprocess.run(["gh", "api", *args], capture_output=True, text=True, check=True, timeout=120).stdout


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    suite, run = argv
    repo = os.environ["GH_REPO"]
    jobs = []
    for page in gh("--paginate", f"repos/{repo}/actions/runs/{run}/jobs?filter=latest&per_page=100", "--jq", ".jobs[]|{id,name,conclusion}").splitlines():
        jobs.append(json.loads(page))
    shards = plan(suite, jobs, lambda i: gh(f"repos/{repo}/actions/jobs/{i}/logs"))
    print(f"{suite}: requeue {json.dumps(shards)}" if shards else f"{suite}: no shard needs a requeue")
    with open(os.environ["GITHUB_OUTPUT"], "a") as f:
        f.write(f"shards={json.dumps(shards)}\n")
    return 0


def selftest():
    jobs = [{"id": 1, "name": "Gallery UI shard 3 of 4 on iPhone (free macos-26, Xcode 26)", "conclusion": "success"},
            {"id": 2, "name": "Gallery UI shard 1 of 4 on iPad (free macos-26, Xcode 26)", "conclusion": "success"},
            {"id": 3, "name": "Gallery UI shard 2 of 4 on iPhone (free macos-26, Xcode 26)", "conclusion": "failure"},
            {"id": 4, "name": "Gallery UI shard 4 of 4 on iPhone, requeued on a fresh runner (free macos-26, Xcode 26)", "conclusion": "success"},
            {"id": 5, "name": "Ouro Feel shard 2 of 3 (free macos-26, Xcode 26)", "conclusion": "success"},
            {"id": 6, "name": "Ouro Feel on an iPad, the iPhone fixture in compatibility mode (free macos-26, Xcode 26)", "conclusion": "success"},
            {"id": 7, "name": "Gallery UI tests, the component claims (free macos-26, Xcode 26)", "conclusion": "success"}]
    marked = {1, 3, 4, 5, 6, 7}
    log = lambda i: f"...\n{MARK}\n" if i in marked else "Executed 4 tests, with 0 failures"
    assert plan("gallery", jobs, log) == [{"shard": 3, "device": "iPhone"}], \
        "a green marked first-run shard is requeued; a red one, a requeued one and the summary are not"
    assert plan("feel", jobs, log) == [{"shard": 2}, {"shard": "ipad"}], "Feel's shards and its iPad lane"
    assert plan("gallery", jobs, lambda i: "") == [], "nothing marked, nothing requeued"
    print("ci-requeue-plan: selftest passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
