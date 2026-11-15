#!/bin/bash
# api-break.sh: compare this checkout's public API with the last release tag (README, "Source stability").
#
# Runs `swift package diagnose-api-breaking-changes` over every library product against the newest vX.Y.Z tag the
# checkout contains. A break fails from 0.9.0 on, unless the pull request's title (PR_TITLE) starts "Breaking:";
# before 0.9.0 it is reported only. Exit 0 when nothing public changed that a caller would notice.
set -uo pipefail
base=$(git tag --merged HEAD --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -1)
if [ -z "$base" ]; then echo "No release tag in this checkout's history; fetch with tags (fetch-depth: 0)."; exit 1; fi
version=${base#v}; major=${version%%.*}; rest=${version#*.}; minor=${rest%%.*}
enforced=0; if [ "$major" -ge 1 ] || [ "$minor" -ge 9 ]; then enforced=1; fi
echo "Comparing the public API with $base (breaks $( [ $enforced = 1 ] && echo fail || echo 'are reported only, before 0.9.0'))."
out=$(swift package diagnose-api-breaking-changes "$base" 2>&1); status=$?
echo "$out"
breaks=$(printf '%s\n' "$out" | grep -E 'API breakage:' || true)
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
if [ $status -eq 0 ] && [ -z "$breaks" ]; then
  echo "### Public API: no break since $base" >> "$summary"; exit 0
fi
if [ -z "$breaks" ]; then echo "The comparison itself failed (exit $status), not a break: read the log above."; exit $status; fi
{ echo "### Public API: breaks since $base"; echo; printf '%s\n' "$breaks" | sed 's/^/- /'; } >> "$summary"
if [ $enforced = 0 ]; then echo "Reported only: the gate fails from 0.9.0."; exit 0; fi
case "${PR_TITLE:-}" in Breaking:*) echo "The title says Breaking:, so this break waits for the next major."; exit 0;; esac
echo "This breaks the public API. Keep the old declaration (deprecate it), or title the pull request \"Breaking: ...\" so it waits for 2.0."
exit 1
