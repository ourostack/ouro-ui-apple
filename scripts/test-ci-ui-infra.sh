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
check "accessibility never loaded, so the runner never started (#289)" retry \
  "Testing failed:" \
  "	OuroFeelFixtureUITests-Runner (5323) encountered an error (The test runner failed to initialize for UI testing. (Underlying Error: Timed out waiting for AX loaded notification))" \
  "** TEST EXECUTE FAILED **"
check "only screenshot timeouts (#43)" retry \
  "<unknown>:0: error: -[G testA] : Failed to get screenshot: Timed out while requesting screenshot"
check "a screenshot timeout next to a real assertion" fail \
  "<unknown>:0: error: -[G testA] : Failed to get screenshot: Timed out while requesting screenshot" "$E"
check "an app launch the simulator timed out, and an app it never handed back" retry \
  "<unknown>:0: error: -[FeelCatchesTests testAPushUnderATabBar] : Failed to launch <XCUIApplicationImpl: 0x1 bot.ouro.feel.fixture> via Xcode: Timed out while launching application via Xcode." \
  "<unknown>:0: error: -[FeelCatchesTests testLateOrLingeringChrome] : Failed to get background assertion for target app with pid 0: No failure details provided"
check "an app launch the simulator never reported on (#267)" retry \
  "<unknown>:0: error: -[OuroHXGalleryUITests.ComponentClaimTests testAnEmptyStatesSymbolSitsAboveItsTitle] : Failed to get launch progress for <XCUIApplicationImpl: 0x106bcfa40 bot.ouro.hx.gallery at /Users/runner/work/x/OuroHXGallery.app>: Timed out while requesting launch progress."
check "a launch it never reported on next to a real assertion" fail \
  "<unknown>:0: error: -[G testA] : Failed to get launch progress for <XCUIApplicationImpl: 0x1 bot.ouro.hx.gallery>" "$E"
check "a launch timeout next to a real assertion" fail \
  "<unknown>:0: error: -[G testA] : Failed to launch <X> via Xcode: Timed out while launching application via Xcode." "$E"
check "xcodebuild hung and the watch stopped it (#164)" retry \
  "<unknown>:0: error: -[G testA] : Failed to launch <X> via Xcode: Timed out while launching application via Xcode." \
  "Details:  DTServiceHub - Error resuming pid 6807 'Error Domain=DTXMessage Code=1 \"Failed to send signal 19 to process 6807: 3\"'" \
  "ci-quiet-watch: xcodebuild wrote nothing for 600 s; stopped it (#164)"
check "a real assertion" fail "$E" "** TEST FAILED **"
check "a run that passed" fail "** TEST SUCCEEDED **"
# The watch itself: a command that goes quiet is stopped with 124 and the line above; one that finishes keeps its status.
OURO_QUIET_WATCH_NAP=1 sh "$here/ci-quiet-watch.sh" 2 "$work/quiet.log" sh -c 'echo started; exec sleep 30'; got=$?
if [ "$got" -eq 124 ] && grep -q "wrote nothing for 2 s" "$work/quiet.log" && sh "$here/ci-ui-infra.sh" "$work/quiet.log" >/dev/null; then
  echo "ok: a quiet command is stopped and earns its retry"
else echo "FAIL: a quiet command (status $got)"; failures=$((failures + 1)); fi
OURO_QUIET_WATCH_NAP=1 sh "$here/ci-quiet-watch.sh" 5 "$work/busy.log" sh -c 'echo one; sleep 2; echo two; exit 3'; got=$?
if [ "$got" -eq 3 ] && grep -q two "$work/busy.log" && ! grep -q "wrote nothing" "$work/busy.log"; then
  echo "ok: a command that finishes keeps its status and output"
else echo "FAIL: a command that finishes (status $got)"; failures=$((failures + 1)); fi
test "$failures" -eq 0
