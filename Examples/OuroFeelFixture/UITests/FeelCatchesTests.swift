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

    func testInsideTheWindow() {
        both("window") { _, feel in (feel.insideWindow(), nil) }
    }

    func testTapLanding() {
        both("taps") { app, feel in (feel.tapLanding(on: app.switches["taps.toggle"], trials: 3), nil) }
    }

    func testTheWayBack() {
        // Following every button: the page's segmented picker and menu must not be taken for screens.
        both("nav") { _, feel in (feel.wayBack(follow: FeelFollow(types: [.button]), depth: 1), nil) }
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
