#!/bin/bash
# Ouro Feel's cold-start runner: runs one UI test N times, each on a fresh simulator, and reports the pass rate.
#
#   scripts/ouro-feel-cold.sh --project App.xcodeproj --scheme App --test AppUITests/FeelTests/testWayBack --runs 5
#
# Options:
#   --project P | --workspace W   the Xcode project or workspace (required)
#   --scheme S                    the scheme that builds the app and its UI tests (required)
#   --test ID                     an -only-testing identifier: Target/Class/method (required)
#   --runs N                      how many runs (default 3)
#   --device NAME                 simulator device type (default "iPhone 17 Pro")
#   --runtime ID                  simulator runtime identifier (default: the newest iOS runtime installed)
#   --udid U                      erase and reuse this simulator for each run instead of creating one
#   --warm                        one fresh simulator for all runs: run 1 is cold, the rest are warm (reported apart)
#   --out DIR                     where reports go (default .build/ouro-feel-cold)
#   --derived-data DIR            DerivedData for the one build (default .build/ouro-feel-dd)
#
# Name one test method in --test: with a whole class, only its first test really starts cold.
# Each run gets TEST_RUNNER_OURO_FEEL_START (cold or warm) and TEST_RUNNER_OURO_FEEL_REPORT_DIR, so every Ouro Feel
# report says how it started. It builds once (build-for-testing), then runs test-without-building. Simulators it creates
# are deleted when it ends, even on failure. Exit status: 0 when every run passed, 1 when any failed, 2 on bad usage.
set -u

project=(); scheme=""; test=""; runs=3; device="iPhone 17 Pro"; runtime=""; udid=""; warm=0
out=".build/ouro-feel-cold"; dd=".build/ouro-feel-dd"
while [ $# -gt 0 ]; do
  case "$1" in
    --project) project=(-project "$2"); shift 2 ;;
    --workspace) project=(-workspace "$2"); shift 2 ;;
    --scheme) scheme="$2"; shift 2 ;;
    --test) test="$2"; shift 2 ;;
    --runs) runs="$2"; shift 2 ;;
    --device) device="$2"; shift 2 ;;
    --runtime) runtime="$2"; shift 2 ;;
    --udid) udid="$2"; shift 2 ;;
    --warm) warm=1; shift ;;
    --out) out="$2"; shift 2 ;;
    --derived-data) dd="$2"; shift 2 ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "ouro-feel-cold: unknown option $1" >&2; exit 2 ;;
  esac
done
if [ ${#project[@]} -eq 0 ] || [ -z "$scheme" ] || [ -z "$test" ]; then
  echo "ouro-feel-cold: --project (or --workspace), --scheme and --test are required; see --help" >&2; exit 2
fi
case "$runs" in ''|*[!0-9]*|0) echo "ouro-feel-cold: --runs must be a number of at least 1" >&2; exit 2 ;; esac
if [ "$warm" = 1 ] && [ -n "$udid" ]; then echo "ouro-feel-cold: --warm and --udid do not combine; --udid erases before every run" >&2; exit 2; fi

if [ -z "$runtime" ] && [ -z "$udid" ]; then
  runtime="$(xcrun simctl list runtimes -j | python3 -I -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x["platform"]=="iOS" and x["isAvailable"]]; print(sorted(r,key=lambda x:[int(p) for p in x["version"].split(".")])[-1]["identifier"])')"
fi
mkdir -p "$out"
out="$(cd "$out" && pwd)"

created=()
cleanup() {
  for u in "${created[@]+"${created[@]}"}"; do
    [ -n "$u" ] || continue
    xcrun simctl shutdown "$u" >/dev/null 2>&1 || true
    xcrun simctl delete "$u" >/dev/null 2>&1 && echo "ouro-feel-cold: deleted simulator $u"
  done
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Sets `made` (not echoed through $(...), which would run in a subshell and hide `created` from the cleanup trap).
fresh() {
  made="$(xcrun simctl create "ouro-feel-cold-$$-$1" "$device" "$runtime")" || { echo "ouro-feel-cold: could not create a $device on $runtime" >&2; exit 2; }
  created+=("$made")
}

echo "ouro-feel-cold: building $scheme for testing"
if ! xcodebuild build-for-testing "${project[@]}" -scheme "$scheme" -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$dd" CODE_SIGNING_ALLOWED=NO > "$out/build.log" 2>&1; then
  tail -30 "$out/build.log"; echo "ouro-feel-cold: the build failed; the full log is $out/build.log" >&2; exit 2
fi
xctestrun="$(find "$dd/Build/Products" -maxdepth 1 -name '*.xctestrun' | head -1)"
[ -n "$xctestrun" ] || { echo "ouro-feel-cold: no .xctestrun in $dd/Build/Products" >&2; exit 2; }

shared=""
if [ "$warm" = 1 ]; then fresh warm; shared="$made"; fi

cold_pass=0; cold_runs=0; warm_pass=0; warm_runs=0; lines=""
i=0
while [ "$i" -lt "$runs" ]; do
  i=$((i+1))
  if [ -n "$udid" ]; then
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl erase "$udid" || { echo "ouro-feel-cold: could not erase $udid" >&2; exit 2; }
    sim="$udid"; start=cold
  elif [ -n "$shared" ]; then
    sim="$shared"; if [ "$i" = 1 ]; then start=cold; else start=warm; fi
  else
    fresh "$i"; sim="$made"; start=cold
  fi
  dir="$out/run-$i"; mkdir -p "$dir"
  started=$(date +%s)
  TEST_RUNNER_OURO_FEEL_START="$start" TEST_RUNNER_OURO_FEEL_REPORT_DIR="$dir/reports" \
    xcodebuild test-without-building -xctestrun "$xctestrun" -destination "id=$sim" -only-testing:"$test" \
    -resultBundlePath "$dir/result.xcresult" > "$dir/test.log" 2>&1
  status=$?
  seconds=$(( $(date +%s) - started ))
  if [ "$status" = 0 ]; then verdict=pass; else verdict=fail; fi
  if [ "$start" = cold ]; then cold_runs=$((cold_runs+1)); [ "$verdict" = pass ] && cold_pass=$((cold_pass+1))
  else warm_runs=$((warm_runs+1)); [ "$verdict" = pass ] && warm_pass=$((warm_pass+1)); fi
  echo "ouro-feel-cold: run $i ($start, simulator $sim): $verdict in ${seconds}s"
  lines="$lines{\"run\":$i,\"start\":\"$start\",\"simulator\":\"$sim\",\"passed\":$([ "$verdict" = pass ] && echo true || echo false),\"seconds\":$seconds},"
  # A fresh simulator per run: delete this one now rather than holding several.
  if [ -z "$udid" ] && [ -z "$shared" ]; then
    xcrun simctl shutdown "$sim" >/dev/null 2>&1 || true
    xcrun simctl delete "$sim" >/dev/null 2>&1
    created=("${created[@]/$sim}")
  fi
done

summary="$test on $device ($runtime${udid:+ simulator $udid}), simulator: cold $cold_pass of $cold_runs passed"
[ "$warm_runs" -gt 0 ] && summary="$summary; warm $warm_pass of $warm_runs passed (warm-only results: a cold start may differ)"
echo "$summary" | tee "$out/summary.txt"
printf '{"test":"%s","device":"%s","runtime":"%s","target":"simulator","cold":{"passed":%d,"runs":%d},"warm":{"passed":%d,"runs":%d},"runs":[%s]}\n' \
  "$test" "$device" "$runtime" "$cold_pass" "$cold_runs" "$warm_pass" "$warm_runs" "${lines%,}" > "$out/summary.json"
[ $((cold_pass + warm_pass)) = $((cold_runs + warm_runs)) ]
