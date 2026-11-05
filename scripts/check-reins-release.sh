#!/bin/sh
# Proves Ouro Reins' debug socket is compiled out of release builds: builds OuroReins in debug and in release, and checks
# that the debug objects hold ReinsSocketServer and the release objects don't, while both hold ReinsSession (so an
# empty or misread object can't pass). Works with both SwiftPM build layouts (.build/<config>/OuroReins.build/*.o and
# .build/<config>/OuroReins.o).
set -eu
cd "$(dirname "$0")/.."

symbols() {
  config="$1"
  swift build -c "$config" --target OuroReins >/dev/null
  objects="$(find -L ".build/$config" -maxdepth 2 \( -path "*/OuroReins.build/*.o" -o -name "OuroReins.o" \) 2>/dev/null)"
  if [ -z "$objects" ]; then
    echo "check-reins-release: no OuroReins objects under .build/$config" >&2
    exit 1
  fi
  # shellcheck disable=SC2086
  nm $objects 2>/dev/null
}

debug="$(symbols debug)"
release="$(symbols release)"
count() { printf '%s\n' "$1" | grep -c "$2" || true; }

echo "debug:   ReinsSession $(count "$debug" ReinsSession), ReinsSocketServer $(count "$debug" ReinsSocketServer)"
echo "release: ReinsSession $(count "$release" ReinsSession), ReinsSocketServer $(count "$release" ReinsSocketServer)"
[ "$(count "$debug" ReinsSession)" -gt 0 ] && [ "$(count "$release" ReinsSession)" -gt 0 ] || { echo "check-reins-release: ReinsSession missing; the objects weren't read" >&2; exit 1; }
[ "$(count "$debug" ReinsSocketServer)" -gt 0 ] || { echo "check-reins-release: the debug build has no socket server" >&2; exit 1; }
[ "$(count "$release" ReinsSocketServer)" -eq 0 ] || { echo "check-reins-release: the release build still holds ReinsSocketServer" >&2; exit 3; }
echo "check-reins-release: the debug socket is compiled out of release"
