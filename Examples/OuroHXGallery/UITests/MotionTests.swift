import XCTest

/// Every component transition is smooth: the gallery's frame probe (`FrameProbe`) times each frame while a transition
/// runs, and a test fails when the hitch ratio, hitch milliseconds per second, is over 5 (Apple's "good" line; over 10
/// is critical) or any one frame is more than two refreshes late, a stall anyone would see.
///
/// The probe counts every frame on screen, so a hitch in the system's own part of a transition (a sheet's dimming
/// and presentation) counts too. On a device, `testTransitionsOnDevice` also reports the same windows through
/// `XCTOSSignpostMetric`; the simulator does not report hitch metrics, so it skips there.
///
/// Frame timing on a simulator depends on the Mac running it. These run on CI's dedicated runner; a local run on a
/// busy Mac can fail without the components being at fault.
@MainActor
final class MotionTests: XCTestCase {
    static let limitRatio = 5.0
    static let limitWorstMs = 33.4

    override func setUp() { continueAfterFailure = true }

    struct Result {
        let ratio: Double
        let worstMs: Double
        let summary: String
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
        guard let ratio = fields["ratio"].flatMap(Double.init), let worst = fields["worstMs"].flatMap(Double.init) else { return nil }
        return Result(ratio: ratio, worstMs: worst, summary: summary)
    }

    private func check(_ name: String, _ result: Result?, file: StaticString = #filePath, line: UInt = #line) {
        guard let result else { return XCTFail("\(name): the probe gave no result", file: file, line: line) }
        let note = XCTAttachment(string: result.summary)
        note.name = "probe-\(name)"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertLessThanOrEqual(result.ratio, Self.limitRatio, "\(name) hitches: \(result.summary)", file: file, line: line)
        XCTAssertLessThanOrEqual(result.worstMs, Self.limitWorstMs, "\(name) stalls a frame: \(result.summary)", file: file, line: line)
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

    func testAToastArrivesAndLeavesSmoothly() { check("toast", demo("toast", page: "toasts")) }
    func testAToastDismissedWhileArrivingTurnsAroundSmoothly() { check("toast-interrupt", demo("toast-interrupt", page: "toasts")) }
    func testAToastStackGrowsAndEmptiesSmoothly() { check("stack", demo("stack", page: "toasts")) }
    func testABannerFoldsAwayAndBackSmoothly() { check("banner", demo("banner", page: "banners")) }
    func testABannerHiddenWhileFoldingTurnsAroundSmoothly() { check("banner-interrupt", demo("banner-interrupt", page: "banners")) }
    func testASheetOpensAndClosesSmoothly() { check("sheet", demo("sheet", page: "sheet")) }
    func testAnEmptyStateArrivesSmoothly() { check("empty", demo("empty", page: "empty")) }

    /// Opens `page` with a probe window `delay` seconds after it appears, lasting `seconds`, for a gesture inside it.
    private func window(_ page: String, delay: Double, seconds: Double) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", "pearl", "-page", page, "-open", "0", "-probe", "1",
                               "-probeDelay", String(delay), "-probeSeconds", String(seconds)]
        app.launch()
        return app
    }

    func testAButtonPressesAndReleasesSmoothly() {
        let app = window("buttons", delay: 4, seconds: 6)
        defer { app.terminate() }
        let button = app.buttons["Save recipe"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        // Found before the window opens; pressed inside it.
        Thread.sleep(forTimeInterval: 4)
        button.press(forDuration: 0.6)
        check("press", read(app, after: 6))
    }

    func testAToastSwipedAwayLeavesSmoothly() {
        let app = window("toasts", delay: 6, seconds: 6)
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10))
        app.buttons["Save"].tap()
        let toast = app.staticTexts["Recipe saved"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        let start = toast.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        Thread.sleep(forTimeInterval: 4)
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -120)), withVelocity: .fast, thenHoldForDuration: 0)
        check("swipe", read(app, after: 7))
        XCTAssertFalse(toast.exists, "a toast swiped up goes")
    }

    /// On a device, each demo's window as `XCTOSSignpostMetric` hitch metrics, beside the probe's numbers.
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
