#!/bin/sh
# Is macOS proof on main green for this exact commit? Usage: sh scripts/release-gate.sh <owner/name> <sha>
# The newest CI push run on main for <sha> must have finished with success (its macOS jobs run only there, never on a
# pull request). Exit 0 green, 1 red, 2 no run yet or still running. Prints the reason.
set -u
repo="$1"; sha="$2"
row="$(gh api "repos/$repo/actions/workflows/ci.yml/runs?head_sha=$sha&event=push&branch=main&per_page=20" \
  --jq '[.workflow_runs[]] | sort_by(.created_at) | last | if . == null then "none" else "\(.status) \(.conclusion // "-") \(.html_url)" end')" || { echo "could not read CI runs for $sha"; exit 2; }
case "$row" in
  none) echo "CI has no push run on main for $sha: macOS has not been proven on it"; exit 2 ;;
  "completed success "*) echo "macOS proof is green on main for $sha: ${row##* }"; exit 0 ;;
  completed*) echo "CI on main for $sha finished ${row#completed }: red"; exit 1 ;;
  *) echo "CI on main for $sha is still running: ${row##* }"; exit 2 ;;
esac
