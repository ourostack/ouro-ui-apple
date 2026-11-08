import CoreGraphics
import Foundation
import OuroFeelCore
import Testing

/// A film on the app's display has one sample per frame, so a gap between samples is the app's main thread stalled
/// (ouro-ui-apple#98: Gatefold's Appearance panel held 34 refreshes at its first frame; no check named it).
@Suite struct FilmHitchTests {
    private let window = CGRect(x: 0, y: 0, width: 466, height: 678)

    /// Samples every refresh from 0 to `end`, none strictly inside `stall`.
    private func film(end: Double = 2, stall: ClosedRange<Double>? = nil, timedBy: String? = FeelRecording.timedBy) -> FeelFilm {
        let stamps = (0...Int(end * 60)).map { Double($0) / 60 }.filter { t in stall.map { t <= $0.lowerBound || t >= $0.upperBound } ?? true }
        return FeelFilm(window: window, frames: stamps.map { FeelFrame(t: $0, seen: []) }, timedBy: timedBy)
    }

    @Test func aFilmAtTheDisplaysPacePasses() {
        let result = film().hitches(refresh: 1.0 / 60)
        #expect(result.passed)
        #expect(result.check == FeelGenre.hitches.rawValue)
    }

    @Test func aStallIsNamedWithItsLengthAndWhereItFell() {
        // 1.133 s to 1.7 s with no sample (34 refreshes): the Duo's Appearance panel in gatefold run 42468852374.
        let result = film(stall: (68.0 / 60)...(102.0 / 60)).hitches(refresh: 1.0 / 60)
        #expect(!result.passed)
        let said = result.findings.map(\.what).joined(separator: " | ")
        #expect(said.contains("stalled 0.567 s (34 refreshes)"), "\(said)")
        #expect(said.contains("at 1.133 s"), "\(said)")
        #expect((result.measures["worstFrames"] ?? 0) > 30, "\(result.measures)")
    }

    @Test func aFilmOnTheRunnersClockCannotBeChecked() {
        // XCUITest's snapshots are not one per frame: their gaps say nothing about the app's frames.
        let result = film(timedBy: nil).hitches(refresh: 1.0 / 60)
        #expect(!result.passed)
        #expect(result.findings.contains { $0.unchecked })
    }
}
