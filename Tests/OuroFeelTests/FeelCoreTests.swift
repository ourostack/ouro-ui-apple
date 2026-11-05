import CoreGraphics
import Foundation
import OuroFeelCore
import Testing

private let phone = CGRect(x: 0, y: 0, width: 402, height: 874)

@Suite struct LayoutTests {
    @Test func aControlInsideTheWindowPasses() {
        let save = FeelElement(key: "save", type: "button", frame: CGRect(x: 20, y: 800, width: 120, height: 44))
        let result = FeelLayout.check([save], window: phone, pose: "portrait")
        #expect(result.passed)
        #expect(result.findings.isEmpty)
    }

    /// Gatefold build 19's Fine-Tune row in portrait: x 1115.5 in a 1032-point window (log-padJ18-portraitpanel.txt).
    @Test func aControlPastTheWindowEdgeFails() {
        let pad = CGRect(x: 0, y: 0, width: 1032, height: 1376)
        let row = FeelElement(key: "appearance.pageNumbers", type: "switch", frame: CGRect(x: 1115.5, y: 1134, width: 61, height: 28),
                              scroll: CGRect(x: 880, y: 818, width: 560, height: 542))
        let result = FeelLayout.check([row], window: pad, pose: "portrait after landscape")
        #expect(!result.passed)
        #expect(result.findings.count == 1)
        #expect(result.findings[0].what.contains("appearance.pageNumbers"))
        #expect(result.findings[0].what.contains("portrait after landscape"))
        #expect(result.measures["outside"] == 1)
    }

    @Test func aControlScrolledOutOfViewInsideAVisibleScrollViewPasses() {
        let list = CGRect(x: 0, y: 100, width: 402, height: 700)
        let below = FeelElement(key: "row 40", type: "button", frame: CGRect(x: 0, y: 2400, width: 402, height: 44), scroll: list)
        #expect(FeelLayout.check([below], window: phone, pose: "portrait").passed)
    }

    @Test func aScrollViewThatItselfOverhangsTheWindowDoesNotExcuseItsControls() {
        let panel = CGRect(x: 300, y: 100, width: 400, height: 500)
        let toggle = FeelElement(key: "t", type: "switch", frame: CGRect(x: 420, y: 200, width: 51, height: 31), scroll: panel)
        #expect(!FeelLayout.check([toggle], window: phone, pose: "portrait").passed)
    }

    @Test func emptyFramesAreIgnoredAndHalfAPointIsTolerated() {
        let hidden = FeelElement(key: "h", type: "button", frame: .zero)
        let edge = FeelElement(key: "e", type: "button", frame: CGRect(x: -0.4, y: 0, width: 44, height: 44))
        #expect(FeelLayout.check([hidden, edge], window: phone, pose: "portrait").passed)
    }
}

@Suite struct TapTests {
    @Test func everyTapLandingPasses() {
        let trials = (0..<10).map { _ in FeelTapTrial(spot: .centre, landed: true) }
        let result = FeelTaps.evaluate(trials)
        #expect(result.passed)
        #expect(result.measures["rate"] == 1)
    }

    @Test func oneMissFailsAndNamesTheSpot() {
        var trials = (0..<9).map { _ in FeelTapTrial(spot: .centre, landed: true) }
        trials.append(FeelTapTrial(spot: .trailingEdge, landed: false))
        let result = FeelTaps.evaluate(trials)
        #expect(!result.passed)
        #expect(result.measures["rate"] == 0.9)
        #expect(result.findings.contains { $0.what.contains("trailing edge") && $0.what.contains("0 of 1") })
    }

    @Test func aTapOnAGapThatChangesTheControlIsAFinding() {
        let trials = [FeelTapTrial(spot: .centre, landed: true), FeelTapTrial(spot: .gap, landed: true, expected: false)]
        let result = FeelTaps.evaluate(trials)
        #expect(!result.passed)
        #expect(result.findings.contains { $0.what.contains("gap") })
    }

    @Test func aMissingOSBaselineAlsoMissedIsMarkedAsInference() {
        let trials = [FeelTapTrial(spot: .centre, landed: true), FeelTapTrial(spot: .centre, landed: false)]
        let result = FeelTaps.evaluate(trials, baseline: 0.77)
        #expect(!result.passed)
        #expect(result.measures["baseline"] == 0.77)
        #expect(result.findings.contains { $0.inferred && $0.what.contains("OS control") })
    }
}

private func film(_ frames: [(Double, [FeelSeen])]) -> FeelFilm {
    FeelFilm(window: phone, frames: frames.map { FeelFrame(t: $0.0, seen: $0.1) })
}

private func card(_ y: Double, key: String = "card", label: String = "Card") -> FeelSeen {
    FeelSeen(key: key, label: label, frame: CGRect(x: 20, y: y, width: 200, height: 100))
}

@Suite struct MotionTests {
    @Test func settleTimeIsWhenTheElementLastMoved() {
        let f = film([(0, [card(900)]), (0.1, [card(600)]), (0.2, [card(420)]), (0.3, [card(400)]), (0.4, [card(400)]), (0.8, [card(400)])])
        #expect(f.settleTime(of: "card") == 0.3)
    }

    @Test func anElementThatNeverAppearsHasNoSettleTime() {
        #expect(film([(0, [])]).settleTime(of: "card") == nil)
    }

    @Test func aMoveAfterRestIsAJump() {
        let f = film([(0, [card(400)]), (0.2, [card(400)]), (0.5, [card(400)]), (0.6, [card(440)]), (0.7, [card(440)])])
        let result = f.jumps(of: "card")
        #expect(!result.passed)
        #expect(result.measures["jumps"] == 1)
        #expect(result.findings[0].what.contains("40"))
    }

    @Test func movingWhileStillAnimatingIsNotAJump() {
        let f = film([(0, [card(900)]), (0.05, [card(700)]), (0.1, [card(500)]), (0.15, [card(400)]), (0.6, [card(400)])])
        #expect(f.jumps(of: "card").passed)
    }

    @Test func theSameContentVisibleTwiceAtOnceIsADoubleDraw() {
        let f = film([(0, [card(100, key: "a", label: "Pancakes")]),
                      (0.1, [card(100, key: "a", label: "Pancakes"), card(500, key: "b", label: "Pancakes")]),
                      (0.2, [card(500, key: "b", label: "Pancakes")])])
        let result = f.doubleDraws(of: ["Pancakes"])
        #expect(!result.passed)
        #expect(result.findings.count == 1)
    }

    @Test func aCopyOffScreenIsNotADoubleDraw() {
        let f = film([(0, [card(100, label: "Pancakes"), card(2000, key: "b", label: "Pancakes")])])
        #expect(f.doubleDraws(of: ["Pancakes"]).passed)
    }

    @Test func twoChromeStatesOnScreenTogetherLinger() {
        let a = card(10, key: "bar.full"), b = card(10, key: "bar.compact")
        let f = film([(0, [a]), (0.1, [a, b]), (0.3, [a, b]), (0.5, [b])])
        let result = f.chrome(from: "bar.full", to: "bar.compact", grace: 0.1)
        #expect(!result.passed)
        #expect(result.findings.contains { $0.what.contains("both") })
        #expect(result.measures["both"] == 0.4)
    }

    @Test func noChromeStateOnScreenIsLate() {
        let a = card(10, key: "bar.full"), b = card(10, key: "bar.compact")
        let f = film([(0, [a]), (0.1, []), (0.4, []), (0.5, [b])])
        let result = f.chrome(from: "bar.full", to: "bar.compact", grace: 0.1)
        #expect(!result.passed)
        #expect(result.findings.contains { $0.what.contains("neither") })
    }

    @Test func aCleanHandOverPasses() {
        let a = card(10, key: "bar.full"), b = card(10, key: "bar.compact")
        #expect(film([(0, [a]), (0.1, [b]), (0.5, [b])]).chrome(from: "bar.full", to: "bar.compact").passed)
    }

    @Test func aFilmRoundTripsThroughJSON() throws {
        let f = film([(0, [card(1)])])
        let back = try JSONDecoder().decode(FeelFilm.self, from: JSONEncoder().encode(f))
        #expect(back == f)
    }
}

@Suite struct HitchTests {
    @Test func evenFramesHaveNoHitches() {
        let stamps = (0...120).map { Double($0) / 120 }
        let h = FeelHitches.analyze(timestamps: stamps, refresh: 1.0 / 120)
        #expect(h.count == 0)
        #expect(h.ratio == 0)
    }

    @Test func aLateFrameCountsItsLatenessAsHitchTime() {
        var stamps = (0...60).map { Double($0) / 60 }
        stamps = stamps.filter { $0 < 0.5 } + stamps.filter { $0 >= 0.54 }
        let h = FeelHitches.analyze(timestamps: stamps, refresh: 1.0 / 60)
        #expect(h.count == 1)
        #expect(h.worstFrames > 1.9 && h.worstFrames < 3.1)
        #expect(h.ratio > 30)
        let result = h.result(limit: 5)
        #expect(!result.passed)
    }
}

@Suite struct PlaceTests {
    @Test func theSameTextHashesTheSameAndNeverStoresIt() {
        let a = FeelPlace.fingerprint("It is a truth universally acknowledged")
        #expect(a == FeelPlace.fingerprint("It is a truth universally acknowledged"))
        #expect(a != FeelPlace.fingerprint("It is a truth universally acknowledged,"))
        #expect(a.count == 16)
        #expect(!a.contains("truth"))
    }

    @Test func aChangedPlaceFailsAndNamesTheStep() {
        let result = FeelPlace.compare(start: FeelPlace.fingerprint("a"), after: ["relaunch": FeelPlace.fingerprint("a"),
                                                                           "rotate": FeelPlace.fingerprint("b")])
        #expect(!result.passed)
        #expect(result.findings.count == 1)
        #expect(result.findings[0].what.contains("rotate"))
        #expect(!result.text.contains("\"b\""))
    }

    @Test func anEmptyReadingIsNeverAMatch() {
        let empty = FeelPlace.fingerprint("")
        #expect(!FeelPlace.compare(start: empty, after: ["relaunch": empty]).passed)
    }
}

@Suite struct ReportTests {
    @Test func aReportSaysWhereAndWhichClockAndMarksInference() {
        let env = FeelEnvironment(target: .simulator, model: "iPhone 17 Pro", os: "iOS 27.2", start: .warm, clock: "test-runner wall clock")
        var result = FeelResult(check: "taps", passed: false, summary: "9 of 10 landed",
                                findings: [FeelFinding(what: "OS control missed too", inferred: true)])
        result.environment = env
        let text = result.text
        #expect(text.contains("FAIL taps"))
        #expect(text.contains("simulator"))
        #expect(text.contains("warm"))
        #expect(text.contains("test-runner wall clock"))
        #expect(text.contains("(inference)"))
    }

    @Test func theStartComesFromTheRunner() {
        #expect(FeelEnvironment.Start(environment: ["OURO_FEEL_START": "cold"]) == .cold)
        #expect(FeelEnvironment.Start(environment: [:]) == .unlabelled)
    }
}
