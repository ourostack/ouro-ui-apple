import Foundation
import OuroFeelCore
import Testing

/// A film of shades, one sample a tick: 0 is the cover.
private func film(_ shades: [UInt8]) -> FeelScreenFilm {
    FeelScreenFilm(frames: shades.enumerated().map { i, v in
        FeelScreenFrame(t: Double(i) / 10, width: 4, height: 4, gray: Array(repeating: v, count: 16))
    })
}

@Suite struct RevealHoldsTests {
    @Test func theFirstPageAfterTheCoverHoldingPasses() {
        let result = film([0, 0, 0, 120, 120, 120, 120]).revealHolds()
        #expect(result.passed, "\(result.text)")
        #expect(result.check == "jump after landing")
    }

    /// A fade from the cover onto the page is the reveal, not a jump.
    @Test func aFadeFromTheCoverPasses() {
        #expect(film([0, 0, 40, 80, 120, 120, 120]).revealHolds().passed)
    }

    /// Gatefold build 20, relaunched on an iPad: another page showed, then his.
    @Test func anotherPageThenHisFails() {
        let result = film([0, 0, 0, 60, 60, 60, 60, 200, 200, 200]).revealHolds()
        #expect(!result.passed)
        #expect(result.detections.contains { $0.what.contains("was replaced") }, "\(result.text)")
    }

    @Test func aFlashAwayFromTheFirstPageFails() {
        let result = film([0, 0, 120, 120, 30, 120, 120]).revealHolds()
        #expect(result.detections.contains { $0.what.contains("flashed away") }, "\(result.text)")
    }

    /// The cover coming back over the page is a jump too.
    @Test func theCoverComingBackFails() {
        #expect(!film([0, 0, 120, 120, 0, 0, 120, 120]).revealHolds().passed)
    }

    /// Only up to the next scripted mark: what the person does after it is theirs.
    @Test func whatComesAfterTheMarkIsNotJudged() {
        #expect(film([0, 0, 120, 120, 120, 200, 200]).revealHolds(until: 4).passed)
    }

    @Test func neverRevealedOrStillChangingCannotBeChecked() {
        let cover = film([0, 0, 0, 0]).revealHolds()
        #expect(!cover.passed && cover.findings.contains { $0.unchecked && $0.what.contains("but the cover") })
        let moving = film([0, 0, 120, 120, 150]).revealHolds()
        #expect(moving.findings.contains { $0.unchecked && $0.what.contains("still changing") }, "\(moving.text)")
    }
}
