#!/bin/sh
# CI only: find a build job's test products for a shard, including after "re-run failed jobs".
#
#   sh scripts/ci-wait-for-build.sh <artifact prefix> <build job name prefix>
#
# The build uploads `<prefix><run attempt>`. This prints `name=<artifact>` to $GITHUB_OUTPUT once this attempt's build
# is uploaded. When this attempt didn't rerun the build ("re-run failed jobs" carries it over), it takes the newest
# earlier attempt's build of the same commit and Xcode, which is the same build. The job's `run_attempt` can't tell a
# carried-over build from a rebuild (GitHub lists both under this attempt, #79), so a build that succeeded without an
# upload from this attempt also falls back. It stops at once if the build job
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
      # The artifacts API can take a minute or more to list a fresh upload: on main's run 42447094866 one shard,
      # 6 s after the upload, failed here while the two beside it found it. So a succeeded build's upload gets
      # WAIT_LISTED_CHECKS more looks, WAIT_RECHECK seconds apart, before this fails. On a rerun an earlier attempt's
      # upload is already listed, so a shard may take it during the delay; it is the same commit and Xcode.
      checks=0
      while :; do
        name="$(pick current)"
        # GitHub lists a build that "re-run failed jobs" carried over under this attempt's number (#79), so the check
        # above can't tell it from a rebuild. An earlier attempt's upload of this prefix is the same commit and Xcode.
        [ -n "$name" ] || { name="$(pick any)"; [ -z "$name" ] || echo "::notice::No upload from attempt $GITHUB_RUN_ATTEMPT; testing $name, the same commit and Xcode"; }
        [ -z "$name" ] && [ "$checks" -lt "${WAIT_LISTED_CHECKS:-24}" ] || break
        sleep "${WAIT_RECHECK:-10}"; checks=$((checks + 1))
      done
      test -n "$name" || { echo "::error::$JOB succeeded, but after $checks more looks no unexpired upload starts $PREFIX: this shard's Xcode differs from the build's, or the build expired (kept 2 days; re-run all jobs)"; exit 1; }
    fi
  fi
  if [ -n "$name" ]; then echo "Testing $name"; echo "name=$name" >> "$GITHUB_OUTPUT"; exit 0; fi
  sleep "${WAIT_POLL:-15}"
done
