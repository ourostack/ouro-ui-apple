#!/bin/sh
# Checks scripts/ci-ui-infra.sh against sample logs, offline: sh scripts/test-ci-ui-infra.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
failures=0
# check <what> <expected: retry|fail> <log lines...>
check() {
  what="$1"; want="$2"; shift 2
  printf '%s\n' "$@" > "$work/log"
  cause="$(sh "$here/ci-ui-infra.sh" "$work/log")" && got=retry || got=fail
  if [ "$got" = "$want" ]; then echo "ok: $what${cause:+ ($cause)}"; else echo "FAIL: $what (wanted $want, got $got)"; failures=$((failures + 1)); fi
}
E="/Users/runner/work/x/UITests/FeelCatchesTests.swift:66: error: -[FeelCatchesTests testAPushFilmedInTheApp] : failed - FAIL snap"
check "testmanagerd lost" retry "Lost connection to testmanagerd" "** TEST FAILED **"
check "accessibility lost mid-run (#84)" retry \
  "<unknown>:0: error: -[OuroFeelFixtureUITests.FeelCatchesTests testFlicker] : Failed to get list of active applications: Error Domain=XCTDaemonErrorDomain Code=13" \
  "Test Case '-[OuroFeelFixtureUITests.FeelCatchesTests testFlicker]' failed (75.274 seconds)."
check "only screenshot timeouts (#43)" retry \
  "<unknown>:0: error: -[G testA] : Failed to get screenshot: Timed out while requesting screenshot"
check "a screenshot timeout next to a real assertion" fail \
  "<unknown>:0: error: -[G testA] : Failed to get screenshot: Timed out while requesting screenshot" "$E"
check "a real assertion" fail "$E" "** TEST FAILED **"
check "a run that passed" fail "** TEST SUCCEEDED **"
test "$failures" -eq 0
