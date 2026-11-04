#!/bin/sh
# CI only: selects the newest /Applications/Xcode_*.app whose version is at least $1 (such as 27.2), or with
# `--exact 27.0` the one whose major.minor is exactly that, and fails when there is none. Bundle names differ between image builds, so the choice reads each bundle's version, never its name.
# Never run this on a shared Mac: it switches xcode-select for every process. Locally, use DEVELOPER_DIR per command.
set -eu
exact=0
if [ "${1:-}" = "--exact" ]; then exact=1; shift; fi
minimum="$1"
if [ -z "${CI:-}" ]; then
  echo "select-xcode: not on CI; this switches xcode-select globally. Fix: DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer <command>." >&2
  exit 2
fi
pick=""; best=""
for app in /Applications/Xcode_*.app; do
  [ -d "$app" ] || continue
  version="$(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
  build="$(defaults read "$app/Contents/version" ProductBuildVersion 2>/dev/null || true)"
  ok="$(awk -v v="$version" -v m="$minimum" -v e="$exact" 'BEGIN { split(v, a, "."); split(m, b, ".");
    if (e) print (a[1]+0 == b[1]+0 && a[2]+0 == b[2]+0); else print ((a[1]+0 > b[1]+0) || (a[1]+0 == b[1]+0 && a[2]+0 >= b[2]+0)) }')"
  [ "$ok" = 1 ] || continue
  key="$(printf '%s %s' "$version" "$build")"
  if [ -z "$pick" ] || [ "$(printf '%s\n%s\n' "$best" "$key" | sort -V | tail -1)" = "$key" ]; then pick="$app"; best="$key"; fi
done
if [ -z "$pick" ]; then
  if [ "$exact" = 1 ]; then echo "select-xcode: no Xcode $minimum on this runner:" >&2; else echo "select-xcode: no Xcode $minimum or later on this runner:" >&2; fi
  ls -d /Applications/Xcode_*.app >&2 || true
  exit 1
fi
echo "Using $pick ($best)"
sudo xcode-select -s "$pick"
xcodebuild -version
