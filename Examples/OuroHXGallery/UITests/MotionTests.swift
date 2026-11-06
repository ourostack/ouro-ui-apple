import XCTest

/// Every component transition is smooth: the gallery's frame probe (`FrameProbe`) times each frame while a transition
/// runs, and a test fails when the hitch ratio, hitch milliseconds per second, is over 5 (Apple's "good" line; over 10
/// is critical) or any one frame is more than two refreshes late, a stall anyone would see. A failing transition is
/// measured up to twice more and fails only if it never runs smooth: a stray hitch on a shared CI machine is not the
/// component's.
///
/// The probe counts every frame on screen, so a hitch in the system's own part of a transition (a sheet's dimming
/// and presentation) counts too. On a device, `testTransitionsOnDevice` also reports the same windows through
/// `XCTOSSignpostMetric`; the simulator does not report hitch metrics, so it skips there.
///
/// Frame timing on a simulator depends on the Mac running it. CI runs these on a fresh hosted macos-26 VM, in Release,
/// and reports them there without gating: that VM has no GPU and its timing swings run to run (#25). A local run on a
/// busy Mac can fail without the components being at fault too.
@MainActor
final class MotionTests: XCTestCase {
    nonisolated static let limitRatio = 5.0
    /// Refresh intervals late: 2 is a frame shown three refreshes after the last.
    nonisolated static let limitWorstFrames = 2.0

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    struct Result {
        let ratio: Double
        let worstFrames: Double
        let summary: String
        var smooth: Bool { ratio <= MotionTests.limitRatio && worstFrames <= MotionTests.limitWorstFrames }
    }

    /// Waits out the probe's window without touching the app (a query takes its main thread and makes hitches of its
    /// own), then reads the result.
    private func read(_ app: XCUIApplication, after seconds: TimeInterval, timeout: TimeInterval = 15) -> Result? {
        Thread.sleep(forTimeInterval: seconds)
        let probe = app.staticTexts["probe"]
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'frames='"), object: probe)
        guard XCTWaiter().wait(for: [done], timeout: timeout) == .completed else { return nil }
        let summary = probe.label
        var fields: [String: String] = [:]
        for part in summary.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2 { fields[String(pair[0])] = String(pair[1]) }
        }
        guard let ratio = fields["ratio"].flatMap(Double.init), let worst = fields["worstFrames"].flatMap(Double.init) else { return nil }
        return Result(ratio: ratio, worstFrames: worst, summary: summary)
    }

    /// Measures with `run`, and once more if the first is not smooth; checks the better of the two.
    private func check(_ name: String, file: StaticString = #filePath, line: UInt = #line, _ run: () -> Result?) {
        var result = run()
        if let first = result, !first.smooth {
            let note = XCTAttachment(string: first.summary)
            note.name = "probe-\(name)-first"
            note.lifetime = .keepAlways
            add(note)
            // It fails only if it keeps failing: up to two more runs, the first smooth one counts, or else the best.
            // Two were not enough on CI's hosted VM, where one run stalls 30 to 60 ms on a transition the next
            // runs clean (#14, 2026-11-06: the banner failed twice in one run and passed in the run before).
            for _ in 0..<2 where !(result?.smooth ?? false) {
                if let next = run(), next.smooth || next.ratio < (result?.ratio ?? .infinity) { result = next }
            }
        }
        guard let result else { return XCTFail("\(name): the probe gave no result", file: file, line: line) }
        let note = XCTAttachment(string: result.summary)
        note.name = "probe-\(name)"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertLessThanOrEqual(result.ratio, Self.limitRatio, "\(name) hitches: \(result.summary)", file: file, line: line)
        XCTAssertLessThanOrEqual(result.worstFrames, Self.limitWorstFrames, "\(name) stalls a frame: \(result.summary)", file: file, line: line)
    }

    /// Plays a gallery `-demo` (it comes, holds and goes, `repeats` times) and reads the probe's result. The demo plays
    /// once unmeasured first (`-warm 1`), so the probe times what every play costs: on CI's GPU-less VM the first glass
    /// a process draws stalled 180 to 415 ms on every launch, which a Mac's simulator never showed. The first play is
    /// timed by the host-video captures instead (W8 round 6).
    private func demo(_ name: String, page: String, repeats: Int = 1) -> Result? {
        let app = XCUIApplication()
        let seconds = 1.0 + 4.0 * Double(repeats) + 1.0
        app.launchArguments = ["-theme", "pearl", "-page", page, "-open", "0", "-demo", name, "-probe", "1", "-warm", "1",
                               "-repeat", String(repeats), "-probeSeconds", String(seconds)]
        app.launch()
        defer { app.terminate() }
        // The window starts a second after the warm-up play ends (up to 7 s); launch takes a few more.
        return read(app, after: seconds + 4 + 7)
    }

    func testAToastArrivesAndLeavesSmoothly() { check("toast") { demo("toast", page: "toasts") } }
    func testAToastDismissedWhileArrivingTurnsAroundSmoothly() { check("toast-interrupt") { demo("toast-interrupt", page: "toasts") } }
    func testAToastStackGrowsAndEmptiesSmoothly() { check("stack") { demo("stack", page: "toasts") } }
    func testABannerFoldsAwayAndBackSmoothly() { check("banner") { demo("banner", page: "banners") } }
    func testABannerHiddenWhileFoldingTurnsAroundSmoothly() { check("banner-interrupt") { demo("banner-interrupt", page: "banners") } }
    func testASheetOpensAndClosesSmoothly() { check("sheet") { demo("sheet", page: "sheet") } }
    func testAnEmptyStateArrivesSmoothly() { check("empty") { demo("empty", page: "empty") } }

    /// Opens `page` with a probe window `delay` seconds after it appears, lasting `seconds`, for a gesture inside it.
    private func window(_ page: String, open: Bool = false, delay: Double, seconds: Double) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", "pearl", "-page", page, "-open", open ? "1" : "0", "-probe", "1",
                               "-probeDelay", String(delay), "-probeSeconds", String(seconds)]
        app.launch()
        return app
    }

    /// A point on screen for `element`, found now, so using it later does not query the app inside the window.
    private func point(_ app: XCUIApplication, _ element: XCUIElement) -> XCUICoordinate {
        let frame = element.frame
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY))
    }

    func testAButtonPressesAndReleasesSmoothly() {
        check("press") {
            // The window opens 5 s after the page appears, once finding the button (which takes the app's main
            // thread) is done, and lasts 8 s; the press lands about 1 to 3 s in, and the result is read after it ends.
            // As for the demos, one press first, unmeasured: on CI's GPU-less VM a process's first press stalls on
            // drawing, which a Mac's simulator never showed (W8 round 7).
            let app = window("buttons", delay: 5, seconds: 8)
            defer { app.terminate() }
            let button = app.buttons["Save recipe"]
            guard button.waitForExistence(timeout: 10) else { return nil }
            let target = point(app, button)
            target.press(forDuration: 0.6)
            Thread.sleep(forTimeInterval: 5.4)
            target.press(forDuration: 0.6)
            return read(app, after: 8)
        }
    }

    func testAToastSwipedAwayLeavesSmoothly() {
        check("swipe") {
            // The page opens with three toasts that stay until dismissed. The front one is swiped away unmeasured,
            // as for the press, and the next, come to the front in its place, is swiped inside the window.
            let app = window("toasts", open: true, delay: 5, seconds: 8)
            defer { app.terminate() }
            let first = app.staticTexts["Couldn\u{2019}t save"]
            guard first.waitForExistence(timeout: 10) else { return nil }
            let start = point(app, first)
            let swipe = { start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -120)), withVelocity: .fast, thenHoldForDuration: 0) }
            swipe()
            Thread.sleep(forTimeInterval: 5.5)
            swipe()
            let result = read(app, after: 8)
            XCTAssertFalse(first.exists, "a toast swiped up goes")
            XCTAssertFalse(app.staticTexts["Recipe deleted"].exists, "the next toast, swiped up, goes")
            return result
        }
    }

    /// Report only: on a device, a demo's window as `XCTOSSignpostMetric` hitch metrics, beside the probe's numbers.
    /// It has no baseline, so it cannot fail; the probe tests above are the gate.
    func testTransitionsOnDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("The simulator does not report hitch metrics; the probe tests above cover it.")
        #else
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        let metric = XCTOSSignpostMetric(subsystem: "bot.ouro.hx.gallery", category: "motion", name: "transition")
        measure(metrics: [metric], options: options) { _ = demo("toast", page: "toasts") }
        #endif
    }
}
