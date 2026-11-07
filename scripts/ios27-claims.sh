#!/bin/sh
# The release step for iOS 27 (RELEASING.md): runs the gallery's component claims (ComponentClaimTests) on an iOS 27
# simulator you created for it, and writes the whole log, with the Xcode and runtime it ran on, to one file:
#   udid=$(xcrun simctl create ouro-hx-ios27 "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-27-2)
#   sh scripts/ios27-claims.sh <that UDID> .build/ios27-claims-vX.Y.Z.txt
#   xcrun simctl delete <that UDID>
# It never creates or deletes a simulator, so it cannot touch one you already use. It exits non-zero when any claim
# fails; the release waits for it to pass, and the log is attached to the release.
# It runs from the repository root wherever it is called from, and refuses a checkout with changes, so the commit the
# log names is the code that ran. Pick the Xcode with DEVELOPER_DIR, never xcode-select.
set -eu
udid="$1"
mkdir -p "$(dirname "$2")"
log="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
cd "$(dirname "$0")/.."
if [ -n "$(git status --porcelain)" ]; then
  echo "ios27-claims: the checkout has changes; run it on a clean checkout of the commit you will tag" >&2
  git status --short >&2
  exit 2
fi
runtime="$(xcrun simctl list devices -j | python3 -I -c 'import json,sys; u=sys.argv[1]; print(next(r for r,ds in json.load(sys.stdin)["devices"].items() for d in ds if d["udid"]==u))' "$udid")"
case "$runtime" in *iOS-27*) ;; *) echo "ios27-claims: $udid runs $runtime, not iOS 27" >&2; exit 2 ;; esac
{
  echo "commit: $(git rev-parse HEAD)"
  echo "runtime: $runtime"
  xcodebuild -version
} > "$log"
(cd Examples/OuroHXGallery && xcodegen generate >/dev/null)
status=0
xcodebuild test -project Examples/OuroHXGallery/OuroHXGallery.xcodeproj -scheme OuroHXGallery -destination "id=$udid" \
  -derivedDataPath .build/gallery CODE_SIGNING_ALLOWED=NO -only-testing:OuroHXGalleryUITests/ComponentClaimTests >> "$log" 2>&1 || status=$?
grep -E "Test Case .*(passed|failed)" "$log" | sed 's/.*ComponentClaimTests //' || true
if [ "$status" -eq 0 ]; then echo "ios27-claims: every claim passed on $runtime ($log)"; else echo "ios27-claims: FAILED on $runtime ($log)" >&2; fi
exit "$status"
