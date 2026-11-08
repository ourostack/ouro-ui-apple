#!/bin/sh
# Checks scripts/ci-wait-for-build.sh against a fake `gh`, offline: sh scripts/test-ci-wait-for-build.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
mkdir -p "$work/bin"
# The fake prints what the real call's --jq would: artifact names, or "<run_attempt> <conclusion>" for the build job.
cat > "$work/bin/gh" <<'GH'
#!/bin/sh
case "$*" in
  *"/artifacts"*) printf '%s\n' $FAKE_ARTIFACTS ;;
  *"/jobs"*) echo "$FAKE_BUILD" ;;
esac
GH
chmod +x "$work/bin/gh"
P=gallery-tests-abc-xcode-26.6-17F113-attempt-
failures=0
# check <what> <attempt> <artifacts> <build state> <expected name, or "fail">
check() {
  out="$work/out.$$"; : > "$out"
  PATH="$work/bin:$PATH" GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=1 GITHUB_RUN_ATTEMPT="$2" GITHUB_OUTPUT="$out" \
    FAKE_ARTIFACTS="$3" FAKE_BUILD="$4" WAIT_RECHECK=0 WAIT_POLL=0 \
    sh "$here/ci-wait-for-build.sh" "$P" "Gallery build for testing" > "$work/log" 2>&1 && status=0 || status=$?
  got="$(sed -n 's/^name=//p' "$out")"
  if [ "$5" = fail ]; then
    if [ "$status" -ne 0 ] && [ -z "$got" ]; then echo "ok: $1"; else echo "FAIL: $1 (wanted a failure, got '$got')"; failures=$((failures + 1)); fi
  elif [ "$status" -eq 0 ] && [ "$got" = "$5" ]; then echo "ok: $1"
  else echo "FAIL: $1 (wanted $5, got '$got', status $status)"; cat "$work/log"; failures=$((failures + 1)); fi
}
check "this attempt's build" 1 "${P}1" "1 success" "${P}1"
check "re-run failed jobs: the carried-over build is listed with this attempt's number (#79)" 2 "${P}1" "2 success" "${P}1"
check "re-run failed jobs, listed with the attempt it ran in" 3 "${P}1" "1 success" "${P}1"
check "the newest earlier build" 3 "${P}1 ${P}2" "3 success" "${P}2"
check "a rebuilt attempt uses its own build" 2 "${P}1 ${P}2" "2 success" "${P}2"
check "the build failed" 2 "" "2 failure" fail
check "the build succeeded for another Xcode" 1 "gallery-tests-abc-xcode-27.0-1A1-attempt-1" "1 success" fail
test "$failures" -eq 0
