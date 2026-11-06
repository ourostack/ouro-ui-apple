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
    /// The demo plays twice (`-repeat 2`) so the film holds a whole play even when launch runs long, and the checks
    /// read one play: from the first toast's arrival to just before the stack empties. A film over both plays read the
    /// exit, and the second arrival at a new place, as a jump after landing.
    ///
    /// A film sampled too sparsely to judge ("could not check", seen on a loaded CI runner) is not a verdict, so it is
    /// filmed once more in a fresh launch.
    func testAToastStackArrivesWithoutJumpsGhostsOrALongSettle() throws {
        var (feel, play) = try filmOnePlay()
        if feel.record(play.doubleDraws(of: Self.stack), name: "stack-double-draw-first", film: play).text.contains("could not check") {
            (feel, play) = try filmOnePlay()
        }
        // Recorded with the film, so its samples are attached for anyone reading a failure.
        let ghosts = feel.record(play.doubleDraws(of: Self.stack), name: "stack-double-draw", film: play)
        XCTAssertTrue(ghosts.passed, ghosts.text)
        feel.expect(play.jumps(of: Self.stack[2]))
        feel.expect(play.settles(Self.stack[2], within: 1.5))
        for older in Self.stack.dropLast() { feel.record(play.jumps(of: older), name: "stack-tuck-\(older)") }
    }

    /// Launches the demo and films one play: from the first toast's arrival to just before the stack empties.
    private func filmOnePlay() throws -> (OuroFeel, FeelFilm) {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", "pearl", "-page", "toasts", "-open", "0", "-demo", "stack", "-repeat", "2"]
        app.launch()
        let feel = OuroFeel(app)
        let whole = feel.film(Self.stack, for: 13)
        let first = try XCTUnwrap(whole.frames.first { $0.seen.contains { $0.label == Self.stack[0] || $0.key == Self.stack[0] } }?.t,
                                  "the first toast never arrived")
        // The demo empties the stack 3 s after the first toast; stop 0.1 s short of that.
        var play = whole
        play.frames = whole.frames.filter { $0.t >= first - 0.1 && $0.t <= first + 2.9 }
        return (feel, play)
    }
}
