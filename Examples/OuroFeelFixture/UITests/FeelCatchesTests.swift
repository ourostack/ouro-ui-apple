import OuroFeel
import OuroFeelCore
import XCTest

/// Every Ouro Feel check, against the fixture's known bugs: each must fail with `-bug 1` and pass without it. The
/// failing runs are recorded, not asserted as failures of this test, so CI shows both reports.
@MainActor
final class FeelCatchesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
    }

    private func launch(_ page: String, bug: Bool, _ extra: [String] = []) -> (XCUIApplication, OuroFeel) {
        let app = XCUIApplication()
        app.launchArguments = ["-page", page, "-bug", bug ? "1" : "0"] + extra
        app.launch()
        return (app, OuroFeel(app))
    }

    /// Runs `check` with and without the bug: it must fail with it and pass without it.
    private func both(_ page: String, _ extra: [String] = [], file: StaticString = #filePath, line: UInt = #line,
                      _ check: (XCUIApplication, OuroFeel) -> (FeelResult, FeelFilm?)) {
        for bug in [true, false] {
            let (app, feel) = launch(page, bug: bug, extra)
            let (raw, film) = check(app, feel)
            let result = feel.record(raw, name: "\(page)-\(bug ? "bug" : "fixed")", film: film)
            XCTAssertEqual(result.passed, !bug, "\(page) with bug=\(bug):\n\(result.text)", file: file, line: line)
            app.terminate()
        }
    }

    private func isBugBuild(_ app: XCUIApplication) -> Bool {
        guard let i = app.launchArguments.firstIndex(of: "-bug"), i + 1 < app.launchArguments.count else { return false }
        return app.launchArguments[i + 1] == "1"
    }

    func testInsideTheWindow() {
        both("window") { _, feel in (feel.insideWindow(), nil) }
    }

    func testTapLanding() {
        both("taps") { app, feel in
            // The OS rate is context only: the bar is absolute, and on the iOS 27.2 simulator UIKit's switch drops it.
            let os = feel.osBaseline(trials: 5, rapid: true)
            let result = feel.tapLanding(on: app.switches["taps.toggle"], trials: 3, rapid: 5, rapidBaseline: os)
            if isBugBuild(app) {
                // The lock is named either way: as lost rapid taps, or (on a loaded machine that bunches paced taps
                // into the lock) as a centre single tap that missed, which leaves the pairs unscored.
                XCTAssertTrue(result.detections.contains { $0.what.contains("rapid taps") || $0.what.hasPrefix("centre:") },
                              "taps lost while animating are named:\n\(result.text)")
            }
            return (result, nil)
        }
    }

    /// Following every button. The segmented picker and the menus are not screens; the walk checks that the menus it
    /// opens close. The Filter menu never closes in the bug build; the Tags menu always closes, so it must pass in
    /// both builds. (Whether a tap opens the system Sort menu varies by iOS version, so the counts allow it either way.)
    func testTheWayBack() {
        both("nav") { app, feel in
            let result = feel.wayBack(follow: FeelFollow(types: [.button]), depth: 1)
            let bug = isBugBuild(app)
            if bug {
                XCTAssertTrue(result.detections.contains { $0.what.contains("nav.filter") }, "the stuck Filter menu is named:\n\(result.text)")
                XCTAssertFalse(result.detections.contains { $0.what.contains("nav.tags") }, "the Tags menu closes:\n\(result.text)")
                XCTAssertFalse(result.detections.contains { $0.what.contains("nav.more") }, "expanding in place is no overlay:\n\(result.text)")
                XCTAssertTrue(result.detections.contains { $0.what.contains("nav.settings") && $0.what.contains("settled back") },
                              "the sheet that refuses a pull down moved and settled back, so it has no gesture back:\n\(result.text)")
                XCTAssertTrue(result.findings.contains { $0.unchecked && $0.what.contains("nav.chef") && $0.what.contains("moved nothing") },
                              "a swipe that moved nothing, even slower, could not be checked:\n\(result.text)")
                XCTAssertFalse(result.detections.contains { $0.what.contains("nav.chef") && $0.what.contains("gesture") },
                               "a swipe that moved nothing is no bug found:\n\(result.text)")
            } else {
                XCTAssertGreaterThanOrEqual(result.measures["overlays"] ?? 0, 2, "both custom menus were checked as overlays:\n\(result.text)")
                XCTAssertTrue(result.passed, "a well-behaved app passes:\n\(result.text)")
                XCTAssertEqual(result.measures["relaunches"], 0, "a well-behaved app needs no recovery:\n\(result.text)")
            }
            return (result, nil)
        }
    }

    /// A push under a tab bar, from a screen whose only other control the pushed page shares, is a new screen: it is
    /// asked for its way back (the bug build hides it) and is no overlay, in both builds.
    func testAPushUnderATabBar() {
        both("push") { app, feel in
            let chefs = FeelEntry("Chefs") { app in
                let link = app.buttons["push.chefs"].firstMatch
                if link.waitForExistence(timeout: 10) { link.tap() }
            }
            let result = feel.wayBack(from: [chefs], follow: FeelFollow(types: [.button]), depth: 1)
            XCTAssertEqual(result.measures["overlays"] ?? 0, 0, "a push is no overlay:\n\(result.text)")
            XCTAssertGreaterThanOrEqual(result.measures["screens"] ?? 0, 1, "the pushed profile is a screen:\n\(result.text)")
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("push.chef") }, "the profile with no way back is named:\n\(result.text)")
            }
            return (result, nil)
        }
    }

    func testOverlayDismissal() {
        both("overlay") { _, feel in (feel.overlays([.button("overlay.open", overlay: "overlay.sidebar", pick: "overlay.saved")]), nil) }
    }

    func testPlaceStability() {
        both("place", ["-resetPlace", "1"]) { app, feel in
            for _ in 0..<3 { app.buttons["place.next"].tap() }
            // Relaunches keep the place: drop the reset.
            if let i = app.launchArguments.firstIndex(of: "-resetPlace") { app.launchArguments.removeSubrange(i...(i + 1)) }
            return (feel.place(read: { app.staticTexts["place.text"].label }), nil)
        }
    }

    /// The motion genres from one film each: the film taps Play, and the card's travel starts two seconds later, after
    /// XCUITest's idle wait for the tap (a start timed from launch was missed when launching took longer under load).
    private func motion(_ judge: (FeelFilm) -> FeelResult) {
        both("motion") { app, feel in
            let play = app.buttons["motion.play"]
            _ = play.waitForExistence(timeout: 10)
            let film = feel.film(["motion.card", "motion.ghost", "Pancakes", "bar.full", "bar.compact"], for: 7) { play.tap() }
            return (judge(film), film)
        }
    }

    func testSnapWithNoTransition() { motion { $0.snaps(of: "motion.card") } }
    func testJumpAfterLanding() { motion { $0.jumps(of: "motion.card") } }
    func testDoubleDraw() { motion { $0.doubleDraws(of: ["Pancakes"]) } }
    func testLateOrLingeringChrome() { motion { $0.chrome(from: "bar.full", to: "bar.compact") } }
    /// The fixed card eases for 0.8 s; snapshots and the runner's clock add up to a few tenths, so the limit is 1.25 s.
    /// The bug's late nudge, 2 s after it landed, is well past it.
    func testSettleTime() { motion { $0.settles("motion.card", within: 1.25) } }

    /// Not a pass or fail: one `XCTHitchMetric` reading of the fixed motion page, so the result bundle shows what the
    /// simulator reports (a proxy; gate hitches on a device).
    func testHitchMetricReading() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("XCTHitchMetric needs iOS 26") }
        let (app, feel) = launch("motion", bug: false, ["-autoplay", "0.1"])
        feel.measureHitches(in: self, iterations: 1) {
            app.buttons["motion.play"].tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
    }
}
