import OuroFeel
import XCTest

/// The checkbox's motion, filmed frame by frame after a real tap, as proof that it moves as web's does: the fill
/// cross-fades over core's `fast` (150 ms), then the tick draws along its path over `draw` (240 ms, ease out); unchecking
/// takes the tick back over `fast` at once.
///
/// The gallery runs OuroHX's motion on its own clock (`-clock 1`, ``OuroMotionClock``), which this test moves one
/// 0.05 s tick at a time, so each frame is the box at exactly 0, 50, 100 ms and so on after the tap, however busy the
/// runner is. Each frame is attached (`checkbox-<theme>-<check|uncheck>-<ms>ms`) for a side-by-side with web's.
@MainActor
final class CheckboxFramesTests: XCTestCase {
    static let tick = "bot.ouro.hx.gallery.tick"
    /// 0 to 400 ms after the tap, every 50 ms: past the fill (150 ms) and the tick's draw (150 + 240 ms).
    static let frames = 8

    override func setUp() { continueAfterFailure = true }

    func testTheTickDrawsOnceTheBoxHasFilledInPearl() throws { try film(theme: "pearl") }

    func testTheTickDrawsOnceTheBoxHasFilledInCookbook() throws { try film(theme: "cookbook") }

    private func film(theme: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", theme, "-page", "choices", "-open", "0", "-scheme", "light", "-demo", "check", "-clock", "1"]
        app.launch()
        defer { app.terminate() }
        let clock = app.staticTexts["gallery.clock"]
        XCTAssertTrue(clock.waitForExistence(timeout: 30), "the gallery's clock never showed")
        let box = app.descendants(matching: .toggle)["Orzo"]
        XCTAssertTrue(box.waitForExistence(timeout: 10), "no Orzo checkbox")
        XCTAssertEqual(box.value as? String, "Not checked")

        box.tap()
        XCTAssertEqual(box.value as? String, "Checked", "the tap did not check the box")
        let checking = try frames(of: box, clock: clock, named: "checkbox-\(theme)-check")
        // The fill comes in before the tick: the first frame differs from the last, and the tick is still drawing at
        // 150 ms (its draw starts then), so that frame differs from the one at rest.
        XCTAssertNotEqual(checking.first, checking.last, "\(theme): the box did not change after the tap")
        XCTAssertNotEqual(checking[3], checking.last, "\(theme): the tick was already whole at 150 ms; it should draw after the fill")

        box.tap()
        XCTAssertEqual(box.value as? String, "Not checked", "the second tap did not uncheck the box")
        let unchecking = try frames(of: box, clock: clock, named: "checkbox-\(theme)-uncheck")
        XCTAssertNotEqual(unchecking.first, unchecking.last, "\(theme): the box did not change after the second tap")
        // Unchecking is over by `fast`: the frames from 200 ms on are at rest.
        XCTAssertEqual(unchecking[4], unchecking.last, "\(theme): unchecking was still moving at 200 ms")
    }

    /// The box at 0, 50, 100 ms and so on after the tap, each attached; returns their PNGs.
    private func frames(of box: XCUIElement, clock: XCUIElement, named name: String) throws -> [Data] {
        let start = try XCTUnwrap(Int(clock.label), "the clock's count is \(clock.label)")
        let advance = FeelClock.darwinNotification(Self.tick)
        var pngs: [Data] = []
        for step in 0...Self.frames {
            if step > 0 {
                advance()
                let ticked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", String(start + step)), object: clock)
                // Feel's own films wait 30 s for a tick (FeelScreen.film's stall): a loaded iPad runner took over 10.
                XCTAssertEqual(XCTWaiter().wait(for: [ticked], timeout: 30), .completed, "the app stopped taking ticks at \(step)")
            }
            let shot = box.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "\(name)-\(String(format: "%03d", step * 50))ms"
            attachment.lifetime = .keepAlways
            add(attachment)
            pngs.append(shot.pngRepresentation)
        }
        return pngs
    }
}
