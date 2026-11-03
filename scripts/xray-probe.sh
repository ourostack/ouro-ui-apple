#!/bin/sh
# The X-ray's behaviour stage, end to end, for CI: plans from the app's metadata, runs Templates/XrayProbe against the
# installed app with AppIntentsTesting, and writes the merged report. On iOS it creates its own simulator, which makes
# the device disposable, and deletes it by UDID when done. On macOS it opens the app on this Mac. Pass --disposable to
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
  # The first launch lets the app create its content and index it, as a person's first launch would.
  xcrun simctl launch "$udid" "$bundle_id" >/dev/null
  sleep 8
  plan="$("$xray" plan --app "$app" $disposable)"
  set +e
  TEST_RUNNER_OURO_AX_PLAN="$plan" TEST_RUNNER_OURO_AX_DISPOSABLE="$([ -n "$disposable" ] && echo 1 || echo 0)" TEST_RUNNER_OURO_AX_RAN_ON="iOS $runtime Simulator ($device_type), $(head -1 "$out/xcode.txt")" \
    xcodebuild test -project "$here/Templates/XrayProbe/XrayProbe.xcodeproj" -scheme XrayProbe-iOS -destination "id=$udid" -retry-tests-on-failure -test-iterations 2 \
    -derivedDataPath "$here/.build/xray-probe-ios" > "$out/probe.log" 2>&1
  status=$?
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
