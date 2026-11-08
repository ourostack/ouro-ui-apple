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
    @Test func spinningThroughPagesAndBackFails() {
        #expect(!film([10, 10, 50, 90, 130, 10, 10]).flickers().passed)
    }

    /// A slide, a scroll and a slow ease of real (textured) content are one change, though each frame on the way is as
    /// far from both rests as they are from each other.
    @Test func texturedSlidesScrollsAndEasesPass() {
        let slide = textured(offsets: [0, 0, 0, 40, 80, 120, 160, 160, 160], pageAt: { $0 < 160 ? 0 : 1 })
        #expect(slide.flickers().passed, "\(slide.flickers().text)")
        let scroll = textured(offsets: [0, 0, 0, 6, 12, 18, 18, 18])
        #expect(scroll.flickers().passed, "\(scroll.flickers().text)")
        let ease = textured(offsets: [0, 0, 0, 30, 50, 62, 70, 75, 78, 79, 80, 80, 80, 80])
        #expect(ease.flickers().passed, "\(ease.flickers().text)")
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

/// A 160x40 film of a textured strip scrolled by each offset (pixels): stripes of varied shades, as text lines are.
private func textured(offsets: [Int], pageAt: (Int) -> Int = { _ in 0 }) -> FeelScreenFilm {
    let w = 160, h = 40
    func shadeAt(_ x: Int, _ y: Int, page: Int) -> UInt8 {
        let v = (x * 37 + y * 11 + page * 101) % 7 == 0 ? 30 : ((x / 3 + y / 2 + page * 5) % 5) * 40 + 40
        return UInt8(min(255, v))
    }
    return FeelScreenFilm(frames: offsets.enumerated().map { i, off in
        var gray = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w {
            let sx = x + off
            gray[y * w + x] = shadeAt(sx % 320, y, page: pageAt(off) == 0 ? (sx < 160 ? 0 : 1) : (sx < 320 ? 1 : 0))
        } }
        return FeelScreenFrame(t: Double(i) / 10, width: w, height: h, gray: gray)
    })
}
