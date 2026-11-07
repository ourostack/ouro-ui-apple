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
        app.launchEnvironment.merge(OuroFeel.recorderEnvironment) { _, new in new }
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

    /// A push filmed in the app, frame by frame: the fixed build's page slides in and settles; the bug build's page
    /// appears in one frame, a snap. XCUITest's idle wait cannot hide the push, since the app records it.
    func testAPushFilmedInTheApp() {
        for bug in [false, true] {
            let (app, feel) = launch("transition", bug: bug)
            let open = app.buttons["transition.open"]
            XCTAssertTrue(open.waitForExistence(timeout: 30))
            let film = feel.recordedFilm(["transition.title"]) { open.tap() }
            XCTAssertNil(film.stalledAt, "the app recorded the push")
            let xs = Set(film.track("transition.title").map { Int($0.frame.minX.rounded()) })
            // The default gap: a move hidden in under 0.15 s reads as a snap whatever drew it. The bug build's push can
            // take the app 0.1 s to lay out, so the page arrives across one long frame.
            let snap = film.snaps(of: "transition.title", appearing: true)
            let settle = film.settles("transition.title", within: 0.8, maxGap: 0.05)
            if bug {
                feel.record(snap, name: "snap-bug", film: film)
                // On a slow machine the page can arrive across a frame longer than the snap check's gap, which it then
                // cannot judge; it still never passes, and the title's single place shows the page did not travel.
                let busy = snap.findings.contains { $0.unchecked && $0.what.contains("was busy") }
                XCTAssertTrue(!snap.detections.isEmpty || busy, snap.text)
                XCTAssertFalse(snap.passed, snap.text)
                XCTAssertLessThanOrEqual(xs.count, 2, "the bug build's page did not travel: \(xs.sorted())")
            } else {
                feel.expect(snap)
                feel.expect(settle)
                XCTAssertGreaterThanOrEqual(xs.count, 8, "the push was filmed frame by frame: \(xs.sorted())")
            }
            let longest = zip(film.frames, film.frames.dropFirst()).map { $1.t - $0.t }.max() ?? 0
            print("[ouro-feel] recorded push (bug \(bug)): \(film.frames.count) frames, \(xs.count) places of the title, cadence \(film.cadence), longest frame \(longest)")
            app.terminate()
        }
    }

    func testInsideTheWindow() {
        both("window") { _, feel in (feel.insideWindow(), nil) }
    }

    func testTapLanding() {
        both("taps") { app, feel in
            // The OS rate is context only: the bar is absolute, and on the iOS 27.2 simulator UIKit's switch drops it.
            let os = feel.osBaseline(trials: 5, rapid: true)
            let result = feel.tapLanding(on: app.descendants(matching: .any)["taps.toggle"].firstMatch, trials: 3, rapid: 5, rapidBaseline: os)
            if isBugBuild(app) {
                // The lock reads touch timestamps, so a double tap always meets it and paced taps never do.
                XCTAssertTrue(result.detections.contains { $0.what.contains("rapid taps") }, "taps lost while animating are named:\n\(result.text)")
                XCTAssertTrue(result.detections.contains { $0.what.hasPrefix("trailing edge:") }, "the dead strip is named:\n\(result.text)")
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

    /// Shapes once misread as missing ways back, none a bug (``KitchenPage`` in the app): a tab switch, a zoom push whose
    /// edge swipe starts lower, a popover of a stepper, and a menu with a submenu. The walk passes them all.
    func testWhatIsNotABrokenWayBack() {
        let (app, feel) = launch("kitchen", bug: false)
        XCTAssertTrue(app.buttons["kitchen.seeAll"].waitForExistence(timeout: 30))
        let result = feel.record(feel.wayBack(follow: FeelFollow(types: [.button, .cell]), depth: 1), name: "kitchen")
        XCTAssertTrue(result.passed, "none of these is a broken way back:\n\(result.text)")
        XCTAssertTrue(result.findings.contains { $0.what.contains("kitchen.seeAll") && $0.what.contains("switched to") },
                      "See all is a tab switch:\n\(result.text)")
        XCTAssertTrue(result.findings.contains { $0.what.contains("kitchen.serves") && $0.what.contains("stepper") },
                      "the stepper's popover is asked only for a tap outside:\n\(result.text)")
        XCTAssertGreaterThanOrEqual(result.measures["good"] ?? 0, 1, "the zoomed recipe has a way back and a gesture back:\n\(result.text)")
        XCTAssertGreaterThanOrEqual(result.measures["overlays"] ?? 0, 2, "the popover and the menu were both checked:\n\(result.text)")
        XCTAssertFalse(result.findings.contains { $0.what.contains("kitchen.openInRecipes") && $0.what.contains("switched to") },
                       "Open in Recipes pushes a page, so it is checked as one, not noted as a tab switch:\n\(result.text)")
        app.terminate()
    }

    /// Near misses of those shapes (``KitchenPage`` with `-bug 1`), each a real broken way back the walk must still
    /// catch: a tab switch that pushes a page with its back button hidden, a popover whose Apply does not close it
    /// (it also holds a slider), and a menu that stays open after a pick while an Undo toast shows elsewhere.
    func testNearMissesOfWhatIsNotABrokenWayBack() {
        let (app, feel) = launch("kitchen", bug: true)
        XCTAssertTrue(app.buttons["kitchen.seeAll"].waitForExistence(timeout: 30))
        let result = feel.record(feel.wayBack(follow: FeelFollow(types: [.button, .cell]), depth: 1), name: "kitchen-bug")
        XCTAssertFalse(result.passed, "each near miss is a broken way back:\n\(result.text)")
        for key in ["kitchen.openInRecipes", "kitchen.heat", "kitchen.tidy"] {
            XCTAssertTrue(result.detections.contains { $0.what.contains(key) }, "\(key) is named:\n\(result.text)")
        }
        for key in ["kitchen.seeAll", "kitchen.serves", "kitchen.recipe", "kitchen.more"] {
            XCTAssertFalse(result.detections.contains { $0.what.contains(key) }, "\(key) is still no bug:\n\(result.text)")
        }
        app.terminate()
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

    /// The motion genres from one film each, on the fixture's own clock (``FixtureClock`` in the app): the film taps
    /// Play, then advances the app a tick (0.1 s) at a time and samples each tick, so a busy runner films the same 36
    /// frames as a quiet one, only more slowly. The motion starts half a second after Play.
    private func motion(_ judge: (FeelFilm) -> FeelResult) {
        both("motion") { app, feel in
            let play = app.buttons["motion.play"]
            _ = play.waitForExistence(timeout: 10)
            let film = feel.film(["motion.card", "motion.ghost", "Pancakes", "bar.full", "bar.compact"], steps: 35, tick: 0.1,
                                 clock: "motion.clock", advance: FeelClock.darwinNotification("bot.ouro.feel.fixture.tick")) { play.tap() }
            return (judge(film), film)
        }
    }

    func testSnapWithNoTransition() { motion { $0.snaps(of: "motion.card") } }
    func testJumpAfterLanding() { motion { $0.jumps(of: "motion.card") } }
    func testDoubleDraw() { motion { $0.doubleDraws(of: ["Pancakes"]) } }
    func testLateOrLingeringChrome() { motion { $0.chrome(from: "bar.full", to: "bar.compact") } }
    /// The fixed card eases for 0.8 s of the app's clock; the bug's late nudge, 2 s after it landed, is well past 1.25 s.
    func testSettleTime() { motion { $0.settles("motion.card", within: 1.25) } }

    /// Flicker on the app's own clock: the bug's words turn, turn back and turn again, and its badge blinks on for one
    /// tick; the fixed page turns once and its badge appears once.
    func testFlicker() {
        both("flicker") { app, feel in
            let play = app.buttons["flicker.play"]
            _ = play.waitForExistence(timeout: 10)
            let film = feel.film(["flicker.words", "flicker.badge"], steps: 12, tick: 0.1, clock: "flicker.clock",
                                 advance: FeelClock.darwinNotification("bot.ouro.feel.fixture.tick")) { play.tap() }
            let result = film.flickers(of: ["flicker.words", "flicker.badge"])
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("flicker.words") && $0.what.contains("taken back") }, result.text)
                XCTAssertTrue(result.detections.contains { $0.what.contains("flicker.badge") && $0.what.contains("blinked on") }, result.text)
            }
            return (result, film)
        }
    }

    /// Place kept through stray input: a tap in the middle, an edge swipe, the Contents sheet swiped away and a trip
    /// to the Home Screen, after reading on to page 3. The bug build's middle tap turns the page and its sheet resets it.
    func testPlaceKeptThroughStrayInput() {
        both("stray") { app, feel in
            let next = app.buttons["stray.next"]
            _ = next.waitForExistence(timeout: 10)
            next.tap(); next.tap()
            let contents = FeelPlaceStep.sheetDismissed("Contents", sheet: "stray.sheet") { $0.buttons["stray.contents"].tap() }
            let result = feel.placeHeld(across: [.strayTap(), .edgeSwipe, contents, .background],
                                        read: { app.staticTexts["stray.page"].label })
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.hasPrefix("stray tap") }, result.text)
                XCTAssertTrue(result.detections.contains { $0.what.hasPrefix("Contents opened and swiped away") }, result.text)
                XCTAssertFalse(result.detections.contains { $0.what.hasPrefix("edge swipe") }, result.text)
            }
            return (result, nil)
        }
    }

    /// One tick of the fixture's clock, then a wait for the app to show it, so each read is one tick later however slow
    /// the runner.
    private func tick(_ app: XCUIApplication) -> () -> Void {
        let clock = app.staticTexts["fight.clock"]
        let advance = FeelClock.darwinNotification("bot.ouro.feel.fixture.tick")
        return {
            let before = clock.label
            advance()
            let deadline = Date().addingTimeInterval(30)
            while clock.label == before && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        }
    }

    /// The fight page's place: empty while the veil is up.
    private func fightPlace(_ app: XCUIApplication) -> () -> String {
        { app.staticTexts["fight.veil"].exists ? "" : app.staticTexts["fight.page"].label }
    }

    /// Navigation that fights you, read once a tick on the app's own clock: the bug build's sync lands three ticks after
    /// Next and pulls the page back; the fixed build's sync agrees.
    func testNavigationThatFightsYou() {
        both("fight") { app, feel in
            _ = app.buttons["fight.next"].waitForExistence(timeout: 10)
            let turn = FeelPlaceStep("next page") { feel in feel.app.buttons["fight.next"].tap() }
            let result = feel.placeFights([turn], reads: 6, between: tick(app), read: fightPlace(app))
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("late restore") }, result.text)
            }
            return (result, nil)
        }
    }

    /// A tap on the right edge while a Contents jump's veil is up: the bug build queues it and lands a page past the one
    /// chosen; the fixed build swallows it and lands on page 30.
    func testATapWhileAJumpIsUnderWayLandsWhereYouChose() {
        both("fight") { app, feel in
            _ = app.buttons["fight.contents"].waitForExistence(timeout: 10)
            let jump = FeelPlaceStep("Contents to page 30, with a tap on the right edge under the veil") { feel in
                feel.app.buttons["fight.contents"].tap()
                feel.app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            }
            let result = feel.placeFights([.move(jump, landsOn: "Page 30")], reads: 6, between: tick(app), read: fightPlace(app))
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("not where you chose") }, result.text)
            }
            return (result, nil)
        }
    }

    /// No input at all: the bug build's cloud reply, arriving three ticks after the page opens, moves the page; the
    /// fixed build offers it instead.
    func testALateCloudReplyNeverMovesThePlace() {
        both("fight", ["-cloud", "1"]) { app, feel in
            _ = app.buttons["fight.next"].waitForExistence(timeout: 10)
            let result = feel.placeHeld(across: [.noInput], reads: 6, between: tick(app), read: fightPlace(app))
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.hasPrefix("no input moved the place") }, result.text)
            }
            return (result, nil)
        }
    }

    /// Not a pass or fail: one `XCTHitchMetric` reading of the fixed motion page, so the result bundle shows what the
    /// simulator reports (a proxy; gate hitches on a device).
    func testHitchMetricReading() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("XCTHitchMetric needs iOS 26") }
        let (app, feel) = launch("motion", bug: false)
        let advance = FeelClock.darwinNotification("bot.ouro.feel.fixture.tick")
        feel.measureHitches(in: self, iterations: 1) {
            app.buttons["motion.play"].tap()
            _ = feel.film(["motion.card"], steps: 15, tick: 0.1, clock: "motion.clock", advance: advance)
        }
    }
}
