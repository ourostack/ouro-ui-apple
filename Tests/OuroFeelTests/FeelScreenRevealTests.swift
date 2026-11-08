import Foundation
import OuroFeelCore
import Testing

/// A film of shades, one sample a tick: 0 is the cover.
private func film(_ shades: [UInt8]) -> FeelScreenFilm {
    FeelScreenFilm(frames: shades.enumerated().map { i, v in
        FeelScreenFrame(t: Double(i) / 10, width: 4, height: 4, gray: Array(repeating: v, count: 16))
    })
}

private let cover = FeelScreenFrame(t: 0, width: 4, height: 4, gray: Array(repeating: 0, count: 16))

@Suite struct RevealHoldsTests {
    /// A relaunch film that starts after the cover went: the wrong page must not pass as the cover.
    @Test func aFilmStartingAfterTheCoverCannotPassTheJump() {
        let result = film([60, 60, 60, 60, 200, 200, 200]).revealHolds(cover: cover)
        #expect(!result.passed)
        #expect(result.findings.contains { $0.unchecked && $0.what.contains("no rest looked like the cover") }, "\(result.text)")
    }

    /// A screen before the open that is not the cover is not judged: the cover, then the page, holds.
    @Test func aDifferentScreenBeforeTheCoverIsNotJudged() {
        let result = film([200, 200, 0, 0, 0, 120, 120, 120]).revealHolds(cover: cover)
        #expect(result.passed, "\(result.text)")
    }

    /// The mark itself is the person's: a change that begins at `until` is not judged.
    @Test func aChangeBeginningAtTheMarkIsNotJudged() {
        #expect(film([0, 0, 120, 120, 120, 200, 200]).revealHolds(cover: cover, until: 5).passed)
        #expect(film([0, 0, 120, 120]).revealHolds(cover: cover, until: -3).findings.contains { $0.unchecked })
    }

    @Test func aCoverOfAnotherSizeCannotBeChecked() {
        let odd = FeelScreenFrame(t: 0, width: 5, height: 5, gray: Array(repeating: 0, count: 25))
        #expect(film([0, 0, 120, 120]).revealHolds(cover: odd).findings.contains { $0.unchecked && $0.what.contains("cover picture") })
    }

    @Test func theFirstPageAfterTheCoverHoldingPasses() {
        let result = film([0, 0, 0, 120, 120, 120, 120]).revealHolds(cover: cover)
        #expect(result.passed, "\(result.text)")
        #expect(result.check == "jump after landing")
    }

    /// A fade from the cover onto the page is the reveal, not a jump.
    @Test func aFadeFromTheCoverPasses() {
        #expect(film([0, 0, 40, 80, 120, 120, 120]).revealHolds(cover: cover).passed)
    }

    /// Gatefold build 20, relaunched on an iPad: another page showed, then his.
    @Test func anotherPageThenHisFails() {
        let result = film([0, 0, 0, 60, 60, 60, 60, 200, 200, 200]).revealHolds(cover: cover)
        #expect(!result.passed)
        #expect(result.detections.contains { $0.what.contains("was replaced") }, "\(result.text)")
    }

    @Test func aFlashAwayFromTheFirstPageFails() {
        let result = film([0, 0, 120, 120, 30, 120, 120]).revealHolds(cover: cover)
        #expect(result.detections.contains { $0.what.contains("flashed away") }, "\(result.text)")
    }

    /// The cover coming back over the page is a jump too.
    @Test func theCoverComingBackFails() {
        #expect(!film([0, 0, 120, 120, 0, 0, 120, 120]).revealHolds(cover: cover).passed)
    }

    /// Only up to the next scripted mark: what the person does after it is theirs.
    @Test func whatComesAfterTheMarkIsNotJudged() {
        #expect(film([0, 0, 120, 120, 120, 200, 200]).revealHolds(cover: cover, until: 5).passed)
    }

    @Test func neverRevealedOrStillChangingCannotBeChecked() {
        let covered = film([0, 0, 0, 0]).revealHolds(cover: cover)
        #expect(!covered.passed && covered.findings.contains { $0.unchecked && $0.what.contains("but the cover") })
        let moving = film([0, 0, 120, 120, 150]).revealHolds(cover: cover)
        #expect(moving.findings.contains { $0.unchecked && $0.what.contains("still changing") }, "\(moving.text)")
    }
}
