#!/bin/sh
# CI only: a shard's runner has a broken simulator service (#74), so requeue the shard on a fresh runner.
#
#   sh scripts/ci-broken-runner.sh "<what went wrong>"
#
# A restart of CoreSimulator on the same runner never recovered one (#74: four shards in an hour on 2026-11-15). So the
# first time, this marks the runner broken: it sets OURO_BROKEN_RUNNER=1 for the job's later steps, which then skip,
# and prints the line scripts/ci-requeue-plan.py looks for. The shard ends without running a test, and the shard's
# requeue job runs it again on a fresh runner once the other shards finish. The required check passes only when that
# requeued shard passes. In a requeued shard (OURO_REQUEUED=1) a second broken runner fails the job, with the line
# scripts/ci-rerun-broken-runner.py reruns on.
set -u
why="$1"
if [ "${OURO_REQUEUED:-0}" = 1 ]; then
  echo "::error title=Simulator could not start::$why, on the fresh runner this shard was requeued on too. This runner's simulator service is broken; no app code ran (#74)."
  exit 1
fi
echo "OURO_BROKEN_RUNNER=1" >> "$GITHUB_ENV"
echo "::warning title=Broken runner, requeued::$why. This shard ran no test to completion here; it runs again on a fresh runner once the other shards finish (#74)."
echo "ouro-ci: broken runner, requeue this shard (#74)"
