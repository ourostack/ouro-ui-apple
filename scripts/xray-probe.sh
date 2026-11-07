#!/bin/sh
# The X-ray's behaviour stage, end to end, for CI: plans from the app's metadata, runs Templates/XrayProbe against the
# installed app with AppIntentsTesting, and writes the merged report. On iOS it creates its own simulator and deletes
# it by UDID when done. On macOS it opens the app on this Mac. Pass --disposable to
# allow refusal runs and import read-backs, which may write: only when the device and the app's backend are throwaway.
#
#   sh scripts/xray-probe.sh --app <path.app> --out <dir> [--platform ios|macos] [--runtime 27.1]
#     [--device-type "iPhone Duo"] [--commit <sha>] [--name <name>] [--disposable]
#
# Run it with DEVELOPER_DIR set to an Xcode whose AppIntentsTesting matches the OS it runs on, and build the app with
# the same Xcode. XRAY names the ouro-ax-xray binary (default: .build/release/ouro-ax-xray).
set -eu
app=""; out=""; platform="ios"; runtime="27.1"; device_type="iPhone Duo"; commit=""; name=""; disposable=""
while [ $# -gt 0 ]; do
  case "$1" in
    --app) app="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --platform) platform="$2"; shift 2 ;;
    --runtime) runtime="$2"; shift 2 ;;
    --device-type) device_type="$2"; shift 2 ;;
    --commit) commit="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --disposable) disposable="--disposable"; shift ;;
    *) echo "xray-probe: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$app" ] && [ -n "$out" ] || { echo "xray-probe: --app and --out are required" >&2; exit 2; }
here="$(cd "$(dirname "$0")/.." && pwd)"
xray="${XRAY:-$here/.build/release/ouro-ax-xray}"
mkdir -p "$out"
(cd "$here/Templates/XrayProbe" && xcodegen generate >/dev/null)
xcodebuild -version | tee "$out/xcode.txt"

if [ "$platform" = "ios" ]; then
  plist="$app/Info.plist"
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
  runtime_id="$(xcrun simctl list runtimes -j | python3 -I -c 'import json,sys; v=sys.argv[1]; rs=[r for r in json.load(sys.stdin)["runtimes"] if r.get("platform")=="iOS" and r.get("isAvailable") and (r["version"]==v or r["version"].startswith(v+"."))]; print(rs[-1]["identifier"] if rs else "")' "$runtime")"
  type_id="$(xcrun simctl list devicetypes -j | python3 -I -c 'import json,sys; n=sys.argv[1]; ts=[t for t in json.load(sys.stdin)["devicetypes"] if t["name"]==n]; print(ts[0]["identifier"] if ts else "")' "$device_type")"
  [ -n "$runtime_id" ] && [ -n "$type_id" ] || { echo "xray-probe: no iOS $runtime runtime or no $device_type device type" >&2; xcrun simctl list runtimes >&2; exit 1; }
  udid="$(xcrun simctl create "ouro-ax-xray-$$" "$type_id" "$runtime_id")"
  echo "simulator $udid ($device_type, $runtime_id)"
  trap 'xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; xcrun simctl delete "$udid" || true' EXIT
  trap 'exit 130' INT TERM
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl install "$udid" "$app"
  # Stops the app and waits for it to exit, so XCTest launches it from nothing: a copy still running when XCTest
  # launches races XCTest's own terminate and relaunch, and the launch can fail with no process ID (#36).
  stop_app() {
    xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
    # The app's job is listed as "<pid> <status> UIKitApplication:<bundle id>[<instance>]...", with "-" for a pid once
    # it has exited. If the list cannot be read at all, say so rather than take silence for a stopped app.
    i=0
    while :; do
      if ! jobs="$(xcrun simctl spawn "$udid" launchctl list 2>&1)"; then
        echo "xray-probe: could not list the simulator's jobs, so whether $bundle_id stopped is unknown: $jobs" >&2
        return 0
      fi
      printf '%s\n' "$jobs" \
        | awk -v job="UIKitApplication:$bundle_id[" 'index($3, job) == 1 && $1 ~ /^[0-9]+$/ { found = 1 } END { exit !found }' \
        || return 0
      i=$((i + 1))
      if [ "$i" -ge 40 ]; then
        echo "xray-probe: $bundle_id was still running 20 s after it was told to stop" >&2
        return 0
      fi
      sleep 0.5
    done
  }
  # The first launch lets the app create its content and index it, as a person's first launch would.
  first_launch() {
    xcrun simctl launch "$udid" "$bundle_id" >/dev/null
    sleep 8
    stop_app
  }
  first_launch
  plan="$("$xray" plan --app "$app" $disposable)"
  ios_probe() {
    TEST_RUNNER_OURO_AX_PLAN="$plan" TEST_RUNNER_OURO_AX_DISPOSABLE="$([ -n "$disposable" ] && echo 1 || echo 0)" TEST_RUNNER_OURO_AX_RAN_ON="iOS $runtime Simulator ($device_type), $(head -1 "$out/xcode.txt")" \
      xcodebuild test -project "$here/Templates/XrayProbe/XrayProbe.xcodeproj" -scheme XrayProbe-iOS -destination "id=$udid" -retry-tests-on-failure -test-iterations 2 \
      -derivedDataPath "$here/.build/xray-probe-ios" > "$1" 2>&1
  }
  set +e
  ios_probe "$out/probe.log"
  status=$?
  # A probe that never reached the app ran nothing, and xcodebuild's own retry does not help: a test runner that crashed
  # before any test started ("never finished bootstrapping"), or an app XCTest could not launch (no process ID, or it
  # never reached the foreground; see XrayProbeTests). Reboot the simulator and run once more; the first log is kept
  # beside the report.
  if ! grep -q OURO-AX-PROBE-BEGIN "$out/probe.log" \
      && grep -qE "never finished bootstrapping|does not have a process ID|Failed to launch.*process ID|OURO-AX-PROBE-UNREACHED" "$out/probe.log"; then
    echo "xray-probe: the probe never reached the app (see probe-first-try.log); rebooting the simulator and trying once more"
    if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::warning::xray-probe: the first probe run never reached the app; retried once (see probe-first-try.log)"; fi
    mv "$out/probe.log" "$out/probe-first-try.log"
    xcrun simctl shutdown "$udid" >/dev/null 2>&1
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" -b >/dev/null
    first_launch
    ios_probe "$out/probe.log"
    status=$?
  fi
  set -e
else
  plist="$app/Contents/Info.plist"
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
  open "$app"
  sleep 8
  plan="$("$xray" plan --app "$app" $disposable)"
  set +e
  TEST_RUNNER_OURO_AX_PLAN="$plan" TEST_RUNNER_OURO_AX_DISPOSABLE="$([ -n "$disposable" ] && echo 1 || echo 0)" TEST_RUNNER_OURO_AX_RAN_ON="macOS $(sw_vers -productVersion), $(head -1 "$out/xcode.txt")" \
    xcodebuild test -project "$here/Templates/XrayProbe/XrayProbe.xcodeproj" -scheme XrayProbe-macOS -destination "platform=macOS" \
    -derivedDataPath "$here/.build/xray-probe-mac" > "$out/probe.log" 2>&1
  status=$?
  set -e
  osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
fi

echo "probe test exit $status"
grep -E "Symbol not found|Test Case|error:|skipped" "$out/probe.log" | head -20 || true
set -- --app "$app" --out "$out" --format text
[ -n "$commit" ] && set -- "$@" --commit "$commit"
[ -n "$name" ] && set -- "$@" --name "$name"
if grep -q OURO-AX-PROBE-BEGIN "$out/probe.log"; then
  "$xray" "$@" --probe "$out/probe.log"
else
  echo "xray-probe: the probe printed no result; the report has the metadata stage only" >&2
  "$xray" "$@"
  exit 1
fi
