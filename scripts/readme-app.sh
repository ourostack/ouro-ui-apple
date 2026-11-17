#!/bin/bash
# The README as a newcomer meets it: a new app made from its Install lines and its "A first screen" code, depending on
# this checkout where the README names the release, built for the Mac and the iOS Simulator. Prints how long each step
# took. Needs Xcode (the README says why). Usage: scripts/readme-app.sh [work dir]
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=${1:-$(mktemp -d)}
app="$work/SettingsApp"
rm -rf "$app" "$work/ouro-ui-apple"
mkdir -p "$app/Sources/SettingsApp"
# The package's identity is its folder's name, which the README's .product line names.
ln -s "$root" "$work/ouro-ui-apple"

python3 -I - "$root/README.md" "$app" "$work/ouro-ui-apple" <<'PY'
import re, sys
readme, app, checkout = sys.argv[1:4]
text = open(readme, encoding="utf-8").read()

def section(heading):
    start = text.index(f"\n{heading}\n")
    end = re.compile(r"\n#{2,3} ").search(text, start + 1)
    return text[start:end.start() if end else len(text)]

def swift_blocks(body):
    return re.findall(r"```swift\n(.*?)```", body, re.S)

install = section("## Install")
package_line = re.search(r'^\s*(\.package\(url: "https://github\.com/ourostack/ouro-ui-apple\.git", from: "[^"]+"\),)', install, re.M)
product_line = re.search(r'^\s*(\.product\(name: "OuroHX", package: "ouro-ui-apple"\),)', install, re.M)
if not package_line or not product_line:
    sys.exit("README.md's Install has no .package(url:…ouro-ui-apple.git…) line or no .product(name: \"OuroHX\"…) line")
screens = swift_blocks(section("### A first screen"))
if len(screens) != 1 or "@main" not in screens[0]:
    sys.exit('README.md\'s "### A first screen" needs exactly one swift block, a whole app with @main')

open(f"{app}/Sources/SettingsApp/App.swift", "w", encoding="utf-8").write(screens[0])
open(f"{app}/Package.swift", "w", encoding="utf-8").write(f"""// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SettingsApp",
    platforms: [.macOS(.v15), .iOS(.v18)],
    dependencies: [
        // The README's line, pointed at this checkout: {package_line.group(1)}
        .package(path: "{checkout}"),
    ],
    targets: [
        .executableTarget(name: "SettingsApp", dependencies: [
            {product_line.group(1)}
        ]),
    ]
)
""")
PY

step() {
  local name=$1; shift
  local start=$SECONDS
  "$@"
  echo "readme-app: $name took $((SECONDS - start)) s"
}

cd "$app"
step "resolve" swift package resolve
step "build for the Mac" swift build
step "build for the iOS Simulator" xcodebuild build -scheme SettingsApp -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$work/xcode" CODE_SIGNING_ALLOWED=NO -quiet
echo "readme-app: the README's first screen builds as a new app, for the Mac and the iOS Simulator"
