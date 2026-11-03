#!/bin/sh
# Builds the DocC archives for every library product into $1 (default .build/docc), with DerivedData inside .build.
set -eu
out="${1:-.build/docc}"
mkdir -p "$out"
for scheme in OuroHX OuroHXTesting OuroAX OuroAXTesting; do
  xcodebuild docbuild -scheme "$scheme" -destination 'generic/platform=macOS' \
    -derivedDataPath .build/docc-dd 2>&1 | tail -3
done
find .build/docc-dd -name '*.doccarchive' -maxdepth 6 -type d -exec cp -R {} "$out/" \;
ls "$out"
