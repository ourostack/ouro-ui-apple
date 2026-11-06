#!/bin/sh
# Builds the DocC archives for every library product into $1 (default .build/docc), with DerivedData inside .build.
set -eu
out="${1:-.build/docc}"
mkdir -p "$out"
for scheme in OuroHX OuroHXTesting OuroAX OuroAXTesting OuroFeel OuroFeelCore OuroReins; do
  log=".build/docc-$scheme.log"
  if ! xcodebuild docbuild -scheme "$scheme" -destination 'generic/platform=macOS' -derivedDataPath .build/docc-dd > "$log" 2>&1; then
    tail -40 "$log"
    echo "docc: $scheme failed; the full log is $log"
    exit 1
  fi
  grep -E "warning: .*(docc|\.md)" "$log" || true
done
find .build/docc-dd -name '*.doccarchive' -maxdepth 6 -type d -exec cp -R {} "$out/" \;
ls "$out"
