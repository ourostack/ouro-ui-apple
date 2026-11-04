import XCTest

/// Every component transition is smooth: the gallery's frame probe (`FrameProbe`) times each frame while a transition
/// runs, and a test fails when the hitch ratio, hitch milliseconds per second, is over 5 (Apple's "good" line; over 10
/// is critical) or any one frame is more than two refreshes late, a stall anyone would see. A failing transition is
/// measured once more and fails only if it fails again: one stray hitch on a shared CI machine is not the component's.
///
/// The probe counts every frame on screen, so a hitch in the system's own part of a transition (a sheet's dimming
/// and presentation) counts too. On a device, `testTransitionsOnDevice` also reports the same windows through
/// `XCTOSSignpostMetric`; the simulator does not report hitch metrics, so it skips there.
///
/// Frame timing on a simulator depends on the Mac running it. CI runs these on a fresh hosted macos-26 VM, in Release;
/// a local run on a busy Mac can fail without the components being at fault.
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
            if let second = run(), second.ratio < first.ratio { result = second }
        }
        guard let result else { return XCTFail("\(name): the probe gave no result", file: file, line: line) }
        let note = XCTAttachment(string: result.summary)
        note.name = "probe-\(name)"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertLessThanOrEqual(result.ratio, Self.limitRatio, "\(name) hitches: \(result.summary)", file: file, line: line)
        XCTAssertLessThanOrEqual(result.worstFrames, Self.limitWorstFrames, "\(name) stalls a frame: \(result.summary)", file: file, line: line)
    }

    /// Plays a gallery `-demo` (it comes, holds and goes, `repeats` times) and reads the probe's result.
    private func demo(_ name: String, page: String, repeats: Int = 1) -> Result? {
        let app = XCUIApplication()
        let seconds = 1.0 + 4.0 * Double(repeats) + 1.0
        app.launchArguments = ["-theme", "pearl", "-page", page, "-open", "0", "-demo", name, "-probe", "1",
                               "-repeat", String(repeats), "-probeSeconds", String(seconds)]
        app.launch()
        defer { app.terminate() }
        // The window starts a second after the page appears; launch takes a few more.
        return read(app, after: seconds + 4)
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
            let app = window("buttons", delay: 2, seconds: 8)
            defer { app.terminate() }
            let button = app.buttons["Save recipe"]
            guard button.waitForExistence(timeout: 10) else { return nil }
            let target = point(app, button)
            // The window opens 2 s after the page appears and lasts 8 s; this lands about 4 s in.
            Thread.sleep(forTimeInterval: 4)
            target.press(forDuration: 0.6)
            return read(app, after: 7)
        }
    }

    func testAToastSwipedAwayLeavesSmoothly() {
        check("swipe") {
            // The page opens with three toasts that stay until dismissed; the front one is swiped away.
            let app = window("toasts", open: true, delay: 2, seconds: 8)
            defer { app.terminate() }
            let toast = app.staticTexts["Couldn't save"]
            guard toast.waitForExistence(timeout: 10) else { return nil }
            let start = point(app, toast)
            Thread.sleep(forTimeInterval: 4)
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -120)), withVelocity: .fast, thenHoldForDuration: 0)
            let result = read(app, after: 7)
            XCTAssertFalse(toast.exists, "a toast swiped up goes")
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
