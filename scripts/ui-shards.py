#!/usr/bin/env python3
"""CI only: which UI tests each shard runs, so several simulators share one build. One plan per suite.

    python3 -I scripts/ui-shards.py check                                # every suite's plan matches its test sources
    python3 -I scripts/ui-shards.py <suite> args <shard>                 # that shard's xcodebuild test selection
    python3 -I scripts/ui-shards.py <suite> pages <shard>                # its audit pages (the suite's page filter), or nothing
    python3 -I scripts/ui-shards.py <suite> env <file.xctestrun> K=V...  # set environment for the suite's UI test target
    python3 -I scripts/ui-shards.py <suite> ran <shard> <bundle.xcresult>    # it ran its plan, and audited its pages
    python3 -I scripts/ui-shards.py <suite> plan                         # each shard's measured seconds, to rebalance by

Suites: `gallery` (Examples/OuroHXGallery) and `feel` (Examples/OuroFeelFixture).

The last shard of each suite is the catch-all: it runs the whole UI test target except the other shards' tests and the
suite's skipped classes, so a test no shard names still runs there. `check` fails the `paths` job when a test is
named twice, a named test no longer exists, or an audit page is in no shard or in two. `ran` reads a shard's result
bundle and fails when the shard ran other tests than its plan or audited other pages, so a shard can never pass by
running nothing.

The gallery's accessibility audit (406 s) is split by page through its OURO_AUDIT_PAGES filter: each shard with pages runs it
with only its own pages, and together they cover every page.

Seconds are from #54's run 42416382709 (attempt 2, macos-26, Xcode 26). Rebalance when a shard runs much longer than
the others: move tests so each shard's total is close to a third of the whole. A new test lands in the catch-all
shard until it is moved.
"""
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Seconds each test (and each audit page, both sheet detents counted under "sheet") took. A catch-all shard's "tests"
# are the ones it is known to run, for the plan's totals and for `ran`.
SUITES = {
    "gallery": {
        "tests_dir": "Examples/OuroHXGallery/UITests",
        "target": "OuroHXGalleryUITests",
        "skipped_classes": {"MotionTests"},  # the main-only hitch probe
        "audit": {"test": "ComponentClaimTests/testEveryComponentPagePassesTheAccessibilityAudit",
                  "pages_in": r"static let pages\s*=\s*\[([^\]]*)\]"},  # filtered by OURO_AUDIT_PAGES
        # Seconds from #61's run 42432765989. The keyboard-sheet test (272 s) is the floor, so shard 1 holds it and
        # little else, and runs no audit pages.
        "shards": {
            1: {"tests": {"ComponentClaimTests/testASheetWithTheKeyboardUpKeepsItsFieldAndActionInSight": 272.5,
                          "ComponentClaimTests/testAnEmptyStatesSymbolSitsAboveItsTitle": 24.8},
                "pages": {}},
            2: {"tests": {"ComponentClaimTests/testASheetKeepsTheFocusedFieldInSightRatherThanItsEnd": 90.6,
                          "ComponentClaimTests/testAnEmptyStatesActionSpansTheWidthAtAccessibilitySizes": 45.5},
                "pages": {"sheet": 119.3}},
            3: {"tests": {"ComponentClaimTests/testEveryControlIs44Points": 38.5},
                "pages": {"toasts": 94.6, "buttons": 78.8}},
            4: {"tests": {"ComponentClaimTests/testVoiceOverLabels": 36.6,
                          "ComponentClaimTests/testCloseControlsClose": 27.8,
                          "ComponentClaimTests/testAToastShowsAboveASheet": 20.3,
                          "ComponentClaimTests/testATallSheetOpensAtItsTopAtTheLargestSize": 17.5,
                          "ComponentClaimTests/testAToastWithAnActionWaits": 16.6,
                          "FeelTests/testAToastStackArrivesWithoutJumpsGhostsOrALongSettle": 11.0},
                "pages": {"empty": 39.2, "banners": 35.0}},
        },
    },
    "feel": {
        "tests_dir": "Examples/OuroFeelFixture/UITests",
        "target": "OuroFeelFixtureUITests",
        "skipped_classes": set(),
        "audit": None,
        # testTheWayBack alone is 430 s, the floor for any shard.
        "shards": {
            1: {"tests": {"FeelCatchesTests/testTheWayBack": 429.8,
                          "FeelCatchesTests/testDoubleDraw": 16.2,
                          "FeelCatchesTests/testHitchMetricReading": 8.3},
                "pages": {}},
            2: {"tests": {"FeelCatchesTests/testTapLanding": 256.3,
                          "FeelCatchesTests/testNearMissesOfWhatIsNotABrokenWayBack": 161.0,
                          "FeelCatchesTests/testPlaceStability": 44.0},
                "pages": {}},
            3: {"tests": {"FeelCatchesTests/testAPushUnderATabBar": 139.4,
                          "FeelCatchesTests/testWhatIsNotABrokenWayBack": 124.9,
                          "FeelCatchesTests/testAPushFilmedInTheApp": 68.3,
                          "FeelCatchesTests/testOverlayDismissal": 30.9,
                          "FeelCatchesTests/testLateOrLingeringChrome": 20.6,
                          "FeelCatchesTests/testInsideTheWindow": 18.5,
                          "FeelCatchesTests/testJumpAfterLanding": 18.0,
                          "FeelCatchesTests/testSettleTime": 16.1,
                          "FeelCatchesTests/testSnapWithNoTransition": 15.7},
                "pages": {}},
        },
    },
}

ATTRS = r"(?:@[\w.]+(?:\([^)]*\))?\s+)*"
CLASS = re.compile(rf"^\s*{ATTRS}(?:(?:final|public|open|internal|private|fileprivate)\s+)*class\s+(\w+)\b")
FUNC = re.compile(rf"^\s*{ATTRS}(?:(?:override|public|open|internal|final|nonisolated)\s+)*func\s+(test\w+)\s*\(")


def source_tests(root, skipped, pages_in=None):
    """Every `Class/testName` under `root` (any depth, attributes allowed), and the audit's pages when it has one."""
    tests, pages = set(), None
    for path in sorted(root.rglob("*.swift")):
        text = path.read_text()
        cls = None
        for line in text.splitlines():
            m = CLASS.match(line)
            if m:
                cls = m.group(1)
            m = FUNC.match(line)
            if m and cls and cls not in skipped:
                tests.add(f"{cls}/{m.group(1)}")
        m = re.search(pages_in, text) if pages_in else None
        if m:
            pages = re.findall(r'"([^"]+)"', m.group(1))
    return tests, pages


def problems(suite, tests, pages):
    shards, audit = suite["shards"], suite["audit"]
    out = []
    assigned = [t for s in shards.values() for t in s["tests"]]
    paged = [p for s in shards.values() for p in s["pages"]]
    for name in sorted(set(assigned)):
        if assigned.count(name) > 1:
            out.append(f"{name} is in more than one shard")
    for name in sorted(set(assigned) - tests):
        out.append(f"{name} is in a shard but not in the tests: remove or rename it in scripts/ui-shards.py")
    if audit is None:
        if paged:
            out.append("this suite has no audit to split, but a shard lists pages")
        return out
    if audit["test"] in assigned:
        out.append(f"{audit['test']} is split by page: list its pages, not the test")
    if pages is None:
        out.append(f"the audit's pages (`{audit['pages_in']}`) were not found")
        return out
    for page in sorted(set(paged)):
        if paged.count(page) > 1:
            out.append(f"audit page {page} is in more than one shard")
    for page in pages:
        if page not in paged:
            out.append(f"audit page {page} is in no shard: add it to the lightest one in scripts/ui-shards.py")
    for page in sorted(set(paged) - set(pages)):
        out.append(f"audit page {page} is in a shard but not in the audit's pages")
    return out


def others(suite, shard):
    return sorted(t for n, s in suite["shards"].items() if n != shard for t in s["tests"])


def args(suite, shard):
    target, spec = suite["target"], suite["shards"][shard]
    if shard == max(suite["shards"]):
        # The catch-all: the whole target, less the other shards' tests and the skipped classes.
        return ([f"-only-testing:{target}"] + [f"-skip-testing:{target}/{t}" for t in others(suite, shard)]
                + [f"-skip-testing:{target}/{c}" for c in sorted(suite["skipped_classes"])])
    lines = [f"-only-testing:{target}/{t}" for t in spec["tests"]]
    if spec["pages"]:
        lines.append(f"-only-testing:{target}/{suite['audit']['test']}")
    return lines


def set_env(suite, xctestrun, pairs):
    """Write KEY=VALUE pairs into the suite's UI test target's environment in an .xctestrun (format 1 or 2)."""
    target_name = suite["target"]
    env = dict(p.split("=", 1) for p in pairs)
    with open(xctestrun, "rb") as f:
        plist = plistlib.load(f)
    targets = []
    for config in plist.get("TestConfigurations", []):
        targets += config.get("TestTargets", [])
    targets += [v for k, v in plist.items() if isinstance(v, dict) and k != "__xctestrun_metadata__" and "TestBundlePath" in v]
    ui = [t for t in targets if t.get("BlueprintName", "") == target_name
          or str(t.get("TestBundlePath", "")).endswith(f"{target_name}.xctest")]
    if not ui:
        raise SystemExit(f"::error::{xctestrun} has no {target_name} target")
    for target in ui:
        # The UI test runner reads EnvironmentVariables; TestingEnvironmentVariables reaches the bundle in a hosted run.
        # `ran` checks after the run that a page filter took effect.
        for key in ("EnvironmentVariables", "TestingEnvironmentVariables"):
            target.setdefault(key, {}).update(env)
    with open(xctestrun, "wb") as f:
        plistlib.dump(plist, f)
    print(f"{' '.join(pairs)} in {len(ui)} {target_name} target(s) of {xctestrun}")


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


def ran_problems(suite, shard, ran, pages_ran):
    spec = suite["shards"][shard]
    want = set(spec["tests"]) | ({suite["audit"]["test"]} if spec["pages"] else set())
    out = []
    if not ran:
        out.append(f"shard {shard} ran no tests")
    if shard == max(suite["shards"]):
        if missing := sorted(want - set(ran)):
            out.append(f"shard {shard} did not run {missing}")
        if extra := sorted(set(ran) & set(others(suite, shard))):
            out.append(f"shard {shard} ran other shards' tests {extra}")
        if skipped := sorted(t for t in ran if t.split("/")[0] in suite["skipped_classes"]):
            out.append(f"shard {shard} ran skipped tests {skipped}")
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
        raise SystemExit(f"::error title=UI shards::xcresulttool {' '.join(what)} on {bundle}: {out.stderr.strip()[:300]}")
    return json.loads(out.stdout)


def check_ran(suite, shard, bundle):
    ran = tests_in(xcresult(bundle, "tests").get("testNodes", []))
    pages_ran = []
    if suite["shards"][shard]["pages"]:
        acts = xcresult(bundle, "activities", "--test-id", f"{suite['audit']['test']}()")
        pages_ran = pages_in([a.get("title", "") for run in acts.get("testRuns", []) for a in run.get("activities", [])])
    found = ran_problems(suite, shard, ran, pages_ran)
    for line in found:
        print(f"::error title=UI shards::{line}")
    if not found:
        print(f"Shard {shard} ran {len(ran)} tests" + (f" and audited {sorted(set(pages_ran))} in {len(pages_ran)} runs" if pages_ran else ""))
    return 1 if found else 0


def selftest():
    import tempfile
    audit = {"test": "A/testAudit", "pages_in": r"static let pages\s*=\s*\[([^\]]*)\]"}
    tests = {"A/test1", "A/test2", "A/testAudit"}
    good = {"target": "T", "skipped_classes": {"M"}, "audit": audit,
            "shards": {1: {"tests": {"A/test1": 1}, "pages": {"p": 1}}, 2: {"tests": {"A/test2": 1}, "pages": {"q": 1}}}}
    assert problems(good, tests, ["p", "q"]) == [], problems(good, tests, ["p", "q"])
    found = problems(dict(good, shards={1: {"tests": {"A/test1": 1}, "pages": {"p": 1}}, 2: {"tests": {}, "pages": {}}}), tests, ["p", "q"])
    assert any("page q is in no shard" in p for p in found), found
    found = problems(dict(good, shards={1: {"tests": {"A/test1": 1, "A/gone": 1}, "pages": {"p": 1, "q": 1}},
                                        2: {"tests": {"A/test1": 1}, "pages": {"p": 1}}}), tests, ["p", "q"])
    assert any("A/test1 is in more than one" in p for p in found) and any("page p is in more than one" in p for p in found)
    assert any("A/gone is in a shard but not in the tests" in p for p in found), found
    assert any("split by page" in p for p in problems(dict(good, shards={1: {"tests": {"A/testAudit": 1}, "pages": {}}}), tests, ["p", "q"]))
    plain = {"target": "F", "skipped_classes": set(), "audit": None,
             "shards": {1: {"tests": {"A/test1": 1}, "pages": {}}, 2: {"tests": {"A/test2": 1}, "pages": {}}}}
    assert problems(plain, {"A/test1", "A/test2"}, None) == []
    # The catch-all selects the whole target less the others and the skipped classes; the rest name theirs.
    assert args(good, 1) == ["-only-testing:T/A/test1", "-only-testing:T/A/testAudit"], args(good, 1)
    assert args(good, 2) == ["-only-testing:T", "-skip-testing:T/A/test1", "-skip-testing:T/M"], args(good, 2)
    assert args(plain, 1) == ["-only-testing:F/A/test1"] and args(plain, 2) == ["-only-testing:F", "-skip-testing:F/A/test1"]
    # `ran`: exact for a named shard, a superset for the catch-all, and never a pass on nothing.
    assert ran_problems(good, 1, ["A/test1", "A/testAudit"], ["p"] * 4) == []
    assert ran_problems(good, 1, ["A/test1"], [])
    assert ran_problems(good, 1, [], [])
    assert ran_problems(good, 2, ["A/test2", "A/testAudit", "B/new"], ["q"] * 4) == []
    assert ran_problems(good, 2, ["A/test2", "A/testAudit", "A/test1"], ["q"] * 4)
    assert ran_problems(good, 2, ["A/test2", "A/testAudit", "M/testX"], ["q"] * 4)
    assert ran_problems(good, 2, ["A/test2", "A/testAudit"], ["p", "q", "q", "q", "q"])
    assert ran_problems(plain, 1, ["A/test1"], []) == [] and ran_problems(plain, 2, [], [])
    titles = ["Set Up", "sheet default light", "sheet large UICTContentSizeCategoryAccessibilityXXXL dark",
              "toasts default light expanded", "Find the \"Save\" Button", "buttons UICTContentSizeCategoryAccessibilityXXXL light"]
    assert pages_in(titles) == ["sheet", "sheet", "buttons"], pages_in(titles)
    nodes = [{"nodeType": "Test Plan", "name": "P", "children": [{"nodeType": "Unit test bundle", "name": "T", "children": [
        {"nodeType": "Test Suite", "name": "A", "children": [{"nodeType": "Test Case", "name": "test1()"}]}]}]}]
    assert tests_in(nodes) == ["A/test1"], tests_in(nodes)
    # The source scan sees attributed classes and tests, in subfolders too.
    with tempfile.TemporaryDirectory() as d:
        sub = Path(d) / "sub"
        sub.mkdir()
        (sub / "X.swift").write_text('@MainActor\nfinal class X: XCTestCase {\n  @MainActor func testOne() {}\n'
                                     '  override func testTwo() async throws {}\n  func helper() {}\n}\n'
                                     '@MainActor final class Y: Base {\n  func testThree() {}\n  static let pages = ["a", "b"]\n}\n'
                                     'final class M: XCTestCase {\n  func testSkipped() {}\n}\n')
        found_tests, found_pages = source_tests(Path(d), {"M"}, audit["pages_in"])
        assert found_tests == {"X/testOne", "X/testTwo", "Y/testThree"}, found_tests
        assert found_pages == ["a", "b"], found_pages


def check_all():
    selftest()
    failed = False
    for name, suite in SUITES.items():
        audit = suite["audit"]
        tests, pages = source_tests(ROOT / suite["tests_dir"], suite["skipped_classes"], audit and audit["pages_in"])
        found = problems(suite, tests, pages)
        for line in found:
            print(f"::error title=UI shards ({name})::{line}")
        failed |= bool(found)
        if not found:
            named = {t for s in suite["shards"].values() for t in s["tests"]}
            catch_all = max(suite["shards"])
            print(f"{name}: {len(tests)} tests" + (f" and {len(pages)} audit pages" if audit else "") + f" in {len(suite['shards'])} shards")
            for test in sorted(tests - named - ({audit["test"]} if audit else set())):
                print(f"::notice title=UI shards ({name})::{test} runs in the catch-all shard {catch_all}; give it a "
                      "measured time and a shard in scripts/ui-shards.py")
    return 1 if failed else 0


def main(argv):
    if argv == ["check"]:
        return check_all()
    if len(argv) >= 2 and argv[0] in SUITES:
        suite, cmd, rest = SUITES[argv[0]], argv[1], argv[2:]
        shard = int(rest[0]) if rest and rest[0].isdigit() and int(rest[0]) in suite["shards"] else None
        if cmd == "args" and shard and len(rest) == 1:
            print("\n".join(args(suite, shard)))
            return 0
        if cmd == "pages" and shard and len(rest) == 1:
            print(",".join(suite["shards"][shard]["pages"]))
            return 0
        if cmd == "env" and len(rest) >= 2 and all("=" in p for p in rest[1:]):
            set_env(suite, rest[0], rest[1:])
            return 0
        if cmd == "ran" and shard and len(rest) == 2:
            return check_ran(suite, shard, rest[1])
        if cmd == "plan" and not rest:
            for n, spec in suite["shards"].items():
                print(f"shard {n}: {sum(spec['tests'].values()) + sum(spec['pages'].values()):.0f} s")
            return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
