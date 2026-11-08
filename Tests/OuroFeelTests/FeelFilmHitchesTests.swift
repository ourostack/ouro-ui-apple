import CoreGraphics
import Foundation
import OuroFeelCore
import Testing

/// A film on the app's display has one sample per frame, so a gap between samples is the app's main thread stalled
/// (ouro-ui-apple#98: Gatefold's Appearance panel held 34 refreshes at its first frame; no check named it).
@Suite struct FilmHitchTests {
    private let window = CGRect(x: 0, y: 0, width: 466, height: 678)

    /// Samples every refresh at `hz` from 0 to `end`, none strictly inside any of `stalls`.
    private func film(hz: Double = 60, end: Double = 2, stalls: [ClosedRange<Double>] = [], stalledAt: Double? = nil,
                      timedBy: String? = FeelRecording.timedBy) -> FeelFilm {
        let stamps = (0...Int(end * hz)).map { Double($0) / hz }.filter { t in stalls.allSatisfy { t <= $0.lowerBound || t >= $0.upperBound } }
        return FeelFilm(window: window, frames: stamps.map { FeelFrame(t: $0, seen: []) }, stalledAt: stalledAt, timedBy: timedBy)
    }

    @Test func aFilmAtTheDisplaysPacePasses() {
        let result = film().hitches()
        #expect(result.passed)
        #expect(result.check == FeelGenre.hitches.rawValue)
        #expect(film(hz: 120).hitches().passed, "a 120 Hz film at its own pace")
    }

    @Test func aStallIsNamedOnceWithItsLengthAndWhereItFell() {
        // 1.133 s to 1.7 s with no sample (34 refreshes): the Duo's Appearance panel in gatefold run 42468852374.
        let result = film(stalls: [(68.0 / 60)...(102.0 / 60)]).hitches()
        #expect(!result.passed)
        let said = result.findings.map(\.what)
        #expect(said.first == "the app stalled 0.567 s at 1.133 s, 33 refreshes late (limit 2)", "\(said)")
        #expect(said.filter { $0.contains("refreshes") }.count == 1, "one stall, one finding: \(said)")
    }

    @Test func theLongerOfTwoStallsIsNamed() {
        let result = film(stalls: [(30.0 / 60)...(40.0 / 60), (68.0 / 60)...(102.0 / 60)]).hitches()
        #expect(result.findings.first?.what.hasPrefix("the app stalled 0.567 s at 1.133 s") == true, "\(result.findings.map(\.what))")
    }

    @Test func aRefreshTheFilmDidNotRunAtCannotBeChecked() {
        // A 60 Hz film read as 120 Hz would count every frame late.
        let result = film().hitches(refresh: 1.0 / 120)
        #expect(!result.passed)
        #expect(result.findings.allSatisfy { $0.unchecked }, "\(result.findings.map(\.what))")
    }

    @Test func aFilmOnTheRunnersClockCannotBeChecked() {
        // XCUITest's snapshots are not one per frame: their gaps say nothing about the app's frames.
        let result = film(timedBy: nil).hitches()
        #expect(!result.passed)
        #expect(result.findings.contains { $0.unchecked })
    }

    @Test func aCutOffFilmNamesItsStallFirst() {
        let result = film(stalls: [(68.0 / 60)...(102.0 / 60)], stalledAt: 2).hitches()
        #expect(!result.passed)
        #expect(result.findings.first?.what.hasPrefix("the app stalled") == true)
        #expect(result.findings.last?.unchecked == true)
    }

    @Test func anEmptyFilmCannotBeChecked() {
        let result = FeelFilm(window: window, frames: [], timedBy: FeelRecording.timedBy).hitches()
        #expect(!result.passed)
        #expect(result.findings.contains { $0.unchecked })
    }
}
