#!/bin/sh
# CI only: did a UI test run fail because of the machine rather than the app?
#
#   sh scripts/ci-ui-infra.sh <xcodebuild log> [result bundle]
#
# Prints the cause and exits 0 when the run earns one more go on a rebooted simulator; exits 1 otherwise. The retry
# reruns the whole shard, so a real failure next to a machine one still fails. Machine failures:
# - the runner lost testmanagerd, never bootstrapped, or couldn't find the simulator it just booted (#42);
# - the simulator's accessibility went away mid-run: "Failed to get list of active applications" (#84);
# - every failure is a screenshot request the simulator never answered (#43). A real assertion next to one still fails.
set -u
log="$1"; bundle="${2:-}"
{ cat "$log"; test -n "$bundle" && xcrun xcresulttool get test-results summary --path "$bundle" 2>/dev/null; } |
  grep -m1 -oE "Lost connection to testmanagerd|never finished bootstrapping|Test runner exited before starting test execution|Failed to establish communication with the test runner|Unable to find a device matching the provided destination specifier|Failed to get list of active applications" && exit 0
failures="$(grep -c ': error: -\[' "$log" || true)"
timeouts="$(grep -c ': error: -\[.*Failed to get screenshot: Timed out while requesting screenshot' "$log" || true)"
if [ "$timeouts" -gt 0 ] && [ "$timeouts" -eq "$failures" ]; then echo "Timed out while requesting screenshot"; exit 0; fi
exit 1
