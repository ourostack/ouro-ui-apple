#!/usr/bin/env python3
"""CI only: which gallery UI tests each shard runs, so three simulators share one build.

    python3 -I scripts/gallery-shards.py check          # every gallery test and audit page is in exactly one shard
    python3 -I scripts/gallery-shards.py args <shard>   # that shard's -only-testing arguments, one per line
    python3 -I scripts/gallery-shards.py pages <shard>  # its accessibility-audit pages (OURO_AUDIT_PAGES), or nothing
    python3 -I scripts/gallery-shards.py plan           # each shard's measured seconds, to rebalance by
    python3 -I scripts/gallery-shards.py env <file.xctestrun> <pages>   # set OURO_AUDIT_PAGES in the UI test target
    python3 -I scripts/gallery-shards.py audited <shard> <bundle.xcresult>  # the audit ran exactly that shard's pages

The audit test (testEveryComponentPagePassesTheAccessibilityAudit) is the longest at 406 s, so it is split by page
through its own OURO_AUDIT_PAGES filter. Every shard that lists audit pages runs it with only those pages, and
together they cover every page. `check` reads the test sources, so a new test or page that no shard runs fails the
`paths` job before any simulator starts. MotionTests is not here: it is the main-only hitch probe.

Seconds are from #54's run 42416382709 (attempt 2, macos-26, Xcode 26). Rebalance when a shard runs much longer than
the others: move tests so each shard's total is close to a third of the whole.
"""
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "Examples/OuroHXGallery/UITests"
TARGET = "OuroHXGalleryUITests"
AUDIT = "ComponentClaimTests/testEveryComponentPagePassesTheAccessibilityAudit"
SKIPPED_CLASSES = {"MotionTests"}

# Seconds each test (and each audit page, both sheet detents counted under "sheet") took.
SHARDS = {
    1: {
        "tests": {"ComponentClaimTests/testASheetWithTheKeyboardUpKeepsItsFieldAndActionInSight": 178.7,
                  "ComponentClaimTests/testAnEmptyStatesSymbolSitsAboveItsTitle": 13.5},
        "pages": {"sheet": 125.0},
    },
    2: {
        "tests": {"ComponentClaimTests/testASheetKeepsTheFocusedFieldInSightRatherThanItsEnd": 99.4,
                  "ComponentClaimTests/testAnEmptyStatesActionSpansTheWidthAtAccessibilitySizes": 22.1,
                  "FeelTests/testAToastStackArrivesWithoutJumpsGhostsOrALongSettle": 9.0},
        "pages": {"toasts": 109.0, "buttons": 72.0},
    },
    3: {
        "tests": {"ComponentClaimTests/testEveryControlIs44Points": 45.4,
                  "ComponentClaimTests/testCloseControlsClose": 42.3,
                  "ComponentClaimTests/testVoiceOverLabels": 41.8,
                  "ComponentClaimTests/testAToastWithAnActionWaits": 41.6,
                  "ComponentClaimTests/testAToastShowsAboveASheet": 32.4,
                  "ComponentClaimTests/testATallSheetOpensAtItsTopAtTheLargestSize": 24.3},
        "pages": {"empty": 50.0, "banners": 50.0},
    },
}


def source_tests():
    """Every `Class/testName` in the gallery UI test target, and the audit's pages."""
    tests, pages = set(), None
    for path in sorted(TESTS.glob("*.swift")):
        text = path.read_text()
        cls = None
        for line in text.splitlines():
            m = re.match(r"\s*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase", line)
            if m:
                cls = m.group(1)
            m = re.match(r"\s*func\s+(test\w+)\s*\(", line)
            if m and cls and cls not in SKIPPED_CLASSES:
                tests.add(f"{cls}/{m.group(1)}")
        m = re.search(r"static let pages\s*=\s*\[([^\]]*)\]", text)
        if m:
            pages = re.findall(r'"([^"]+)"', m.group(1))
    return tests, pages


def problems(shards, tests, pages):
    out = []
    assigned = [t for s in shards.values() for t in s["tests"]]
    paged = [p for s in shards.values() for p in s["pages"]]
    for name in sorted(set(assigned)):
        if assigned.count(name) > 1:
            out.append(f"{name} is in more than one shard")
    for name in sorted(tests - set(assigned) - {AUDIT}):
        out.append(f"{name} is in no shard: add it to the lightest one in scripts/gallery-shards.py")
    for name in sorted(set(assigned) - tests):
        out.append(f"{name} is in a shard but not in the tests")
    if AUDIT in assigned:
        out.append(f"{AUDIT} is split by page: list its pages, not the test")
    if pages is None:
        out.append("ComponentClaimTests' `static let pages` was not found")
    else:
        for page in sorted(set(paged)):
            if paged.count(page) > 1:
                out.append(f"audit page {page} is in more than one shard")
        for page in pages:
            if page not in paged:
                out.append(f"audit page {page} is in no shard: add it to the lightest one in scripts/gallery-shards.py")
        for page in sorted(set(paged) - set(pages)):
            out.append(f"audit page {page} is in a shard but not in ComponentClaimTests.pages")
    return out


def args(shard):
    spec = SHARDS[shard]
    lines = [f"-only-testing:{TARGET}/{t}" for t in spec["tests"]]
    if spec["pages"]:
        lines.append(f"-only-testing:{TARGET}/{AUDIT}")
    return lines


def set_env(xctestrun, pages):
    """Write OURO_AUDIT_PAGES into the UI test target's environment in an .xctestrun (format 1 or 2)."""
    with open(xctestrun, "rb") as f:
        plist = plistlib.load(f)
    targets = []
    for config in plist.get("TestConfigurations", []):
        targets += config.get("TestTargets", [])
    targets += [v for k, v in plist.items() if isinstance(v, dict) and k != "__xctestrun_metadata__" and "TestBundlePath" in v]
    ui = [t for t in targets if t.get("BlueprintName", "") == TARGET or str(t.get("TestBundlePath", "")).endswith(f"{TARGET}.xctest")]
    if not ui:
        raise SystemExit(f"::error::{xctestrun} has no {TARGET} target")
    for target in ui:
        # The UI test runner reads EnvironmentVariables; TestingEnvironmentVariables reaches the bundle in a hosted run.
        # `audited` checks after the run that the filter took effect.
        for key in ("EnvironmentVariables", "TestingEnvironmentVariables"):
            target.setdefault(key, {})["OURO_AUDIT_PAGES"] = pages
    with open(xctestrun, "wb") as f:
        plistlib.dump(plist, f)
    print(f"OURO_AUDIT_PAGES={pages} in {len(ui)} {TARGET} target(s) of {xctestrun}")


AUDIT_RUN = re.compile(r"^(\w+)( large)? (default|UICT\w+) (light|dark)$")


def pages_in(titles):
    """The pages an audit's activity titles name ("toasts default light", "sheet large UICT... dark")."""
    return [m.group(1) for m in map(AUDIT_RUN.match, titles) if m]


def audited(shard, bundle):
    want = set(SHARDS[shard]["pages"])
    if not want:
        return 0
    out = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "activities", "--path", bundle,
                          "--test-id", f"{AUDIT.split('/')[0]}/{AUDIT.split('/')[1]}()", "--compact"],
                         capture_output=True, text=True, timeout=120)
    if out.returncode != 0:
        print(f"::error title=Gallery shards::no audit activities in {bundle}: {out.stderr.strip()[:300]}")
        return 1
    titles = [a.get("title", "") for run in json.loads(out.stdout).get("testRuns", []) for a in run.get("activities", [])]
    ran = pages_in(titles)
    if set(ran) != want or len(ran) < 4 * len(want):
        print(f"::error title=Gallery shards::shard {shard} should audit {sorted(want)} at both sizes in light and dark; "
              f"it audited {sorted(set(ran))} in {len(ran)} runs")
        return 1
    print(f"Shard {shard} audited {sorted(want)} in {len(ran)} runs")
    return 0


def selftest():
    tests = {"A/test1", "A/test2", AUDIT}
    good = {1: {"tests": {"A/test1": 1}, "pages": {"p": 1}}, 2: {"tests": {"A/test2": 1}, "pages": {"q": 1}}}
    assert problems(good, tests, ["p", "q"]) == [], problems(good, tests, ["p", "q"])
    missing = {1: {"tests": {"A/test1": 1}, "pages": {"p": 1}}}
    found = problems(missing, tests, ["p", "q"])
    assert any("A/test2 is in no shard" in p for p in found) and any("page q is in no shard" in p for p in found), found
    twice = {1: {"tests": {"A/test1": 1, "A/test2": 1}, "pages": {"p": 1, "q": 1}}, 2: {"tests": {"A/test1": 1}, "pages": {"p": 1}}}
    found = problems(twice, tests, ["p", "q"])
    assert any("A/test1 is in more than one" in p for p in found) and any("page p is in more than one" in p for p in found), found
    whole = {1: {"tests": {"A/test1": 1, "A/test2": 1, AUDIT: 1}, "pages": {}}}
    assert any("split by page" in p for p in problems(whole, tests, ["p", "q"]))
    assert args(1)[-1].endswith(AUDIT) and all(a.startswith(f"-only-testing:{TARGET}/") for a in args(3))
    titles = ["Set Up", "sheet default light", "sheet large UICTContentSizeCategoryAccessibilityXXXL dark",
              "toasts default light expanded", "Find the \"Save\" Button", "buttons UICTContentSizeCategoryAccessibilityXXXL light"]
    assert pages_in(titles) == ["sheet", "sheet", "buttons"], pages_in(titles)


def main(argv):
    if argv[:1] == ["check"]:
        selftest()
        tests, pages = source_tests()
        found = problems(SHARDS, tests, pages)
        for line in found:
            print(f"::error title=Gallery shards::{line}")
        if not found:
            print(f"{len(tests)} gallery tests and {len(pages)} audit pages, each in exactly one of {len(SHARDS)} shards")
        return 1 if found else 0
    if len(argv) == 2 and argv[0] in ("args", "pages") and argv[1].isdigit() and int(argv[1]) in SHARDS:
        shard = int(argv[1])
        print("\n".join(args(shard)) if argv[0] == "args" else ",".join(SHARDS[shard]["pages"]))
        return 0
    if len(argv) == 3 and argv[0] == "env":
        set_env(argv[1], argv[2])
        return 0
    if len(argv) == 3 and argv[0] == "audited" and argv[1].isdigit() and int(argv[1]) in SHARDS:
        return audited(int(argv[1]), argv[2])
    if argv[:1] == ["plan"]:
        for shard, spec in SHARDS.items():
            print(f"shard {shard}: {sum(spec['tests'].values()) + sum(spec['pages'].values()):.0f} s")
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
