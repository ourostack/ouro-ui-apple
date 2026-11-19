#!/bin/sh
# Checks scripts/release-gate.sh against a fake `gh`, offline: sh scripts/test-release-gate.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
mkdir -p "$work/bin"
# The fake prints what the real call's --jq would for FAKE_RUNS: "<status> <conclusion|-> <url>", "none", or a failure.
cat > "$work/bin/gh" <<'GH'
#!/bin/sh
[ "$FAKE_RUNS" = "fail" ] && exit 1
echo "$FAKE_RUNS"
GH
chmod +x "$work/bin/gh"
failures=0
check() {
  want="$1"; runs="$2"
  FAKE_RUNS="$runs" PATH="$work/bin:$PATH" sh "$here/release-gate.sh" o/r abc >/dev/null; got=$?
  [ "$got" = "$want" ] || { echo "FAIL: '$runs' exited $got, wanted $want"; failures=$((failures + 1)); }
}
check 0 "completed success https://x/1"
check 1 "completed failure https://x/1"
check 1 "completed cancelled https://x/1"
check 2 "in_progress - https://x/1"
check 2 "queued - https://x/1"
check 2 "none"
check 2 "fail"
rm -rf "$work"
[ "$failures" = 0 ] && echo "release-gate: ok"
exit "$failures"
