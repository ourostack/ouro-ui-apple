#!/bin/sh
# Captures the gallery in light, dark and increased contrast on a simulator you created for it:
#   udid=$(xcrun simctl create ouro-hx-gallery "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-27-1)
#   sh scripts/gallery-captures.sh <that UDID> <output folder>
#   xcrun simctl delete <that UDID>
# It never creates or deletes a simulator, so it cannot touch one you already use.
set -eu
udid="$1"
out="$2"
mkdir -p "$out"
app=".build/gallery/Build/Products/Debug-iphonesimulator/OuroHXGallery.app"
test -d "$app" || { echo "build the gallery first (README, Gallery)"; exit 2; }
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl install "$udid" "$app"
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
shoot() { # theme page mode
  case "$3" in
    light) xcrun simctl ui "$udid" appearance light; xcrun simctl ui "$udid" increase_contrast disabled ;;
    dark) xcrun simctl ui "$udid" appearance dark; xcrun simctl ui "$udid" increase_contrast disabled ;;
    increased) xcrun simctl ui "$udid" appearance light; xcrun simctl ui "$udid" increase_contrast enabled ;;
  esac
  xcrun simctl terminate "$udid" bot.ouro.hx.gallery 2>/dev/null || true
  xcrun simctl launch "$udid" bot.ouro.hx.gallery -theme "$1" -page "$2" >/dev/null
  sleep 3
  xcrun simctl io "$udid" screenshot --type=png "$out/$1-$2-$3.png" >/dev/null 2>&1
  echo "$out/$1-$2-$3.png"
}
for theme in pearl abyss brass chart cookbook coral; do
  for mode in light dark increased; do shoot "$theme" colors "$mode"; done
done
for mode in light dark increased; do shoot pearl pairs "$mode"; shoot abyss pairs "$mode"; done
shoot pearl feel light
