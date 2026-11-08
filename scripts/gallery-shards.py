#!/usr/bin/env python3
"""CI only: which gallery UI tests each shard runs, so four simulators share one build.

    python3 -I scripts/gallery-shards.py check                       # the plan matches the test sources
    python3 -I scripts/gallery-shards.py args <shard>                # that shard's xcodebuild test selection
    python3 -I scripts/gallery-shards.py pages <shard>               # its accessibility-audit pages (OURO_AUDIT_PAGES)
    python3 -I scripts/gallery-shards.py env <file.xctestrun> <pages>    # set OURO_AUDIT_PAGES for the UI test target
    python3 -I scripts/gallery-shards.py ran <shard> <bundle.xcresult>   # it ran its tests and audited its pages
    python3 -I scripts/gallery-shards.py plan                        # each shard's measured seconds, to rebalance by

The audit test (testEveryComponentPagePassesTheAccessibilityAudit) is the longest at 406 s, so it is split by page
through its own OURO_AUDIT_PAGES filter: each shard with pages runs it with only those pages, and together they cover every
page. The last shard is the catch-all: it runs the whole UI test target except the other shards' tests and
MotionTests (the main-only hitch probe), so a test no shard names still runs there. `check` reads the test sources
and fails the `paths` job when a test is named twice, a named test no longer exists, or an audit page is in no shard
or in two. `ran` reads each shard's result bundle and fails when the shard ran other tests than its plan or audited
other pages, so a shard can never pass by running nothing.

Seconds are from #61's run 42432765989 (macos-26, Xcode 26), read from each shard's result bundle. The keyboard-sheet
test alone (272 s) is the floor, so shard 1 holds it and little else. Rebalance when a shard runs much longer than the
others: move tests so the other shards' totals stay close to each other. A new test lands in the catch-all
shard until it is moved.
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

# Seconds each test (and each audit page, both sheet detents counted under "sheet") took. The last shard is the
# catch-all; its "tests" are the ones it is known to run, for the plan's totals and for `ran`.
SHARDS = {
    1: {
        "tests": {"ComponentClaimTests/testASheetWithTheKeyboardUpKeepsItsFieldAndActionInSight": 272.5,
                  "ComponentClaimTests/testAnEmptyStatesSymbolSitsAboveItsTitle": 24.8},
        "pages": {},
    },
    2: {
        "tests": {"ComponentClaimTests/testASheetKeepsTheFocusedFieldInSightRatherThanItsEnd": 90.6,
                  "ComponentClaimTests/testAnEmptyStatesActionSpansTheWidthAtAccessibilitySizes": 45.5},
        "pages": {"sheet": 119.3},
    },
    3: {
        "tests": {"ComponentClaimTests/testEveryControlIs44Points": 38.5},
        "pages": {"toasts": 94.6, "buttons": 78.8},
    },
    4: {
        "tests": {"ComponentClaimTests/testVoiceOverLabels": 36.6,
                  "ComponentClaimTests/testCloseControlsClose": 27.8,
                  "ComponentClaimTests/testAToastShowsAboveASheet": 20.3,
                  "ComponentClaimTests/testATallSheetOpensAtItsTopAtTheLargestSize": 17.5,
                  "ComponentClaimTests/testAToastWithAnActionWaits": 16.6,
                  "FeelTests/testAToastStackArrivesWithoutJumpsGhostsOrALongSettle": 11.0},
        "pages": {"empty": 39.2, "banners": 35.0},
    },
}
CATCH_ALL = max(SHARDS)

ATTRS = r"(?:@[\w.]+(?:\([^)]*\))?\s+)*"
CLASS = re.compile(rf"^\s*{ATTRS}(?:(?:final|public|open|internal|private|fileprivate)\s+)*class\s+(\w+)\b")
FUNC = re.compile(rf"^\s*{ATTRS}(?:(?:override|public|open|internal|final|nonisolated)\s+)*func\s+(test\w+)\s*\(")


def source_tests(root=TESTS):
    """Every `Class/testName` in the gallery UI test target (any depth, attributes allowed), and the audit's pages."""
    tests, pages = set(), None
    for path in sorted(root.rglob("*.swift")):
        text = path.read_text()
        cls = None
        for line in text.splitlines():
            m = CLASS.match(line)
            if m:
                cls = m.group(1)
            m = FUNC.match(line)
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
    for name in sorted(set(assigned) - tests):
        out.append(f"{name} is in a shard but not in the tests: remove or rename it in scripts/gallery-shards.py")
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


def others(shards, shard):
    return sorted(t for n, s in shards.items() if n != shard for t in s["tests"])


def args(shard, shards=None):
    shards = shards or SHARDS
    spec = shards[shard]
    if shard == max(shards):
        # The catch-all: the whole target, less the other shards' tests and the hitch probe.
        return ([f"-only-testing:{TARGET}"] + [f"-skip-testing:{TARGET}/{t}" for t in others(shards, shard)]
                + [f"-skip-testing:{TARGET}/{c}" for c in sorted(SKIPPED_CLASSES)])
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
        # `ran` checks after the run that the filter took effect.
        for key in ("EnvironmentVariables", "TestingEnvironmentVariables"):
            target.setdefault(key, {})["OURO_AUDIT_PAGES"] = pages
    with open(xctestrun, "wb") as f:
        plistlib.dump(plist, f)
    print(f"OURO_AUDIT_PAGES={pages} in {len(ui)} {TARGET} target(s) of {xctestrun}")


AUDIT_RUN = re.compile(r"^(\w+)( large)? (default|UICT\w+) (light|dark)$")


def pages_in(titles):
    """The pages an audit's activity titles name ("toasts default light", "sheet large UICT... dark")."""
    return [m.group(1) for m in map(AUDIT_RUN.match, titles) if m]


def tests_in(nodes):
    """`Class/testName` of every test case in xcresulttool's `tests` tree."""
    out = []

    def walk(node, cls):
        kind = node.get("nodeType")
        if kind == "Test Case":
            out.append(f"{cls}/{node['name'].removesuffix('()')}")
            return
        for child in node.get("children", []):
            walk(child, node["name"] if kind == "Test Suite" else cls)

    for node in nodes:
        walk(node, None)
    return out


def ran_problems(shard, ran, pages_ran, shards=None):
    shards = shards or SHARDS
    spec = shards[shard]
    want = set(spec["tests"]) | ({AUDIT} if spec["pages"] else set())
    out = []
    if shard == max(shards):
        if missing := sorted(want - set(ran)):
            out.append(f"shard {shard} did not run {missing}")
        if extra := sorted(set(ran) & set(others(shards, shard))):
            out.append(f"shard {shard} ran other shards' tests {extra}")
        if probe := sorted(t for t in ran if t.split("/")[0] in SKIPPED_CLASSES):
            out.append(f"shard {shard} ran the hitch probe {probe}")
    elif set(ran) != want:
        out.append(f"shard {shard} should run {sorted(want)}; it ran {sorted(set(ran))}")
    if spec["pages"] and (set(pages_ran) != set(spec["pages"]) or len(pages_ran) < 4 * len(spec["pages"])):
        out.append(f"shard {shard} should audit {sorted(spec['pages'])} at both sizes in light and dark; "
                   f"it audited {sorted(set(pages_ran))} in {len(pages_ran)} runs")
    return out


def xcresult(bundle, *what):
    out = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", *what, "--path", bundle, "--compact"],
                         capture_output=True, text=True, timeout=120)
    if out.returncode != 0:
        raise SystemExit(f"::error title=Gallery shards::xcresulttool {' '.join(what)} on {bundle}: {out.stderr.strip()[:300]}")
    return json.loads(out.stdout)


def check_ran(shard, bundle):
    ran = tests_in(xcresult(bundle, "tests").get("testNodes", []))
    pages_ran = []
    if SHARDS[shard]["pages"]:
        acts = xcresult(bundle, "activities", "--test-id", f"{AUDIT}()")
        pages_ran = pages_in([a.get("title", "") for run in acts.get("testRuns", []) for a in run.get("activities", [])])
    found = ran_problems(shard, ran, pages_ran)
    for line in found:
        print(f"::error title=Gallery shards::{line}")
    if not found:
        print(f"Shard {shard} ran {len(ran)} tests and audited {sorted(set(pages_ran))} in {len(pages_ran)} runs")
    return 1 if found else 0


def selftest():
    import tempfile
    tests = {"A/test1", "A/test2", AUDIT}
    good = {1: {"tests": {"A/test1": 1}, "pages": {"p": 1}}, 2: {"tests": {"A/test2": 1}, "pages": {"q": 1}}}
    assert problems(good, tests, ["p", "q"]) == [], problems(good, tests, ["p", "q"])
    found = problems({1: {"tests": {"A/test1": 1}, "pages": {"p": 1}}, 2: {"tests": {}, "pages": {}}}, tests, ["p", "q"])
    assert any("page q is in no shard" in p for p in found), found
    found = problems({1: {"tests": {"A/test1": 1, "A/gone": 1}, "pages": {"p": 1, "q": 1}},
                      2: {"tests": {"A/test1": 1}, "pages": {"p": 1}}}, tests, ["p", "q"])
    assert any("A/test1 is in more than one" in p for p in found) and any("page p is in more than one" in p for p in found)
    assert any("A/gone is in a shard but not in the tests" in p for p in found), found
    assert any("split by page" in p for p in problems({1: {"tests": {AUDIT: 1}, "pages": {}}}, tests, ["p", "q"]))
    # The catch-all selects the whole target less the others and the probe; the rest name theirs.
    assert args(1, good) == [f"-only-testing:{TARGET}/A/test1", f"-only-testing:{TARGET}/{AUDIT}"], args(1, good)
    assert args(2, good) == [f"-only-testing:{TARGET}", f"-skip-testing:{TARGET}/A/test1", f"-skip-testing:{TARGET}/MotionTests"]
    # `ran`: exact for a named shard, a superset for the catch-all, and never a pass on nothing.
    assert ran_problems(1, ["A/test1", AUDIT], ["p"] * 4, good) == []
    assert ran_problems(1, ["A/test1"], [], good)
    assert ran_problems(1, [], [], good)
    assert ran_problems(2, ["A/test2", AUDIT, "B/new"], ["q"] * 4, good) == []
    assert ran_problems(2, ["A/test2", AUDIT, "A/test1"], ["q"] * 4, good)
    assert ran_problems(2, ["A/test2", AUDIT, "MotionTests/testX"], ["q"] * 4, good)
    assert ran_problems(2, ["A/test2", AUDIT], ["p", "q", "q", "q", "q"], good)
    titles = ["Set Up", "sheet default light", "sheet large UICTContentSizeCategoryAccessibilityXXXL dark",
              "toasts default light expanded", "Find the \"Save\" Button", "buttons UICTContentSizeCategoryAccessibilityXXXL light"]
    assert pages_in(titles) == ["sheet", "sheet", "buttons"], pages_in(titles)
    nodes = [{"nodeType": "Test Plan", "name": "P", "children": [{"nodeType": "Unit test bundle", "name": TARGET, "children": [
        {"nodeType": "Test Suite", "name": "A", "children": [{"nodeType": "Test Case", "name": "test1()"}]}]}]}]
    assert tests_in(nodes) == ["A/test1"], tests_in(nodes)
    # The source scan sees attributed classes and tests, in subfolders too.
    with tempfile.TemporaryDirectory() as d:
        sub = Path(d) / "sub"
        sub.mkdir()
        (sub / "X.swift").write_text('@MainActor\nfinal class X: XCTestCase {\n  @MainActor func testOne() {}\n'
                                     '  override func testTwo() async throws {}\n  func helper() {}\n}\n'
                                     '@MainActor final class Y: Base {\n  func testThree() {}\n  static let pages = ["a", "b"]\n}\n')
        found_tests, found_pages = source_tests(Path(d))
        assert found_tests == {"X/testOne", "X/testTwo", "Y/testThree"}, found_tests
        assert found_pages == ["a", "b"], found_pages


def main(argv):
    if argv[:1] == ["check"]:
        selftest()
        tests, pages = source_tests()
        found = problems(SHARDS, tests, pages)
        for line in found:
            print(f"::error title=Gallery shards::{line}")
        if not found:
            named = {t for s in SHARDS.values() for t in s["tests"]}
            unnamed = sorted(tests - named - {AUDIT})
            print(f"{len(tests)} gallery tests and {len(pages)} audit pages in {len(SHARDS)} shards")
            for name in unnamed:
                print(f"::notice title=Gallery shards::{name} runs in the catch-all shard {CATCH_ALL}; give it a measured "
                      "time and a shard in scripts/gallery-shards.py")
        return 1 if found else 0
    if len(argv) == 2 and argv[0] in ("args", "pages") and argv[1].isdigit() and int(argv[1]) in SHARDS:
        shard = int(argv[1])
        print("\n".join(args(shard)) if argv[0] == "args" else ",".join(SHARDS[shard]["pages"]))
        return 0
    if len(argv) == 3 and argv[0] == "env":
        set_env(argv[1], argv[2])
        return 0
    if len(argv) == 3 and argv[0] == "ran" and argv[1].isdigit() and int(argv[1]) in SHARDS:
        return check_ran(int(argv[1]), argv[2])
    if argv[:1] == ["plan"]:
        for shard, spec in SHARDS.items():
            print(f"shard {shard}: {sum(spec['tests'].values()) + sum(spec['pages'].values()):.0f} s")
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
