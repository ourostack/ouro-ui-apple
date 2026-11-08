import Foundation
import OuroFeelCore
import Testing

/// A 4x4 picture of one shade.
private func shade(_ v: UInt8, at i: Int, size: Int = 4) -> FeelScreenFrame {
    FeelScreenFrame(t: Double(i) / 10, width: size, height: size, gray: Array(repeating: v, count: size * size))
}

/// A film of shades, one sample a tick.
private func film(_ shades: [UInt8]) -> FeelScreenFilm {
    FeelScreenFilm(frames: shades.enumerated().map { shade($1, at: $0) })
}

@Suite struct ScreenFlickerTests {
    @Test func oneChangePasses() {
        let result = film([10, 10, 10, 200, 200, 200, 200]).flickers()
        #expect(result.passed, "\(result.text)")
        #expect(result.check == "flicker")
    }

    /// Gatefold build 20 on a folded Duo: the page showed, a slip took over, and the first picture came back, all in
    /// one reading action, where no label changed.
    @Test func comingBackToAStateItLeftFails() {
        let result = film([10, 10, 200, 200, 10, 10, 10]).flickers()
        #expect(!result.passed)
        #expect(result.detections.contains { $0.what.contains("came back to it 3 samples later") }, "\(result.text)")
    }

    @Test func comingBackAfterTheWindowPasses() {
        let result = film([10, 10, 200, 200, 200, 200, 10, 10]).flickers(within: 3, states: 2)
        #expect(result.passed, "\(result.text)")
    }

    @Test func moreStatesThanTheActionDeclaresFail() {
        let shades: [UInt8] = [10, 10, 100, 100, 200, 200, 200]
        #expect(!film(shades).flickers().passed)
        #expect(film(shades).flickers(states: 3).passed, "a veil, then the page, declared")
    }

    /// Frames on their way (a fade) belong to no state, so a cross-fade is one change.
    @Test func aFadeBetweenTwoRestsIsOneChange() {
        let result = film([10, 10, 60, 110, 160, 200, 200, 200]).flickers()
        #expect(result.passed, "\(result.text)")
    }

    /// Tiny noise (a caret, dithering) under the thresholds is the same rest.
    @Test func noiseUnderTheThresholdIsOneState() {
        #expect(film([10, 10, 10, 10, 10, 10]).states().count == 1)
        var f = film([10, 10, 10, 10])
        f.frames[2].gray[0] = 11
        #expect(f.states().count == 1)
    }

    /// One tick of something else is 100 ms on a 0.1 s clock: plain to see, though too short to be a rest.
    @Test func aOneSampleFlashFails() {
        let result = film([10, 10, 200, 10, 10]).flickers()
        #expect(!result.passed)
        #expect(result.detections.contains { $0.what.contains("flashed away") }, "\(result.text)")
        #expect(!film([10, 10, 200, 10, 200, 200]).flickers().passed, "A, B, A for one tick, then B")
    }

    /// Gatefold build 20 spun through pages a tick each before it settled back.
    @Test func spinningThroughPagesFails() {
        #expect(!film([10, 10, 50, 90, 130, 10, 10]).flickers().passed)
        // Through pages that are neither the first nor the last, on the way to a new one: not a fade.
        let pages: [[UInt8]] = [[10, 10, 10, 10], [10, 10, 10, 10], [200, 0, 200, 0], [0, 200, 0, 200], [10, 200, 10, 200], [10, 200, 10, 200]]
        let spun = FeelScreenFilm(frames: pages.enumerated().map { i, p in
            FeelScreenFrame(t: Double(i) / 10, width: 4, height: 4, gray: Array(repeating: p, count: 4).flatMap { $0 })
        })
        #expect(spun.flickers().detections.contains { $0.what.contains("neither") }, "\(spun.flickers().text)")
    }

    /// A slow drift never chains into one rest: each sample is judged against the rest's first.
    @Test func aSlowDriftAwayAndBackIsNotOneRest() {
        let drift: [UInt8] = [10, 10, 10, 10, 10, 10] + (1...10).map { 10 + UInt8($0) / 2 * 1 } + [200, 200, 10, 10]
        #expect(!film(drift).flickers().passed)
    }

    @Test func aSkippedTickCannotBeChecked() {
        var f = film([10, 10, 10, 200, 200, 200])
        f.frames[4].t = 1.0
        f.frames[5].t = 1.1
        #expect(f.flickers().findings.contains { $0.unchecked && $0.what.contains("twice the usual") }, "\(f.flickers().text)")
    }

    @Test func stillChangingAtTheEndCannotBeChecked() {
        let result = film([10, 10, 200, 200, 90]).flickers()
        #expect(!result.passed)
        #expect(result.findings.contains { $0.unchecked && $0.what.contains("still changing") })
    }

    @Test func aStalledOrMixedFilmCannotBeChecked() {
        var stalled = film([10, 10, 10])
        stalled.stalledAt = 0.2
        #expect(stalled.flickers().findings.contains { $0.unchecked && $0.what.contains("stopped") })
        var mixed = film([10, 10, 10])
        mixed.frames[1] = shade(10, at: 1, size: 5)
        #expect(mixed.flickers().findings.contains { $0.unchecked && $0.what.contains("one size") })
        #expect(!mixed.flickers().passed)
    }
}
