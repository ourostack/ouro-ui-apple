import OuroFeel
import XCTest

/// The button's press, filmed frame by frame, for a side-by-side with web's: pressing shrinks it to core's press scale
/// (`pressIn`), and letting go springs it back (`pressOut`).
///
/// XCUITest cannot film a real press: `tap()` presses and lifts at once, and `press(forDuration:)` takes no
/// screenshots until it lets go. So the gallery holds the press itself (`-demo press`, OuroHX's `ouroHeldPress`): it
/// presses the primary button at tick 1 of its clock (`-clock 1`) and lets go at tick 9, and this test moves that clock
/// one 0.05 s tick at a time, so each frame is the button exactly 0, 50, 100 ms and so on after the press or the
/// release, however busy the runner is. Each frame is attached (`button-<theme>-<press|release>-<ms>ms`, and `rest`
/// before the press).
@MainActor
final class ButtonFramesTests: XCTestCase {
    static let tick = "bot.ouro.hx.gallery.tick"
    /// The gallery presses at tick 1 and lets go at tick 9.
    static let pressAt = 1, releaseAt = 9
    /// 750 ms after the release: past `pressOut`'s spring (0.35 s, a little bounce).
    static let last = 24

    override func setUp() { continueAfterFailure = true }

    func testThePressShrinksAndSpringsBackInPearl() throws { try film(theme: "pearl") }

    func testThePressShrinksAndSpringsBackInCookbook() throws { try film(theme: "cookbook") }

    private func film(theme: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", theme, "-page", "buttons", "-open", "0", "-scheme", "light", "-demo", "press", "-clock", "1"]
        app.launch()
        defer { app.terminate() }
        let clock = app.staticTexts["gallery.clock"]
        XCTAssertTrue(clock.waitForExistence(timeout: 30), "the gallery's clock never showed")
        let button = app.buttons["button.primary"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no primary button")

        let start = try XCTUnwrap(Int(clock.label), "the clock's count is \(clock.label)")
        XCTAssertEqual(start, 0, "the clock had moved before the test")
        let advance = FeelClock.darwinNotification(Self.tick)
        var pngs: [Data] = []
        for step in 0...Self.last {
            if step > 0 {
                advance()
                let ticked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", String(step)), object: clock)
                // Feel's own films wait 30 s for a tick (FeelScreen.film's stall): a loaded iPad runner took over 10.
                XCTAssertEqual(XCTWaiter().wait(for: [ticked], timeout: 30), .completed, "the app stopped taking ticks at \(step)")
            }
            let shot = button.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "button-\(theme)-\(Self.name(step))"
            attachment.lifetime = .keepAlways
            add(attachment)
            pngs.append(shot.pngRepresentation)
        }
        let rest = pngs[0], held = pngs[Self.releaseAt - 1]
        // Pressed, the button is drawn smaller and shaded, and still moving 50 ms in; let go, it moves back.
        XCTAssertNotEqual(held, rest, "\(theme): the held button looked as it did at rest")
        XCTAssertNotEqual(pngs[Self.pressAt + 1], held, "\(theme): the press had already landed 50 ms in; it should spring")
        XCTAssertNotEqual(pngs[Self.releaseAt + 1], pngs[Self.last], "\(theme): the release had already landed 50 ms in")
        XCTAssertNotEqual(pngs[Self.last], held, "\(theme): the button stayed pressed after it was let go")
    }

    /// `rest`, `press-000ms` from the press, `release-000ms` from the release.
    private static func name(_ step: Int) -> String {
        if step < pressAt { return "rest" }
        let (phase, from) = step < releaseAt ? ("press", pressAt) : ("release", releaseAt)
        return "\(phase)-\(String(format: "%03d", (step - from) * 50))ms"
    }
}
