#!/usr/bin/env python3
"""CI only: rerun a CI or accessibility pass run's failed jobs once when every failure was a runner whose simulator service was broken (#74).

    python3 -I scripts/ci-rerun-broken-runner.py <run id>     # GH_TOKEN and GH_REPO set; called by rerun-broken-runner.yml
    python3 -I scripts/ci-rerun-broken-runner.py --selftest

`ci-simulator.py` restarts CoreSimulator three times when `simctl list runtimes` hangs. When it still hangs, it fails the
job with "This runner's simulator service is broken; no app code ran (#74)", because a restart on the same runner
doesn't help. A fresh runner does. On 2026-11-15 that happened four times in one morning, and each one waited for a
person to rerun the job.

This reruns the failed jobs on fresh runners, once (the run's first attempt only), and only when every failed job
either carries that line or is a job that fails because one that did failed (the two required summary checks). A real
failure next to a broken runner leaves the run as it is, for a person. Report-only jobs (the hitch probe) are ignored.

Since #74's requeue, a gallery or Ouro Feel shard on a broken runner doesn't fail: it ends at once and its requeue job
runs it on a fresh runner within the same run (scripts/ci-broken-runner.sh, scripts/ci-requeue-plan.py). This is the
next layer: a requeued shard that lands on a second broken runner fails with the line above, and so do the X-ray lanes.
"""
import json
import re
import subprocess
import sys

# ci-simulator.py's own line, and ci-broken-runner.sh's for a requeued shard on a second bad runner (broken or slow, #199).
MARK = re.compile(r"no app code ran \(#74\)|not the app; rerun it on a fresh runner \(#74\)")
# Required checks that fail only because a job they wait for failed.
SUMMARIES = {"Gallery UI tests, the component claims (free macos-26, Xcode 26)", "Ouro Feel catches every genre's bug (free macos-26, Xcode 26)"}
REPORT_ONLY = ("Gallery hitch probe",)


def decide(failed):
    """`failed`: [(job name, log text)]. Returns (rerun?, reason)."""
    if not failed:
        return False, "no failed jobs"
    broken = [name for name, log in failed if MARK.search(log)]
    other = [name for name, log in failed if not MARK.search(log) and name not in SUMMARIES and not name.startswith(REPORT_ONLY)]
    if not broken:
        return False, "no job failed on a broken simulator service"
    if other:
        return False, "other jobs failed too, so the run is left for a person: " + "; ".join(other)
    return True, "a broken simulator service stopped: " + "; ".join(broken)


def gh(*args):
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def evidence(repo, job_id):
    """The job's annotations, then its log. Annotations exist as soon as the job ends; a log GitHub hasn't stored yet
    reads as empty, which once read a broken runner as no broken runner at all (#201)."""
    text = []
    for path in (f"{repo}/check-runs/{job_id}/annotations", f"{repo}/actions/jobs/{job_id}/logs"):
        try:
            got = gh("api", path, *(["--jq", ".[].message"] if path.endswith("annotations") else []))
        except subprocess.CalledProcessError:
            continue
        text.append(got)
        if MARK.search(got):
            break
    return "\n".join(text)


def main(run_id):
    repo = "repos/{owner}/{repo}"
    jobs = json.loads(gh("api", "--paginate", f"{repo}/actions/runs/{run_id}/attempts/1/jobs", "--jq", "[.jobs[]|{id, name, conclusion}]"))
    failed = []
    for job in jobs:
        if job["conclusion"] != "failure":
            continue
        failed.append((job["name"], evidence(repo, job["id"])))
    rerun, why = decide(failed)
    print(("Rerunning the failed jobs: " if rerun else "Not rerunning: ") + why)
    if rerun:
        gh("api", "-X", "POST", f"{repo}/actions/runs/{run_id}/rerun-failed-jobs")


def selftest():
    hung = "##[error]simctl list runtimes hung past 30 s, 3 times, with CoreSimulator restarted between. This runner's simulator service is broken; no app code ran (#74)."
    shard = "Gallery UI shard 4 of 4 on iPhone (free macos-26, Xcode 26)"
    summary = "Gallery UI tests, the component claims (free macos-26, Xcode 26)"
    assert decide([(shard, hung), (summary, "")])[0], "a broken runner and its summary are rerun"
    assert decide([("Ouro Feel shard 1 of 3 (free macos-26, Xcode 26)", hung)])[0], "a Feel shard too"
    slow = "##[error]Ouro Feel shard 2: FeelCatchesTests/testX ran 535 s, 26 times its measured 20.6 s: the runner is too slow, on the fresh runner this shard was requeued on too. The runner failed, not the app; rerun it on a fresh runner (#74)."
    assert decide([("Ouro Feel shard 2 of 3, requeued on a fresh runner (free macos-26, Xcode 26)", slow)])[0], "a second slow runner too"
    assert decide([(shard, hung), ("Gallery hitch probe (main and releases, report only)", "error")])[0], "a report-only job doesn't block"
    assert not decide([(shard, hung), ("Gallery UI shard 2 of 4 on iPhone (free macos-26, Xcode 26)", "error: -[G testA] : failed")])[0], "a real failure beside it is left"
    assert not decide([(shard, "error: -[G testA] : failed"), (summary, "")])[0], "a real failure alone is left"
    assert not decide([(summary, "")])[0], "a summary alone is left"
    assert not decide([])[0]
    print("ok: ci-rerun-broken-runner selftest")


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
    elif len(sys.argv) == 2:
        main(sys.argv[1])
    else:
        sys.exit(__doc__)
