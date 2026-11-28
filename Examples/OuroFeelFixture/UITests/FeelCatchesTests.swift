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
        // Only from a pose a test leaves behind: on a freshly booted CI simulator, which reads unknown or face up while
        // its screen is portrait, setting portrait timed out "waiting for confirmation of orientation change" and failed
        // the shard's first test (#188).
        let now = XCUIDevice.shared.orientation
        if now.isLandscape || now == .portraitUpsideDown { XCUIDevice.shared.orientation = .portrait }
        #endif
    }

    private func launch(_ page: String, bug: Bool, _ extra: [String] = []) -> (XCUIApplication, OuroFeel) {
        let app = XCUIApplication()
        app.launchArguments = ["-page", page, "-bug", bug ? "1" : "0"] + extra
        app.launchEnvironment.merge(OuroFeel.recorderEnvironment) { _, new in new }
        app.launch()
        return (app, OuroFeel(app))
    }

    /// Runs `check` with and without the bug: it must fail with it and pass without it. `builds` narrows it to one
    /// build, for a check long enough that each build is its own test (and its own CI shard).
    private func both(_ page: String, _ extra: [String] = [], builds: [Bool] = [true, false], file: StaticString = #filePath, line: UInt = #line,
                      _ check: (XCUIApplication, OuroFeel) -> (FeelResult, FeelFilm?)) {
        for bug in builds {
            let (app, feel) = launch(page, bug: bug, extra)
            let (raw, film) = check(app, feel)
            let result = feel.record(raw, name: "\(page)-\(bug ? "bug" : "fixed")", film: film)
            XCTAssertEqual(result.passed, !bug, "\(page) with bug=\(bug):\n\(result.text)", file: file, line: line)
            app.terminate()
        }
    }

    /// ``both(_:_:builds:file:line:_:)`` for a check judged from a screen film: a failing run also saves the film's
    /// contact sheet beside its report (#73).
    private func both(screens page: String, file: StaticString = #filePath, line: UInt = #line,
                      _ check: (XCUIApplication, OuroFeel) -> (FeelResult, FeelScreenFilm)) {
        for bug in [true, false] {
            let (app, feel) = launch(page, bug: bug)
            let (raw, film) = check(app, feel)
            let result = feel.record(raw, name: "\(page)-\(bug ? "bug" : "fixed")", screenFilm: film)
            XCTAssertEqual(result.passed, !bug, "\(page) with bug=\(bug):\n\(result.text)", file: file, line: line)
            if bug { XCTAssertNotNil(film.contactSheet(), "the failing film has a contact sheet to save", file: file, line: line) }
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
            func filmed() -> (XCUIApplication, OuroFeel, FeelFilm) {
                // The first tap on Open is ignored on purpose: a tap that doesn't take must be noticed and retried,
                // never judged as a page that was never on screen (#84).
                let (app, feel) = launch("transition", bug: bug, ["-missTaps", "1"])
                let open = app.buttons["transition.open"]
                XCTAssertTrue(open.waitForExistence(timeout: 30))
                let title = app.staticTexts["transition.title"]
                var film = feel.recordedFilm(["transition.title"]) { open.tap() }
                // A tap that didn't take films a list with no page: the title is in no frame and not on screen after.
                // One that took late is on screen now, and isn't retried, since the push it filmed is already gone. A
                // stalled recording is never retried here, so the recorder's own failures still fail.
                for _ in 0..<2 where film.stalledAt == nil && film.track("transition.title").isEmpty && !title.exists {
                    film = feel.recordedFilm(["transition.title"]) { open.tap() }
                }
                return (app, feel, film)
            }
            var (app, feel, film) = filmed()
            // A film with one frame held for over 0.3 s is a simulator that froze, not a push that snapped or a
            // recorder that failed: on loaded runners one film had a 4.2 s frame, and another 13 frames, one of them
            // 32.7 s long, which ran it past its cap. A shorter freeze still fails the settle check: this push settles
            // in about 0.4 s, and one 0.5 s frame on main made it 0.9 s against the 0.8 s limit (run 43710948223). A
            // passing film's longest frame was 0.26 s. It is filmed again from a fresh launch; a third frozen film still
            // fails.
            let longestFrame = { (f: FeelFilm) in zip(f.frames, f.frames.dropFirst()).map { $1.t - $0.t }.max() ?? 0 }
            // A film that ran to the recorder's 20 s limit without the page in any frame is a simulator that froze too:
            // on main, a refilmed push stalled at 23.9 s with no page in it, and the page was on screen after (run
            // 43731737949). It is filmed again, up to three films in all. A recorder that stalls while the page is in
            // its frames is never refilmed, so the recorder's own failures still fail.
            let froze = { (f: FeelFilm) in longestFrame(f) > 0.3 || (f.stalledAt != nil && f.track("transition.title").isEmpty) }
            for _ in 0..<2 where froze(film) {
                print("[ouro-feel] the push film froze (longest frame \(longestFrame(film)) s, stalled at \(film.stalledAt.map { "\($0) s" } ?? "never")); filming it once more")
                app.terminate()
                (app, feel, film) = filmed()
            }
            // A good push the runner stalled right before the title moved cannot be judged, so it is filmed once more
            // and the retry is printed; a second unjudged film still fails (#249).
            let busy = { (f: FeelFilm) in f.snaps(of: "transition.title", appearing: true).findings.contains { $0.unchecked && $0.what.contains("busy") } }
            if !bug && busy(film) {
                print("[ouro-feel] the push film was busy where the title moved: \(film.snaps(of: "transition.title", appearing: true).text); filming it once more")
                app.terminate()
                (app, feel, film) = filmed()
            }
            let title = app.staticTexts["transition.title"]
            XCTAssertFalse(film.track("transition.title").isEmpty, title.exists
                ? "the push landed after the film ended, so it was not filmed"
                : "Open never took, so no push was filmed")
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
                XCTAssertTrue(!snap.detections.isEmpty || busy(film), snap.text)
                XCTAssertFalse(snap.passed, snap.text)
                XCTAssertLessThanOrEqual(xs.count, 2, "the bug build's page did not travel: \(xs.sorted())")
            } else {
                feel.expect(snap)
                feel.expect(settle)
                XCTAssertGreaterThanOrEqual(xs.count, 8, "the push was filmed frame by frame: \(xs.sorted())")
            }
            print("[ouro-feel] recorded push (bug \(bug)): \(film.frames.count) frames, \(xs.count) places of the title, cadence \(film.cadence), longest frame \(longestFrame(film))")
            app.terminate()
        }
    }

    /// The bug build's panel off the side fails; the covers of a "Reading Now" row (a horizontal ScrollView inside a
    /// vertical one) run off the side in both builds, and in landscape below the window's bottom too, and are a
    /// carousel's in a scrolled shelf, never outside the window (#67).
    func testInsideTheWindow() {
        both("window") { app, feel in
            let result = feel.insideWindow()
            if !isBugBuild(app) {
                XCTAssertTrue(app.buttons["window.cover.4"].exists || app.descendants(matching: .any)["window.cover.4"].exists,
                              "the row runs off the side, so the check is asked about a cover past the edge")
            } else {
                XCTAssertFalse(result.findings.contains { $0.what.contains("window.cover") }, "no cover is outside the window:\n\(result.text)")
            }
            return (result, nil)
        }
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
    /// The walk takes minutes per build, so each build is its own test: CI can run them side by side.
    func testTheWayBackBugBuild() { theWayBack(bug: true) }
    func testTheWayBackFixedBuild() { theWayBack(bug: false) }

    private func theWayBack(bug only: Bool) {
        both("nav", builds: [only]) { app, feel in
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

    /// The system keyboard is not the app's: with a search field focused, the walk follows none of its keys. A hosted
    /// simulator's Emoji key was once followed, and its picker judged as an overlay that ignores taps outside (#60).
    func testTheKeyboardIsNotWalked() throws {
        let (app, feel) = launch("keyboard", bug: false)
        XCTAssertTrue(app.textFields["keyboard.field"].waitForExistence(timeout: 30))
        // A simulator with a hardware keyboard attached shows no software keyboard, and then there is nothing to skip.
        try XCTSkipUnless(app.keyboards.firstMatch.waitForExistence(timeout: 10), "no software keyboard on this simulator")
        let result = feel.record(feel.wayBack(follow: FeelFollow(types: [.button]), depth: 1), name: "keyboard")
        for key in ["Emoji", "Dictate", "Next keyboard"] {
            XCTAssertFalse(result.text.contains(key), "the keyboard's \(key) key was walked:\n\(result.text)")
        }
        XCTAssertTrue(result.findings.contains { $0.what.contains("keyboard.recipe") } || (result.measures["screens"] ?? 0) >= 1,
                      "the app's own Recipe link was walked:\n\(result.text)")
        XCTAssertTrue(result.passed, "a search field with the keyboard up has no broken way back:\n\(result.text)")
        app.terminate()
    }

    /// Shapes once misread as missing ways back, none a bug (``KitchenPage`` in the app): a tab switch, a zoom push whose
    /// edge swipe starts lower, a popover of a stepper, and a menu with a submenu. The walk passes them all.
    func testWhatIsNotABrokenWayBack() {
        var (app, feel) = launch("kitchen", bug: false)
        XCTAssertTrue(app.buttons["kitchen.seeAll"].waitForExistence(timeout: 30))
        var result = feel.wayBack(follow: FeelFollow(types: [.button, .cell]), depth: 1)
        // On a loaded free runner the simulator can drop every gesture sent to the zoomed recipe, through the walk's own
        // relaunch too (#112, and #193 on PR #189: twelve gestures, all moved=false, back button hittable). The walk then
        // says it could not check, and nothing else is wrong; walk once more on a fresh launch. A real miss comes back.
        let untouched = { (r: FeelResult) in
            !r.passed && r.findings.allSatisfy { $0.note || ($0.unchecked && $0.what.contains("the touch never reached the app")) }
        }
        if untouched(result) {
            print("[ouro-feel] no gesture reached the zoomed recipe; walking once more on a fresh launch (#193)")
            app.terminate()
            (app, feel) = launch("kitchen", bug: false)
            XCTAssertTrue(app.buttons["kitchen.seeAll"].waitForExistence(timeout: 30))
            result = feel.wayBack(follow: FeelFollow(types: [.button, .cell]), depth: 1)
        }
        result = feel.record(result, name: "kitchen")
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
            // Play before the film: nothing moves until the test advances the app's clock, and a Play that did not take
            // would leave a still card that no motion check can fail (#65). Tapped again if it did not take.
            let played = app.staticTexts["motion.played"]
            for _ in 0..<3 where !played.exists {
                play.tap()
                _ = played.waitForExistence(timeout: 10)
            }
            XCTAssertTrue(played.exists, "the motion page never started playing, so its film was not judged")
            guard played.exists else { return (FeelResult(check: "motion", passed: false, summary: "could not check: Play never took"), nil) }
            let film = feel.film(["motion.card", "motion.ghost", "Pancakes", "bar.full", "bar.compact"], steps: 35, tick: 0.1,
                                 clock: "motion.clock", advance: FeelClock.darwinNotification("bot.ouro.feel.fixture.tick"))
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
            // Play before the film, as the motion page does (#65): nothing changes until the test advances the app's
            // clock, and a Play that did not take would film a still page with no badge (#86).
            let played = app.staticTexts["flicker.played"]
            guard tapUntil(play, { played.exists }) else {
                XCTFail("the flicker page never started playing, so its film was not judged")
                return (FeelResult(check: FeelGenre.flicker.rawValue, passed: false, summary: "could not check: Play never took"), nil)
            }
            let film = feel.film(["flicker.words", "flicker.badge"], steps: 12, tick: 0.1, clock: "flicker.clock",
                                 advance: FeelClock.darwinNotification("bot.ouro.feel.fixture.tick"))
            let result = film.flickers(of: ["flicker.words", "flicker.badge"])
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("flicker.words") && $0.what.contains("taken back") }, result.text)
                XCTAssertTrue(result.detections.contains { $0.what.contains("flicker.badge") && $0.what.contains("blinked on") }, result.text)
            }
            return (result, film)
        }
    }

    /// Flicker of the whole screen, judged from screenshots on the app's own clock: no element names the page. The bug's
    /// page turns, goes back for three ticks and turns again; the fixed page turns once.
    func testScreenFlicker() {
        both(screens: "screen-flicker") { app, feel in
            let play = app.buttons["screenflicker.play"]
            _ = play.waitForExistence(timeout: 10)
            // Both builds turn the page three ticks after Play, so a film that rests in one state only is a Play that
            // didn't take (CI, #185's run 43735965549: the bug build "never came back to a state it left"), never a page
            // that held. It is filmed once more from a fresh launch; a second still film is judged as it is.
            var film = FeelScreenFilm(frames: [])
            for attempt in 1...2 {
                if attempt > 1 {
                    print("[ouro-feel] the screen film never left its first state, so Play didn't take; filming it once more (#188)")
                    app.terminate()
                    app.launch()
                    _ = play.waitForExistence(timeout: 10)
                }
                film = feel.screenFilm(steps: 14, tick: 0.1, clock: "screenflicker.clock",
                                       advance: FeelClock.darwinNotification("bot.ouro.feel.fixture.tick")) { play.tap() }
                if film.stalledAt != nil || film.states().count >= 2 { break }
            }
            XCTAssertNil(film.stalledAt, "the app's clock answered every tick")
            let result = film.flickers()
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("came back to it") }, result.text)
            }
            return (result, film)
        }
    }

    /// In landscape, the screen film still blanks the app's clock (#73): its label changes every tick, so a clock left
    /// showing would make every tick a new state. With nothing else moving, every sample of the film is the same picture.
    /// The check is not vacuous: unblanked, at this width, two ticks of the clock are different pictures.
    func testTheClockIsBlankedInLandscape() {
        clockIsBlanked(landscape: true)
    }

    /// The same in portrait. On an iPhone the other screen films prove it too; on an iPad the fixture, an iPhone app,
    /// runs in compatibility mode, in a window smaller than the screen, and CI's iPad lane runs this and the landscape
    /// test there to prove the blanking lands on the clock (#73, item 2).
    func testTheClockIsBlankedInPortrait() {
        clockIsBlanked(landscape: false)
    }

    private func clockIsBlanked(landscape: Bool) {
        let (app, feel) = launch("screen-flicker", bug: false)
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["screenflicker.play"].waitForExistence(timeout: 10))
        let clock = app.staticTexts["screenflicker.clock"]
        let way = landscape ? "landscape" : "portrait"
        if landscape {
            XCUIDevice.shared.orientation = .landscapeLeft
            let deadline = Date().addingTimeInterval(10)
            // The screen turns. On an iPad the fixture, an iPhone app in compatibility mode, keeps a portrait window in
            // the middle of the landscape screen, so the window's own shape says nothing.
            func wide() -> Bool { let s = XCUIScreen.main.screenshot().image.size; return clock.exists && s.width > s.height }
            while !wide(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
            XCTAssertTrue(wide(), "the screen never turned to landscape")
        }
        Thread.sleep(forTimeInterval: 1)
        let tick = FeelClock.darwinNotification("bot.ouro.feel.fixture.tick")
        // Unblanked (no element is keyed "no-clock"), two ticks apart: the clock's digits show.
        guard let before = feel.screenPicture(clock: "no-clock", width: 640) else { return XCTFail("no screenshot") }
        tick(); tick()
        Thread.sleep(forTimeInterval: 0.5)
        guard let after = feel.screenPicture(clock: "no-clock", width: 640) else { return XCTFail("no screenshot") }
        XCTAssertGreaterThan(FeelScreenFilm.difference(before, after) ?? 0, 0, "the clock's ticks don't show at this width, so the check below proves nothing")
        let film = feel.screenFilm(steps: 6, tick: 0.1, clock: "screenflicker.clock", advance: tick, width: 640)
        XCTAssertNil(film.stalledAt, "the app's clock answered every tick")
        if landscape {
            XCTAssertGreaterThan(film.frames.first.map { $0.width } ?? 0, film.frames.first.map { $0.height } ?? 0, "the film is landscape")
        }
        // Where a sample differs from the first, in points, beside where the clock is: so a failure says what changed.
        guard let first = film.frames.first else { return XCTFail("the film has no samples") }
        let scale = XCUIScreen.main.screenshot().image.size.width / CGFloat(first.width)
        let (snapshotWindow, seen) = feel.seen(["screenflicker.clock"])
        let snapshotClock = seen.first?.frame ?? .null
        for (n, frame) in film.frames.enumerated().dropFirst() where FeelScreenFilm.difference(first, frame) != 0 {
            var box = CGRect.null
            for i in 0..<min(first.gray.count, frame.gray.count) where first.gray[i] != frame.gray[i] {
                box = box.union(CGRect(x: CGFloat(i % first.width) * scale, y: CGFloat(i / first.width) * scale, width: scale, height: scale))
            }
            XCTFail("sample \(n) differs from the first at \(box) (screen points), the clock at \(clock.frame), window \(app.windows.firstMatch.frame); in the app's snapshot, the clock at \(snapshotClock), window \(snapshotWindow): the clock is not blanked in \(way)")
        }
        feel.record(film.flickers(states: 1), name: "\(way)-clock", screenFilm: film)
    }

    /// The first page shown after an open holds, judged from screenshots: the bug's cover goes onto another page that
    /// then jumps to his; the fixed cover holds until his page shows.
    func testRevealHolds() {
        both(screens: "reveal") { app, feel in
            let open = app.buttons["reveal.open"]
            _ = open.waitForExistence(timeout: 10)
            // The cover is up until Open: its picture is what the film's cover must look like.
            guard let cover = feel.screenPicture(clock: "reveal.clock") else {
                return (FeelResult.judged(check: FeelGenre.jumpAfterLanding.rawValue, passing: "", failing: { _ in "" },
                                          findings: [.couldNotCheck("no screenshot of the cover")]), FeelScreenFilm(frames: []))
            }
            // 2.4 s: the fixed build's page shows 0.7 s after Open takes, and a loaded runner can take Open late (main,
            // 2026-11-15: a 1.4 s film ended on the cover, "film for longer"). The bug build's jump comes 0.4 s after its
            // first page, so a longer film still sees it.
            let film = feel.screenFilm(steps: 24, tick: 0.1, clock: "reveal.clock",
                                       advance: FeelClock.darwinNotification("bot.ouro.feel.fixture.tick")) { open.tap() }
            XCTAssertNil(film.stalledAt, "the app's clock answered every tick")
            let result = film.revealHolds(cover: cover)
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("was replaced") }, result.text)
            }
            return (result, film)
        }
    }

    /// The same open, from a shelf that looks nothing like the cover (#73, item 4). The cover's picture is taken once
    /// Open has put the cover up, before the clock moves it on, and the film is judged against that. Judged against the
    /// shelf, the screen before Open, the film can't be checked, since no rest looks like it.
    func testRevealHoldsFromACoverShotWhileItIsUp() {
        both(screens: "reveal-shelf") { app, feel in
            let open = app.buttons["reveal.open"]
            _ = open.waitForExistence(timeout: 10)
            func couldNotCheck(_ why: String) -> FeelResult {
                FeelResult.judged(check: FeelGenre.jumpAfterLanding.rawValue, passing: "", failing: { _ in "" }, findings: [.couldNotCheck(why)])
            }
            guard let shelf = feel.screenPicture(clock: "reveal.clock") else { return (couldNotCheck("no screenshot of the shelf"), FeelScreenFilm(frames: [])) }
            open.tap()
            // Open has taken once the cover is up: the screen no longer looks like the shelf. The clock doesn't move
            // until the film ticks it, so the cover stays up for its picture.
            var cover = shelf
            let deadline = Date().addingTimeInterval(10)
            while (FeelScreenFilm.difference(shelf, cover) ?? 0) < 1, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                if let now = feel.screenPicture(clock: "reveal.clock") { cover = now }
            }
            XCTAssertGreaterThan(FeelScreenFilm.difference(shelf, cover) ?? 0, 1, "the cover looks like the shelf, so this proves nothing")
            let film = feel.screenFilm(steps: 24, tick: 0.1, clock: "reveal.clock",
                                       advance: FeelClock.darwinNotification("bot.ouro.feel.fixture.tick"))
            XCTAssertNil(film.stalledAt, "the app's clock answered every tick")
            let fromShelf = film.revealHolds(cover: shelf)
            XCTAssertTrue(fromShelf.findings.contains { $0.unchecked },
                          "judged against the shelf, nothing looks like the cover: \(fromShelf.text)")
            let result = film.revealHolds(cover: cover)
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("was replaced") }, result.text)
            }
            return (result, film)
        }
    }

    /// The same open as ``testRevealHolds`` for an app with no clock of its own (#94): the page runs on wall time and the
    /// film is one screenshot per XCUITest read, judged in reads. The bug's cover goes onto another page that then jumps
    /// to his; the fixed cover holds until his page shows.
    func testRevealHoldsByReads() {
        both("reveal-reads") { app, feel in
            let open = app.buttons["revealreads.open"]
            _ = open.waitForExistence(timeout: 10)
            // At least 7 s: the bug's jump comes 4 s after Open, and a loaded runner can take the tap late. The film
            // shoots its own cover first, with its own settings, while the cover is up (#73, item 5).
            let film = feel.screenFilm(cover: true, atLeast: 7) { open.tap() }
            XCTAssertEqual(film.byReads, true)
            XCTAssertNotNil(film.cover, "the film shot its cover")
            XCTAssertTrue(film.timedBy?.contains("reads") ?? false, film.timedBy ?? "no timedBy")
            let result = film.revealHolds()
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("was replaced") }, result.text)
            }
            return (result, nil)
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

    /// Place kept through stray input in a reader that scrolls: a tap at the top edge (the status bar) and a swipe
    /// across and back, among the other stray steps. The bug build's status bar tap scrolls to the chapter's start, and
    /// coming back from the next chapter lands at this one's end, as Gatefold build 39's scroll mode did.
    func testPlaceKeptThroughAStatusBarTapAndASwipeAcrossAndBack() {
        both("scroll-reader") { app, feel in
            let place = app.staticTexts["scroll.place"]
            XCTAssertTrue(place.waitForExistence(timeout: 10))
            let result = feel.placeHeld(across: FeelPlaceStep.strayReading, read: { place.label })
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.hasPrefix("tap at the top edge") }, result.text)
                XCTAssertTrue(result.detections.contains { $0.what.hasPrefix("swipe across and back") }, result.text)
                XCTAssertFalse(result.detections.contains { $0.what.hasPrefix("stray tap") }, result.text)
            }
            return (result, nil)
        }
    }

    /// The fixed build's swipe across really reaches the next chapter, so the round trip's pass is a trip that came
    /// back, not a swipe that never arrived.
    func testTheSwipeAcrossReachesTheNextChapter() {
        let (app, _) = launch("scroll-reader", bug: false)
        let place = app.staticTexts["scroll.place"]
        XCTAssertTrue(place.waitForExistence(timeout: 10))
        let start = place.label
        let w = app.windows.firstMatch.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: w.minX + w.width * 0.8, dy: w.midY))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: w.minX + w.width * 0.2, dy: w.midY)), withVelocity: .fast, thenHoldForDuration: 0)
        let away = NSPredicate { _, _ in place.label.hasPrefix("chapter 2") }
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: away, object: nil)], timeout: 10), .completed,
                       "the swipe across reached chapter 2 (was \(start), now \(place.label))")
        app.terminate()
    }

    /// Covered content: the bug build's running head sits over the first line and its Close button under the status
    /// bar; the fixed build's sit clear.
    func testCoveredContent() {
        both("cover") { app, feel in
            XCTAssertTrue(app.staticTexts["cover.line.1"].waitForExistence(timeout: 10))
            let result = feel.uncovered(by: ["cover.head", "cover.close"])
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("\"cover.head\" covers") }, result.text)
                // Only when the system reported the status bar along the window's top; otherwise the report notes it,
                // and this says so in the log rather than passing quietly.
                if result.findings.contains(where: { $0.note && $0.what.contains("status bar") }) {
                    print("[ouro-feel] cover-bug: the status bar was not read, so Close under it was not judged")
                } else {
                    XCTAssertTrue(result.detections.contains { $0.what.contains("\"cover.close\"") && $0.what.contains("status bar") },
                                  result.text)
                }
            }
            return (result, nil)
        }
    }

    /// Content readiness (gatefold run 46076998864): a check waits for what it measures instead of scoring an empty
    /// page. The fixed page's words and ready signal arrive 15 s after the page appears, and the covered-content check waits for
    /// them and passes. The bug page's never arrive, and the check fails as "never became ready", with no bug found.
    /// Each build runs with the app's ready signal and without it, when the check waits on its own content alone.
    func testACheckWaitsForContentAndSaysWhenItNeverComes() {
        for signal in [true, false] {
            for bug in [true, false] {
                let name = "late-\(bug ? "bug" : "fixed")-\(signal ? "signal" : "content")"
                var (app, feel) = launch("late", bug: bug, ["-lateBy", "15"])
                if signal { feel.ready = { ($0.descendants(matching: .any)["late.ready"].firstMatch.value as? String) == "1" } }
                feel.readyTimeout = bug ? 20 : 60
                XCTAssertTrue(app.staticTexts["late.head"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.staticTexts["late.line.1"].exists, "\(name): the words were there before the check began")
                let began = Date()
                let result = feel.record(feel.uncovered(by: ["late.head"], within: "late.page"), name: name)
                let took = Date().timeIntervalSince(began)
                print("[ouro-feel] \(name): \(result.passed ? "PASS" : "FAIL") after \(String(format: "%.1f", took)) s: \(result.summary)")
                if bug {
                    XCTAssertFalse(result.passed, "\(name)\n\(result.text)")
                    XCTAssertTrue(result.summary.hasPrefix("never became ready: no content came on screen"), "\(name)\n\(result.text)")
                    XCTAssertTrue(result.findings.contains(where: \.neverReady), "\(name)\n\(result.text)")
                    XCTAssertTrue(result.detections.isEmpty, "\(name): an empty page is never scored\n\(result.text)")
                    XCTAssertGreaterThanOrEqual(result.measures["waited"] ?? 0, 20, "\(name)\n\(result.text)")
                } else {
                    XCTAssertTrue(result.passed, "\(name)\n\(result.text)")
                    XCTAssertTrue(app.staticTexts["late.line.1"].exists, "\(name): the check passed before the words came")
                }
                app.terminate()
            }
        }
    }

    /// Inside the window, for what you read too: the bug build's text column slides past the window's side while
    /// every control stays inside.
    func testInsideTheWindowAlsoChecksTheTextColumn() {
        both("cover") { app, feel in
            XCTAssertTrue(app.staticTexts["cover.line.1"].waitForExistence(timeout: 10))
            let result = feel.insideWindow(poses: [.current], also: ["cover.column"])
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("cover.column") }, result.text)
            }
            return (result, nil)
        }
    }

    /// Viewport holds still: the bug build's page scrolls sideways too and its lines run past the window's side, so a
    /// drag across pans the text; the fixed build's page holds, and the shelf inside it scrolls sideways as it should.
    func testViewportHoldsStill() {
        both("viewport") { app, feel in
            XCTAssertTrue(app.staticTexts["viewport.line.1"].waitForExistence(timeout: 10))
            let result = feel.viewportHolds()
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("past the trailing side of scroll view \"viewport.page\"") },
                              result.text)
                XCTAssertTrue(result.detections.contains { $0.what.contains("moved its content") }, result.text)
            }
            return (result, nil)
        }
    }

    /// Chrome floats over content: the bug build's pill sits under the page and shrinks it; the fixed build's floats
    /// over the lines, which run underneath and end clear of it.
    func testChromeFloatsOverContent() {
        both("float") { app, feel in
            XCTAssertTrue(app.staticTexts["float.line.1"].waitForExistence(timeout: 10))
            let result = feel.chromeFloats(["float.restart"], over: "float.page")
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("sits beside") }, result.text)
            }
            return (result, nil)
        }
    }

    /// Chrome floats over content, at the end: the bug build's pill floats, but the last line stays under it however
    /// far the page scrolls.
    func testChromeLeavesTheEndClear() {
        both("float-under") { app, feel in
            XCTAssertTrue(app.staticTexts["float.line.1"].waitForExistence(timeout: 10))
            let result = feel.chromeFloats(["float.restart"], over: "float.page")
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("stays") && $0.what.contains("under") }, result.text)
            }
            return (result, nil)
        }
    }

    /// One action finishes the intent: the bug build's book downloads and stays shut until a second tap; the fixed
    /// build's opens once its download is done.
    func testOneActionFinishesTheIntent() {
        both("intent") { app, feel in
            let book = app.buttons["intent.book"]
            XCTAssertTrue(book.waitForExistence(timeout: 10))
            let result = feel.finishesIntent(book, opens: "intent.reader", within: 20)
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("took a second tap") }, result.text)
            }
            return (result, nil)
        }
    }

    /// Still while idle: the bug build's Close and status bar take turns three times a second with no input.
    func testStillWhileIdle() {
        both("idle") { app, feel in
            XCTAssertTrue(app.staticTexts["idle.page"].waitForExistence(timeout: 10))
            let result = feel.stillWhileIdle(for: 3)
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("\"idle.close\"") }, result.text)
            }
            return (result, nil)
        }
    }

    /// Still while idle judges only what the app draws (gatefold #639's run 46078753578): a control with no name that
    /// comes into the app far past the window's edge mid-watch is not a change.
    func testStillWhileIdleJudgesOnlyWhatIsDrawn() {
        let (app, feel) = launch("idle", bug: false, ["-offstage", "1"])
        XCTAssertTrue(app.staticTexts["idle.page"].waitForExistence(timeout: 10))
        let before = app.buttons.count
        let result = feel.record(feel.stillWhileIdle(for: 12), name: "idle-offstage")
        let after = app.buttons.count
        print("[ouro-feel] idle-offstage: \(result.passed ? "PASS" : "FAIL"): \(result.summary) (buttons \(before) then \(after))")
        XCTAssertEqual(before, 1, "the near miss came before the watch began")
        XCTAssertEqual(after, 2, "the control past the edge never came into the app, so this proves nothing")
        XCTAssertTrue(result.passed, result.text)
        app.terminate()
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

    /// Taps until `took` holds, up to three times. A loaded simulator can drop a tap, and a move that never happened
    /// would be judged as a place that held (#86); with nothing on the app's clock advancing, a second tap is safe.
    private func tapUntil(_ target: XCUIElement, _ took: () -> Bool) -> Bool {
        for _ in 0..<3 where !took() {
            target.tap()
            let deadline = Date().addingTimeInterval(5)
            while !took() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        }
        return took()
    }

    /// Navigation that fights you, read once a tick on the app's own clock: the bug build's sync lands three ticks after
    /// Next and pulls the page back; the fixed build's sync agrees.
    func testNavigationThatFightsYou() {
        both("fight") { app, feel in
            _ = app.buttons["fight.next"].waitForExistence(timeout: 10)
            // Both builds show page 2 at once; the bug's sync pulls it back only once the clock advances.
            let turn = FeelPlaceStep("next page") { feel in
                let page = feel.app.staticTexts["fight.page"]
                // Any page past the first: on a loaded runner a tap can take after tapUntil's 5 s wait, and the tap
                // sent after it takes too (Page 3). That is still Next taking, and each build's sync still follows it.
                XCTAssertTrue(self.tapUntil(feel.app.buttons["fight.next"]) { page.exists && page.label != "Page 1" }, "Next never took")
            }
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
                let veil = feel.app.staticTexts["fight.veil"]
                XCTAssertTrue(self.tapUntil(feel.app.buttons["fight.contents"]) { veil.exists }, "Contents never took")
                let edge = feel.app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
                if self.isBugBuild(feel.app) {
                    // The bug build queues the tap and marks it; a dropped one would land on page 30 and pass it.
                    let queued = feel.app.staticTexts["fight.queued"]
                    for _ in 0..<3 where !queued.exists { edge.tap(); _ = queued.waitForExistence(timeout: 5) }
                    XCTAssertTrue(queued.exists, "the edge tap under the veil never took")
                } else {
                    edge.tap()
                }
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

    // MARK: Gatefold's jank hunt, 2026-11-27 (ourostack/gatefold#646 to #654)

    /// Content clears the fold, on a fold the page declares (no simulator folds): the bug's one column runs across it;
    /// the fixed page has a page on each side.
    func testContentClearsTheFold() {
        both("fold") { app, feel in
            _ = app.descendants(matching: .any)["ouro.fold"].waitForExistence(timeout: 10)
            let result = feel.clearsTheFold(spread: true, posture: "a simulated fold, held like a book")
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("runs across the fold") }, result.text)
            }
            return (result, nil)
        }
    }

    /// A turn lays out like a fresh launch: the bug's portrait panel lingers in landscape, and is missing when it turns
    /// back; the fixed page's panel follows the window.
    func testATurnLaysOutLikeAFreshLaunch() {
        both("relayout") { app, feel in
            _ = app.descendants(matching: .any)["relayout.page"].waitForExistence(timeout: 10)
            let result = feel.laysOutFresh()
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("\"relayout.panel\" is still on screen") }, result.text)
            }
            return (result, nil)
        }
    }

    /// Your place survives a turn, with a scroll between turns: the bug goes back to the first turn's place; the fixed
    /// page keeps the line at the top.
    func testYourPlaceSurvivesATurn() {
        both("turn-place") { app, feel in
            _ = app.scrollViews["turn.page"].waitForExistence(timeout: 10)
            let result = feel.placeSurvivesTurns(within: "turn.page")
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("the place") }, result.text)
            }
            return (result, nil)
        }
    }

    /// A jump lands on its own, on time: the bug's Contents jump waits for the next tap on the page; the fixed one lands.
    func testAJumpLandsOnItsOwn() {
        both("jump") { app, feel in
            let contents = app.buttons["jump.contents"]
            _ = contents.waitForExistence(timeout: 10)
            let result = feel.landsOnItsOwn(contents, on: "Page 30")
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("landed only after a tap") }, result.text)
            }
            return (result, nil)
        }
    }

    /// What you asked for lands in clear view: the bug's search hit lands under the "Back to where you were" pill; the
    /// fixed one near the top.
    func testWhatYouAskedForLandsInClearView() {
        both("hit") { app, feel in
            let search = app.buttons["hit.result"]
            _ = search.waitForExistence(timeout: 10)
            let result = feel.landsInClearView("hit.target", chrome: ["hit.back"], over: "hit.page") { search.tap() }
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("landed under") }, result.text)
            }
            return (result, nil)
        }
    }

    /// A notice gets out of the way: the bug's notice stays over the first line; the fixed page makes room for it.
    func testANoticeGetsOutOfTheWay() {
        both("notice") { app, feel in
            _ = app.descendants(matching: .any)["notice.banner"].waitForExistence(timeout: 10)
            let result = feel.noticeGivesWay("notice.banner", within: "notice.page", after: 3)
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("still covers") }, result.text)
            }
            return (result, nil)
        }
    }

    /// Every target is big enough to hit: the bug's close button is its 14 pt glyph; the fixed one is 44 pt.
    func testEveryTargetIsBigEnoughToHit() {
        both("targets") { app, feel in
            _ = app.buttons["targets.close"].waitForExistence(timeout: 10)
            let result = feel.targetsBigEnough()
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("\"targets.close\" is 14×14 pt") }, result.text)
            }
            return (result, nil)
        }
    }

    /// The screen shows only the before, the after or a veil, at a jump judged from screenshots: the bug shows another
    /// page on the way; the fixed jump shows a plain veil, then the target.
    func testTheScreenShowsOnlyTheBeforeTheAfterOrAVeilAtAJump() {
        both(screens: "landing") { app, feel in
            let jump = app.buttons["landing.jump"]
            _ = jump.waitForExistence(timeout: 10)
            // At least 4 s: the page lands 1.5 s after Jump, and a loaded runner can take the tap late.
            let film = feel.screenFilm(cover: true, atLeast: 4) { jump.tap() }
            let result = feel.beforeAfterOrVeil(film)
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("neither the before, the after nor a veil") }, result.text)
            }
            return (result, film)
        }
    }

    /// The same through a turn, whose pictures change shape: the bug's page is drawn squeezed for 3 s after it; the
    /// fixed page re-lays out with the turn.
    func testTheScreenShowsOnlyTheBeforeTheAfterOrAVeilThroughATurn() {
        both(screens: "turn-film") { app, feel in
            _ = app.wait(for: .runningForeground, timeout: 10)
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            let film = feel.screenFilm(cover: true, atLeast: 5) { XCUIDevice.shared.orientation = .landscapeLeft }
            // Judged before turning back: its later picture must be of the landscape after.
            let result = feel.beforeAfterOrVeil(film)
            XCUIDevice.shared.orientation = .portrait
            if isBugBuild(app) {
                XCTAssertTrue(result.detections.contains { $0.what.contains("neither the before, the after nor a veil") }, result.text)
            }
            return (result, film)
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
