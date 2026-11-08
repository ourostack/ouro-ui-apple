#!/bin/sh
# CI only: find a build job's test products for a shard, including after "re-run failed jobs".
#
#   sh scripts/ci-wait-for-build.sh <artifact prefix> <build job name prefix>
#
# The build uploads `<prefix><run attempt>`. This prints `name=<artifact>` to $GITHUB_OUTPUT once this attempt's build
# is uploaded. When this attempt didn't rerun the build ("re-run failed jobs" carries it over), it takes the newest
# earlier attempt's build of the same commit and Xcode, which is the same build. It stops at once if the build job
# failed, was cancelled or was skipped, and fails if the build succeeded without uploading what this shard needs
# (its Xcode differs from the build's). Needs GH_TOKEN with actions: read.
set -eu
PREFIX="$1"; JOB="$2"
names() {
  gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/artifacts?per_page=100" \
    --jq '.artifacts[] | select(.expired | not) | .name' 2>/dev/null | grep -F "$PREFIX" || true
}
# `current`: this attempt's build. `any`: the newest attempt's build of this commit and Xcode.
pick() {
  if [ "$1" = current ]; then names | grep -xF "$PREFIX$GITHUB_RUN_ATTEMPT" || true
  else names | sed "s/^.*-attempt-//" | sort -n | tail -1 | sed "s/^/$PREFIX/" | grep -F "$PREFIX" || true; fi
}
# "<attempt the build job ran in> <its conclusion>", or "0 " when this attempt lists no build job.
build_state() {
  gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/attempts/$GITHUB_RUN_ATTEMPT/jobs?per_page=100" \
    --jq "[.jobs[] | select(.name | startswith(\"$JOB\"))][0] // {} | \"\\(.run_attempt // 0) \\(.conclusion // \"\")\"" \
    2>/dev/null || echo "0 "
}
while :; do
  name="$(pick current)"
  if [ -z "$name" ]; then
    # shellcheck disable=SC2046
    set -- $(build_state); built_in="${1:-0}"; conclusion="${2:-}"
    case "$conclusion" in failure|cancelled|skipped|timed_out) echo "::error::$JOB ended $conclusion; nothing to test"; exit 1 ;; esac
    if [ "$built_in" != "$GITHUB_RUN_ATTEMPT" ]; then name="$(pick any)"; fi
    if [ -z "$name" ] && [ "$conclusion" = success ]; then
      sleep "${WAIT_RECHECK:-10}"; name="$(pick current)"
      # GitHub lists a build that "re-run failed jobs" carried over under this attempt's number (#79), so the check
      # above can't tell it from a rebuild. An earlier attempt's upload of this prefix is the same commit and Xcode.
      [ -n "$name" ] || name="$(pick any)"
      test -n "$name" || { echo "::error::$JOB succeeded without uploading $PREFIX$GITHUB_RUN_ATTEMPT: this shard's Xcode differs from the build's"; exit 1; }
    fi
  fi
  if [ -n "$name" ]; then echo "Testing $name"; echo "name=$name" >> "$GITHUB_OUTPUT"; exit 0; fi
  sleep "${WAIT_POLL:-15}"
done
