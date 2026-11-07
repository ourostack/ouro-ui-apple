import OuroFeel
import OuroFeelCore
import XCTest

/// Ouro Feel's motion genres on the gallery's own transitions: the kit dogfoods the tool that judges apps built on it.
@MainActor
final class FeelTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private static let stack = ["Recipe saved", "Added to Weeknights", "Recipe deleted"]

    /// Three toasts arrive 0.6 s apart, then the stack empties 3 s after the first. While they arrive and rest, the
    /// newest lands once and stays put (jump after landing), no toast's words show twice (double-draw), and it comes to
    /// rest within 1.5 s (settle). The older ones move once more by design, as each tucks behind the next, so their
    /// jumps are recorded, not judged.
    ///
    /// The demo and OuroHX's springs run on the app's own clock (`-clock 1`, ``OuroMotionClock``), which this test moves
    /// one 0.05 s tick at a time, sampling after each. So the film holds the same frames however busy the runner is
    /// (#33); a wall-clock film here thinned out on loaded CI runners and its verdicts moved with the load. The checks
    /// read one play: from the first toast's arrival to just before the stack empties.
    func testAToastStackArrivesWithoutJumpsGhostsOrALongSettle() throws {
        let (feel, play) = try filmOnePlay()
        // Recorded with the film, so its samples are attached for anyone reading a failure.
        let ghosts = feel.record(play.doubleDraws(of: Self.stack), name: "stack-double-draw", film: play)
        XCTAssertTrue(ghosts.passed, ghosts.text)
        feel.expect(play.jumps(of: Self.stack[2]))
        feel.expect(play.settles(Self.stack[2], within: 1.5))
        for older in Self.stack.dropLast() { feel.record(play.jumps(of: older), name: "stack-tuck-\(older)") }
    }

    /// Launches the demo on the app's clock and films one play: from the first toast's arrival to just before the
    /// stack empties.
    private func filmOnePlay() throws -> (OuroFeel, FeelFilm) {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", "pearl", "-page", "toasts", "-open", "0", "-demo", "stack", "-clock", "1"]
        app.launch()
        let feel = OuroFeel(app)
        // 3.6 s of the app's clock: still for half a second, the three arrivals, and their rest until the stack
        // empties at 3.5 s.
        let whole = feel.film(Self.stack, steps: 72, tick: 0.05, clock: "gallery.clock",
                              advance: FeelClock.darwinNotification("bot.ouro.hx.gallery.tick"))
        XCTAssertNil(whole.stalledAt, "the app stopped taking ticks")
        let first = try XCTUnwrap(whole.frames.first { $0.seen.contains { $0.label == Self.stack[0] || $0.key == Self.stack[0] } }?.t,
                                  "the first toast never arrived")
        // The demo empties the stack 3 s after the first toast; stop 0.1 s short of that.
        var play = whole
        play.frames = whole.frames.filter { $0.t >= first - 0.1 && $0.t <= first + 2.9 }
        return (feel, play)
    }
}
