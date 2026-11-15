#!/bin/sh
# CI only: did a UI test run fail because of the machine rather than the app?
#
#   sh scripts/ci-ui-infra.sh <xcodebuild log> [result bundle]
#
# Prints the cause and exits 0 when the run earns one more go on a rebooted simulator; exits 1 otherwise. The retry
# reruns the whole shard, so a real failure next to a machine one still fails. Machine failures:
# - the runner lost testmanagerd, never bootstrapped, or couldn't find the simulator it just booted (#42);
# - the simulator's accessibility went away mid-run: "Failed to get list of active applications" (#84);
# - every failure is the simulator not answering: a screenshot request it never answered (#43), an app launch it
#   timed out ("Timed out while launching application via Xcode") or an app it never handed back ("Failed to get
#   background assertion for target app"), both seen on 2026-11-15 with no test code run. A real assertion next to
#   one still fails.
set -u
log="$1"; bundle="${2:-}"
{ cat "$log"; test -n "$bundle" && xcrun xcresulttool get test-results summary --path "$bundle" 2>/dev/null; } |
  grep -m1 -oE "Lost connection to testmanagerd|never finished bootstrapping|Test runner exited before starting test execution|Failed to establish communication with the test runner|Unable to find a device matching the provided destination specifier|Failed to get list of active applications" && exit 0
failures="$(grep -c ': error: -\[' "$log" || true)"
unanswered='Failed to get screenshot: Timed out while requesting screenshot|Timed out while launching application via Xcode|Failed to get background assertion for target app'
timeouts="$(grep -cE ": error: -\[.*($unanswered)" "$log" || true)"
if [ "$timeouts" -gt 0 ] && [ "$timeouts" -eq "$failures" ]; then
  grep -m1 -oE ": error: -\[.*($unanswered)" "$log" | grep -oE "$unanswered"; exit 0
fi
exit 1
