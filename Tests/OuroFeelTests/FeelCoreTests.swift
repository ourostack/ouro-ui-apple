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
    /// A film on the app's own clock that the app stopped answering ends where the clock stalled; every motion check on
    /// it says it could not be checked, never passes on frames it never saw (a jump due later was not filmed).
    @Test func aStalledClockCannotPass() {
        var f = film([(0, [card(200), card(100, key: "bar.full", label: "Kitchen")]),
                      (0.1, [card(200), card(100, key: "bar.full", label: "Kitchen")]),
                      (0.2, [card(200), card(100, key: "bar.full", label: "Kitchen")])])
        f.stalledAt = 0.2
        let results = [f.jumps(of: "card"), f.settles("card", within: 1), f.doubleDraws(of: ["Card"]),
                       f.snaps(of: "card"), f.chrome(from: "bar.full", to: "bar.compact")]
        for r in results {
            #expect(!r.passed, "\(r.check)")
            #expect(r.findings.contains { $0.unchecked && $0.what.contains("stopped at 0.200 s") }, "\(r.check): \(r.findings)")
        }
        let decoded = try? JSONDecoder().decode(FeelFilm.self, from: f.json)
        #expect(decoded?.stalledAt == 0.2)
        let old = try? JSONDecoder().decode(FeelFilm.self, from: Data(#"{"window":[[0,0],[402,874]],"frames":[]}"#.utf8))
        #expect(old != nil && old?.stalledAt == nil)
    }

    @Test func aFilmSaysWhichClockTimedIt() {
        var f = film([(0, [card(200)]), (0.1, [card(200)]), (0.2, [card(200)]), (0.3, [card(200)])])
        let wall = [f.jumps(of: "card"), f.settles("card", within: 1)]
        #expect(wall.allSatisfy { $0.environment == nil }, "a wall-clock film leaves the clock to the runner's report")
        f.timedBy = "the app's own clock (motion.clock, 0.1 s a tick)"
        let results = [f.jumps(of: "card"), f.settles("card", within: 1), f.doubleDraws(of: ["Card"]),
                       f.snaps(of: "card"), f.chrome(from: "bar.full", to: "bar.compact")]
        for r in results {
            #expect(r.environment?.clock == "the app's own clock (motion.clock, 0.1 s a tick)", "\(r.check)")
            #expect(r.text.contains("timed by the app's own clock") && !r.text.contains("wall clock"), "\(r.check): \(r.text)")
        }
        let decoded = try? JSONDecoder().decode(FeelFilm.self, from: f.json)
        #expect(decoded?.timedBy == f.timedBy)
    }

    @Test func settleTimeIsWhenTheElementLastMoved() {
        let f = film([(0, [card(900)]), (0.1, [card(600)]), (0.2, [card(420)]), (0.3, [card(400)]), (0.4, [card(400)]), (0.8, [card(400)])])
        #expect(f.settleTime(of: "card") == 0.3)
    }

    @Test func anElementThatNeverAppearsHasNoSettleTime() {
        #expect(film([(0, [])]).settleTime(of: "card") == nil)
    }

    @Test func aMoveAfterLandingIsAJump() {
        let f = film([(0, [card(700)]), (0.1, [card(400)]), (0.2, [card(400)]), (0.5, [card(400)]), (0.6, [card(440)]), (0.7, [card(440)])])
        let result = f.jumps(of: "card")
        #expect(!result.passed)
        #expect(result.measures["jumps"] == 1)
        #expect(result.findings.first?.what.contains("40") == true)
    }

    @Test func theFirstMoveFromRestIsTheTransitionNotAJump() {
        let f = film([(0, [card(200)]), (1.0, [card(200)]), (2.0, [card(200)]), (2.1, [card(520)]), (2.5, [card(520)])])
        #expect(f.jumps(of: "card").passed)
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

    @Test func aFilmWithAGapLongerThanMaxGapCannotPassForDoubleDraw() {
        // A copy drawn for less than the gap could fall inside it, so no copy seen is no evidence.
        let f = film([(0, [card(100, label: "Pancakes")]), (0.05, [card(100, label: "Pancakes")]), (1.5, [card(500, label: "Pancakes")])])
        let r = f.doubleDraws(of: ["Pancakes"])
        #expect(!r.passed)
        #expect(r.detections.isEmpty)
        #expect(r.findings.contains { $0.unchecked && $0.what.contains("1.450 s apart") })
        #expect(f.doubleDraws(of: ["Pancakes"], maxGap: 2).passed)
    }

    @Test func aCopySeenIsADoubleDrawHoweverSparseTheFilm() {
        let f = film([(0, [card(100, key: "a", label: "Pancakes"), card(500, key: "b", label: "Pancakes")]), (2, [card(500, label: "Pancakes")])])
        let r = f.doubleDraws(of: ["Pancakes"])
        #expect(r.detections.count == 1)
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

@Suite struct GenreTests {
    @Test func everyGenreSaysWhatGoodFeelsLike() {
        #expect(FeelGenre.allCases.count == 11)
        for genre in FeelGenre.allCases { #expect(!genre.good.isEmpty) }
        #expect(FeelGenre.wayBack.rawValue == "the way back")
    }

    @Test func everyCheckReportsItsGenre() {
        let phone = CGRect(x: 0, y: 0, width: 402, height: 874)
        #expect(FeelLayout.check([], window: phone, pose: "p").check == FeelGenre.insideWindow.rawValue)
        #expect(FeelTaps.evaluate([]).check == FeelGenre.tapLanding.rawValue)
        #expect(FeelPlace.compare(start: "a", after: [:]).check == FeelGenre.placeStability.rawValue)
        let f = FeelFilm(window: phone, frames: [])
        #expect(f.jumps(of: "x").check == FeelGenre.jumpAfterLanding.rawValue)
        #expect(f.doubleDraws(of: []).check == FeelGenre.doubleDraw.rawValue)
        #expect(f.chrome(from: "a", to: "b").check == FeelGenre.chrome.rawValue)
        #expect(f.settles("x", within: 1).check == FeelGenre.settleTime.rawValue)
        #expect(f.snaps(of: "x").check == FeelGenre.snap.rawValue)
    }
}

@Suite struct SnapTests {
    private func box(_ y: Double) -> FeelSeen { FeelSeen(key: "panel", frame: CGRect(x: 0, y: y, width: 300, height: 300)) }

    @Test func aBigMoveInOneSampleIsASnap() {
        let f = FeelFilm(window: phone, frames: [FeelFrame(t: 0, seen: [box(800)]), FeelFrame(t: 0.05, seen: [box(400)]), FeelFrame(t: 0.1, seen: [box(400)])])
        let r = f.snaps(of: "panel")
        #expect(!r.passed)
        #expect(r.findings.first?.what.contains("400") == true)
    }

    @Test func aMoveSeenInBetweenIsATransition() {
        let f = FeelFilm(window: phone, frames: [0, 0.05, 0.1, 0.15, 0.2].enumerated().map { i, t in
            FeelFrame(t: t, seen: [box(800 - Double(i) * 100)]) })
        #expect(f.snaps(of: "panel").passed)
    }

    @Test func appearingInFullBetweenTwoSamplesIsASnap() {
        let f = FeelFilm(window: phone, frames: [FeelFrame(t: 0, seen: []), FeelFrame(t: 0.05, seen: [box(400)]), FeelFrame(t: 0.1, seen: [box(400)])])
        #expect(!f.snaps(of: "panel", appearing: true).passed)
        // Without `appearing`, arriving is not motion, so a film of it cannot judge a snap.
        #expect(f.snaps(of: "panel").summary.hasPrefix("could not check"))
    }

    /// Mid-animation, SwiftUI's accessibility frame stretches from where the element is drawn to where it is going
    /// (seen on the iOS 27.2 simulator), so a stretched sample is an in-between position, however big the step to it.
    @Test func aStretchedFrameIsAnInBetweenPositionNotASnap() {
        func at(_ t: Double, _ y: Double, _ h: Double) -> FeelFrame { FeelFrame(t: t, seen: [FeelSeen(key: "panel", frame: CGRect(x: 0, y: y, width: 300, height: h))]) }
        let f = FeelFilm(window: phone, frames: [at(0, 200, 120), at(0.03, 200, 120), at(0.06, 200, 393.17), at(0.09, 200.26, 392.9),
                                                 at(0.12, 260, 333), at(0.15, 473, 120), at(0.18, 473, 120)])
        #expect(f.snaps(of: "panel").passed)
    }

    /// A stall in otherwise quick sampling hides the move: a transition and a snap with heavy layout both cause one
    /// (seen on the iOS 27.2 simulator), so the check cannot judge it and fails saying so.
    @Test func aMoveInsideAStallCannotBeJudged() {
        var frames = stride(from: 0.0, to: 1.0, by: 0.02).map { FeelFrame(t: $0, seen: [box(200)]) }
        frames += stride(from: 1.9, to: 2.5, by: 0.02).map { FeelFrame(t: $0, seen: [box(520)]) }
        let r = FeelFilm(window: phone, frames: frames).snaps(of: "panel")
        #expect(!r.passed)
        #expect(r.findings.contains { $0.what.contains("busy") })
    }

    /// A gap only a little longer than usual is not a stall: a move across it is judged as usual.
    @Test func aMoveInASlightlyLongGapIsStillASnap() {
        var frames = stride(from: 0.0, to: 1.0, by: 0.07).map { FeelFrame(t: $0, seen: [box(200)]) }
        frames += stride(from: 1.12, to: 2.0, by: 0.07).map { FeelFrame(t: $0, seen: [box(520)]) }
        #expect(!FeelFilm(window: phone, frames: frames).snaps(of: "panel").passed)
    }

    @Test func aSparseFilmCannotPassEvenWithNoMoveSeen() {
        let frames = stride(from: 0.0, to: 4.0, by: 0.5).map { FeelFrame(t: $0, seen: [box(200)]) }
        let r = FeelFilm(window: phone, frames: frames).snaps(of: "panel")
        #expect(!r.passed)
        #expect(r.findings.contains { $0.what.contains("too far apart") })
    }

    @Test func samplesTooSparseToJudgeSayso() {
        let f = FeelFilm(window: phone, frames: [FeelFrame(t: 0, seen: [box(800)]), FeelFrame(t: 0.5, seen: [box(400)])])
        let r = f.snaps(of: "panel")
        #expect(!r.passed)
        #expect(r.findings.contains { $0.what.contains("too far apart") })
    }
}

@Suite struct WayBackTests {
    @Test func aScreenWithAButtonAndAGestureBackPasses() {
        let d = FeelDestination(path: ["Recipes", "Pancakes"], affordance: "Back", affordanceReturns: true, gesture: "edge swipe")
        let r = FeelWayBack.evaluate([d])
        #expect(r.passed)
        #expect(r.check == FeelGenre.wayBack.rawValue)
        #expect(r.measures["screens"] == 1)
    }

    @Test func aScreenWithNoGestureBackFailsAndNamesThePath() {
        let d = FeelDestination(path: ["Recipes", "Chef"], affordance: "Back", affordanceReturns: true, gesture: nil)
        let r = FeelWayBack.evaluate([d])
        #expect(!r.passed)
        #expect(r.findings[0].what.contains("Recipes › Chef"))
        #expect(r.findings[0].what.contains("no gesture"))
    }

    @Test func aScreenWithNoButtonBackFails() {
        let r = FeelWayBack.evaluate([FeelDestination(path: ["Cook"], affordance: nil, affordanceReturns: false, gesture: "swipe down")])
        #expect(!r.passed)
        #expect(r.findings[0].what.contains("no visible way back"))
    }

    @Test func findingNoScreensAtAllFails() {
        #expect(!FeelWayBack.evaluate([]).passed)
    }

    @Test func aGestureThatMovedTheScreenAndSettledBackIsNoWayBack() {
        let d = FeelDestination(path: ["Recipes", "Settings"], affordance: "Done", affordanceReturns: true, gesture: nil, gestureArrived: true)
        let r = FeelWayBack.evaluate([d])
        #expect(!r.passed)
        #expect(r.detections.count == 1)
        #expect(r.detections[0].what.contains("Recipes › Settings"))
        #expect(r.detections[0].what.contains("settled back"))
    }

    @Test func aGestureThatNeverMovedTheScreenCouldNotBeChecked() {
        let d = FeelDestination(path: ["Recipes", "Chef"], affordance: "Back", affordanceReturns: true, gesture: nil, gestureArrived: false)
        let r = FeelWayBack.evaluate([d])
        #expect(!r.passed, "could not check is never a pass")
        #expect(r.detections.isEmpty, "a gesture that never arrived is not a bug found")
        #expect(r.findings.count == 1 && r.findings[0].unchecked)
        #expect(r.findings[0].what.contains("Recipes › Chef"))
        #expect(r.findings[0].what.contains("moved nothing"))
        #expect(r.summary.hasPrefix("could not check"))
    }

    @Test func aScreenWithNoButtonBackFailsEvenWhenItsGestureNeverArrived() {
        let d = FeelDestination(path: ["Cook"], affordance: nil, affordanceReturns: false, gesture: nil, gestureArrived: false)
        let r = FeelWayBack.evaluate([d])
        #expect(r.detections.map(\.what).contains { $0.contains("no visible way back") })
        #expect(r.findings.contains { $0.unchecked })
    }

    @Test func anOldRecordWithoutArrivalStillFails() throws {
        let json = #"{"path":["a"],"affordance":"Back","affordanceReturns":true}"#
        let d = try JSONDecoder().decode(FeelDestination.self, from: Data(json.utf8))
        #expect(d.gestureArrived == nil)
        #expect(FeelWayBack.evaluate([d]).detections.count == 1)
    }
}

@Suite struct GestureProgressTests {
    let window = CGRect(x: 0, y: 0, width: 400, height: 800)

    @Test func aScreenThatFollowedTheFingerAcrossMoved() {
        // The pushed screen's text slid from x 139 to 272 while the finger was held, as an interactive pop does.
        let before = ["Pancakes recipe": CGRect(x: 139, y: 300, width: 120, height: 20)]
        let during = [["Pancakes recipe": CGRect(x: 139, y: 300, width: 120, height: 20)],
                      ["Pancakes recipe": CGRect(x: 272, y: 300, width: 120, height: 20)]]
        #expect(FeelGestureProgress.moved(before: before, during: during, axis: .horizontal, window: window))
        #expect(!FeelGestureProgress.moved(before: before, during: during, axis: .vertical, window: window))
    }

    @Test func aScreenThatStayedPutDidNotMove() {
        let before = ["Ada's recipes": CGRect(x: 150, y: 300, width: 100, height: 20)]
        let during = Array(repeating: before, count: 8)
        #expect(!FeelGestureProgress.moved(before: before, during: during, axis: .horizontal, window: window))
    }

    @Test func aFewPointsOfJitterIsNotMovement() {
        let before = ["t": CGRect(x: 150, y: 300, width: 100, height: 20)]
        let during = [["t": CGRect(x: 154, y: 302, width: 100, height: 20)]]
        #expect(!FeelGestureProgress.moved(before: before, during: during, axis: .horizontal, window: window))
    }

    @Test func aSheetPulledDownMovedVertically() {
        let before = ["Settings": CGRect(x: 150, y: 400, width: 100, height: 20)]
        let during = [["Settings": CGRect(x: 150, y: 460, width: 100, height: 20)]]
        #expect(FeelGestureProgress.moved(before: before, during: during, axis: .vertical, window: window))
    }

    @Test func noSamplesIsNoEvidenceOfMovement() {
        #expect(!FeelGestureProgress.moved(before: ["t": .zero], during: [], axis: .horizontal, window: window))
    }

    @Test func anAnchorThatVanishedMidGestureIsNotMovement() {
        // Gone from the tree is not a displacement we saw; whether the screen went back is read separately.
        let before = ["t": CGRect(x: 150, y: 300, width: 100, height: 20)]
        #expect(!FeelGestureProgress.moved(before: before, during: [[:]], axis: .horizontal, window: window))
    }
}

@Suite struct OverlayTests {
    @Test func anOverlayThatGoesOnATapOutsideAndAfterAPickPasses() {
        let r = FeelOverlays.evaluate([FeelOverlayTrial(name: "sidebar", appeared: true, outsideDismisses: true, pickDismisses: true)])
        #expect(r.passed)
        #expect(r.check == FeelGenre.overlayDismissal.rawValue)
    }

    @Test func aSidebarThatStaysAfterAPickFails() {
        let r = FeelOverlays.evaluate([FeelOverlayTrial(name: "sidebar", appeared: true, outsideDismisses: true, pickDismisses: false)])
        #expect(!r.passed)
        #expect(r.findings[0].what.contains("after picking"))
    }

    @Test func anOverlayThatNeverOpenedFails() {
        #expect(!FeelOverlays.evaluate([FeelOverlayTrial(name: "menu", appeared: false)]).passed)
    }

    @Test func aPopoverOfControlsIsAskedOnlyForATapOutsideAndSaysSo() {
        let r = FeelOverlays.evaluate([FeelOverlayTrial(name: "serves", appeared: true, outsideDismisses: true,
                                                        noPickBecause: "it holds only a stepper or slider, which it stays open to adjust")])
        #expect(r.passed)
        #expect(r.findings.contains { $0.note && $0.what.contains("only a tap outside") })
    }

    @Test func aTapOutsideThatLandsOnTheScreenBehindIsNotCountedAsADismissal() {
        let r = FeelOverlays.evaluate([FeelOverlayTrial(name: "filter", appeared: true, outsideLandedBehind: true)])
        #expect(!r.passed)
        #expect(r.detections.isEmpty)
        #expect(r.findings.contains { $0.unchecked && $0.what.contains("landed on the screen behind") })
        #expect(!r.findings.contains { $0.what.contains("no place outside") })
    }

    @Test func theLowerEdgeSwipeAvoidsEveryRowAtTheEdgeAndIsSkippedWhenNoHeightIsFree() {
        let window = CGRect(x: 0, y: 0, width: 400, height: 800)
        // Rows that share one identifier still each block their height.
        let row = { (y: CGFloat) in CGRect(x: 0, y: y, width: 400, height: 60) }
        #expect(FeelWayBack.quietEdgeHeight(window: window, blocked: []) == 400)
        #expect(FeelWayBack.quietEdgeHeight(window: window, blocked: [row(380)]) == 336)
        // A row that starts away from the edge leaves it free.
        #expect(FeelWayBack.quietEdgeHeight(window: window, blocked: [CGRect(x: 60, y: 380, width: 300, height: 60)]) == 400)
        let full = stride(from: 0, to: 800, by: 60).map { row(CGFloat($0)) }
        #expect(FeelWayBack.quietEdgeHeight(window: window, blocked: full) == nil)
    }
}

@Suite struct SettleFromMotionTests {
    @Test func settleIsTimedFromTheFirstMove() {
        let still = (0..<10).map { FeelFrame(t: Double($0) * 0.1, seen: [card(200)]) }
        let moving = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5].map { t in FeelFrame(t: t, seen: [card(t == 1.0 ? 300 : 400)]) }
        let f = FeelFilm(window: phone, frames: still + moving)
        let r = f.settles("card", within: 0.5)
        #expect(r.passed)
        #expect(r.measures["settle"] == 0.2)
    }

    @Test func aSparseFilmCannotTimeSettling() {
        let f = film([(0, [card(200)]), (1.0, [card(200)]), (1.5, [card(500)]), (2.2, [card(500)]), (2.9, [card(500)])])
        let r = f.settles("card", within: 1.0)
        #expect(!r.passed)
        #expect(r.findings.contains { $0.what.contains("too far apart") })
    }

    @Test func aLateJumpMakesSettlingSlow() {
        let frames = [0, 0.1, 0.2, 1.4, 1.5].enumerated().map { i, t in FeelFrame(t: t, seen: [card(i == 0 ? 200 : (i < 3 ? 500 : 540))]) }
        #expect(!FeelFilm(window: phone, frames: frames).settles("card", within: 1).passed)
    }
}

/// A check never passes on what it could not see (decision record, point 6).
@Suite struct NothingSeenTests {
    @Test func motionChecksFailWhenTheElementIsNeverSeen() {
        let f = film((0..<20).map { (Double($0) * 0.05, [card(200, key: "other", label: "Other")]) })
        for r in [f.jumps(of: "card"), f.snaps(of: "card"), f.doubleDraws(of: ["Card"]), f.chrome(from: "bar.a", to: "bar.b"),
                  f.settles("card", within: 1)] {
            #expect(!r.passed, "\(r.check)")
            #expect(r.findings.contains { $0.what.contains("never on screen") || $0.what.contains("not on screen") || $0.what.contains("ever on screen") }, "\(r.check)")
        }
    }

    @Test func noControlsCountedFails() {
        let r = FeelLayout.check([], window: phone, pose: "portrait")
        #expect(!r.passed)
        #expect(r.findings.first?.what.contains("no controls") == true)
    }

    @Test func settlingStillMovingWhenTheFilmEndsFails() {
        let f = film((0..<10).map { (Double($0) * 0.05, [card(200 + Double($0) * 20)]) })
        let r = f.settles("card", within: 5)
        #expect(!r.passed)
        #expect(r.findings.contains { $0.what.contains("still moving when the film ended") })
    }

    @Test func settlingOfSomethingThatNeverMovedFails() {
        let r = film((0..<20).map { (Double($0) * 0.05, [card(200)]) }).settles("card", within: 1)
        #expect(!r.passed)
        #expect(r.findings.contains { $0.what.contains("never seen moving") })
    }

    @Test func noTimestampsAreNoHitchReading() {
        #expect(!FeelHitches.analyze(timestamps: [], refresh: 1.0 / 60).result().passed)
    }

    @Test func anOverlayCheckNotTriedIsAFinding() {
        let r = FeelOverlays.evaluate([FeelOverlayTrial(name: "full", appeared: true, outsideDismisses: nil, pickDismisses: true)])
        #expect(!r.passed)
        #expect(r.findings.contains { $0.what.contains("no place outside") })
    }

    @Test func nonFiniteMeasuresStayOutOfTheReport() {
        let r = FeelResult(check: "x", passed: false, summary: "s", measures: ["gap": .infinity, "nan": .nan, "ok": 1])
        #expect(r.measures == ["ok": 1])
        #expect(!r.json.isEmpty)
    }
}

@Suite struct ScrollAxisTests {
    @Test func aVerticalListDoesNotExcuseAControlOffTheSide() {
        let list = CGRect(x: 0, y: 100, width: 402, height: 700)
        let off = FeelElement(key: "t", type: "switch", frame: CGRect(x: 420, y: 300, width: 51, height: 31), scroll: list)
        #expect(!FeelLayout.check([off], window: phone, pose: "portrait").passed)
    }

    @Test func aHorizontalCarouselExcusesItsOffscreenItems() {
        let strip = CGRect(x: 0, y: 100, width: 402, height: 160)
        let next = FeelElement(key: "card 5", type: "button", frame: CGRect(x: 900, y: 110, width: 140, height: 140), scroll: strip, scrollsHorizontally: true)
        #expect(FeelLayout.check([next], window: phone, pose: "portrait").passed)
    }
}

@Suite struct SafetyTests {
    @Test func dangerousWordsMatchWhateverTheCase() {
        for key in ["account.signOut", "logout", "settings.delete-account", "Checkout", "trash_item", "Clear History"] {
            #expect(FeelSafety.isDangerous(key), "\(key)")
        }
        for key in ["recipe.pancakes", "Chefs", "nav.settings"] { #expect(!FeelSafety.isDangerous(key), "\(key)") }
    }
}

/// "Could not check" is not a detection: it fails, but says so in the summary and stays out of the counts.
@Suite struct CouldNotCheckTests {
    @Test func anUnseenElementIsNotCountedAsASnapOrJump() {
        let f = film((0..<20).map { (Double($0) * 0.05, [card(200, key: "other", label: "Other")]) })
        for (r, measure) in [(f.snaps(of: "card"), "snaps"), (f.jumps(of: "card"), "jumps"), (f.doubleDraws(of: ["Card"]), "doubled")] {
            #expect(!r.passed, "\(r.check)")
            #expect(r.measures[measure] == 0, "\(r.check)")
            #expect(r.summary.hasPrefix("could not check"), "\(r.summary)")
            #expect(r.findings.allSatisfy { $0.unchecked }, "\(r.check)")
            #expect(r.text.contains("(not checked)"))
        }
        let chrome = f.chrome(from: "bar.a", to: "bar.b")
        #expect(!chrome.passed)
        #expect(chrome.summary.hasPrefix("could not check"))
    }

    @Test func aSnapAndAnUnjudgedMoveAreCountedApart() {
        // A clean snap at 0.5 s, then a move hidden in a 1 s stall: one snap, one move not checked.
        var samples: [(Double, [FeelSeen])] = (0..<10).map { (Double($0) * 0.05, [card($0 < 5 ? 100 : 300)]) }
        samples += (10..<20).map { (Double($0) * 0.05, [card(300)]) }
        samples.append((1.95, [card(500)]))
        samples += (1..<10).map { (1.95 + Double($0) * 0.05, [card(500)]) }
        let r = film(samples).snaps(of: "card")
        #expect(!r.passed)
        #expect(r.measures["snaps"] == 1)
        #expect(r.summary.contains("snapped 1 time"))
        #expect(r.findings.filter { $0.unchecked }.count == 1)
    }

    @Test func noControlsIsCouldNotCheckInEveryPose() {
        let one = FeelLayout.check([], window: phone, pose: "portrait")
        #expect(one.summary.hasPrefix("could not check"))
        #expect(one.measures["outside"] == 0)
        let all = FeelLayout.combine([one, FeelLayout.check([], window: phone, pose: "landscape")])
        #expect(!all.passed)
        #expect(all.summary.hasPrefix("could not check"))
        #expect(all.measures["outside"] == 0)
    }

    @Test func aFilmWithOneSampleNeverPrintsInfinity() {
        let r = film([(0, [card(200)])]).snaps(of: "card")
        #expect(!r.passed)
        #expect(!r.text.contains("inf"))
    }

    @Test func oldReportsWithoutTheFlagStillDecode() throws {
        let finding = try JSONDecoder().decode(FeelFinding.self, from: Data(#"{"what":"x","inferred":false}"#.utf8))
        #expect(!finding.unchecked)
    }
}

@Suite struct CarouselTests {
    /// A full-height list in landscape is wide and short, so it can look like a carousel; it must not excuse a control off the side.
    @Test func aFullHeightScrollViewIsNeverACarousel() {
        let landscape = CGRect(x: 0, y: 0, width: 874, height: 402)
        let off = FeelElement(key: "t", type: "switch", frame: CGRect(x: 900, y: 200, width: 51, height: 31),
                              scroll: landscape, scrollsHorizontally: true)
        #expect(!FeelLayout.check([off], window: landscape, pose: "landscape").passed)
    }
}

@Suite struct WordTests {
    @Test func acronymsAndUnsubscribeAreCaught() {
        for key in ["URLDelete", "deleteURL", "Unsubscribe", "newsletter.unsubscribe"] { #expect(FeelSafety.isDangerous(key), "\(key)") }
    }

    @Test func backWordsMatchWholeWords() {
        for key in ["Back", "nav.close", "doneButton", "Close Sidebar", "Cancel"] { #expect(FeelWayBack.saysBack(key), "\(key)") }
        for key in ["Feedback", "Playback", "backgroundPicker", "Closet", "Undone"] { #expect(!FeelWayBack.saysBack(key), "\(key)") }
    }
}

@Suite struct ReviewThreeTests {
    @Test func aPortraitOnlyAppPassesWithANote() {
        let portrait = FeelLayout.check([FeelElement(key: "b", type: "button", frame: CGRect(x: 20, y: 20, width: 80, height: 44))],
                                        window: phone, pose: "portrait")
        var turned = FeelLayout.check([FeelElement(key: "b", type: "button", frame: CGRect(x: 20, y: 20, width: 80, height: 44))],
                                      window: phone, pose: "landscape")
        if let note = FeelLayout.stayedPortrait(window: phone, pose: "landscape", deviceLandscape: true) { turned.findings.append(note) }
        #expect(turned.findings.count == 1)
        let all = FeelLayout.combine([portrait, turned, portrait])
        #expect(all.passed)
        #expect(all.detections.isEmpty)
        #expect(all.text.contains("(note)"))
        #expect(FeelLayout.stayedPortrait(window: CGRect(x: 0, y: 0, width: 874, height: 402), pose: "landscape", deviceLandscape: true) == nil)
    }

    @Test func aCardCarouselInLandscapeExcusesItsOffscreenCards() {
        let landscape = CGRect(x: 0, y: 0, width: 874, height: 402)
        let strip = CGRect(x: 0, y: 120, width: 874, height: 200)
        let next = FeelElement(key: "card 6", type: "button", frame: CGRect(x: 900, y: 130, width: 180, height: 180), scroll: strip, scrollsHorizontally: true)
        #expect(FeelLayout.check([next], window: landscape, pose: "landscape").passed)
        let listUnderABar = CGRect(x: 0, y: 60, width: 874, height: 342)
        let off = FeelElement(key: "t", type: "switch", frame: CGRect(x: 900, y: 200, width: 51, height: 31), scroll: listUnderABar, scrollsHorizontally: true)
        #expect(!FeelLayout.check([off], window: landscape, pose: "landscape").passed)
    }

    /// A tap that leaves the navigation bar as it was and the screen underneath still there (a menu opening, edit mode,
    /// a row expanding) changed this screen; it did not reach a new one.
    @Test func anInPlaceChangeIsNotANewScreen() {
        #expect(!FeelWayBack.isNewScreen(barsBefore: ["Recipes"], barsAfter: ["Recipes"], stillThere: 4, of: 5))
        #expect(FeelWayBack.isNewScreen(barsBefore: ["Recipes"], barsAfter: ["Pancakes"], stillThere: 5, of: 5))
        #expect(FeelWayBack.isNewScreen(barsBefore: ["Recipes"], barsAfter: ["Recipes"], stillThere: 0, of: 5))
        #expect(FeelWayBack.isNewScreen(barsBefore: ["Recipes"], barsAfter: ["Recipes", "Settings"], stillThere: 5, of: 5))
        #expect(FeelWayBack.isNewScreen(barsBefore: [], barsAfter: [], stillThere: 0, of: 0))
    }

    /// A bar with no title is known by its back button too, so a push that keeps the bar's identifier (an untitled
    /// SwiftUI bar) but brings a back button, or changes its title, is a new bar.
    @Test func aBarIsKnownByItsBackButtonToo() {
        let root = FeelWayBack.barIdentity(key: "NavigationStackHosting", backLabels: [])
        let chefs = FeelWayBack.barIdentity(key: "NavigationStackHosting", backLabels: ["Kitchen"])
        let profile = FeelWayBack.barIdentity(key: "NavigationStackHosting", backLabels: ["Back"])
        #expect(root == "NavigationStackHosting")
        #expect(root != chefs && chefs != profile)
        #expect(FeelWayBack.isNewScreen(barsBefore: [chefs], barsAfter: [profile], stillThere: 1, of: 1))
    }

    /// Only the bar's way back names it: Done, Cancel and Close come with edit mode, selection and a popover's own bar.
    @Test func onlyTheBackButtonNamesABar() {
        #expect(FeelWayBack.isBackButton(identifier: "BackButton", label: "Kitchen"))
        #expect(FeelWayBack.isBackButton(identifier: "", label: "Back"))
        #expect(!FeelWayBack.isBackButton(identifier: "", label: "Done"))
        #expect(!FeelWayBack.isBackButton(identifier: "Cancel", label: "Cancel"))
        #expect(!FeelWayBack.isBackButton(identifier: "", label: "Close"))
        #expect(!FeelWayBack.isBackButton(identifier: "", label: "Feedback"))
        // A popover with its own Done bar adds a bar with no way back: it stays an overlay candidate.
        #expect(!FeelWayBack.replacedBar(barsBefore: ["Recipes"], barsAfter: ["Recipes", FeelWayBack.barIdentity(key: "Filter", backLabels: [])]))
    }

    /// A tap that replaced a bar that was on screen, or brought a bar with a back button, went somewhere new, so what it
    /// brought cannot float over the screen as an overlay: a pushed page's content under a tab bar that stayed is no
    /// menu. A tap that only added a bar with no way back (a popover with its own) or kept them all may still have
    /// opened one.
    @Test func aReplacedBarRulesOutAnOverlay() {
        #expect(FeelWayBack.replacedBar(barsBefore: ["Chefs ‹ Kitchen"], barsAfter: ["Chefs ‹ Back"]))
        #expect(!FeelWayBack.replacedBar(barsBefore: ["Recipes"], barsAfter: ["Recipes"]))
        #expect(!FeelWayBack.replacedBar(barsBefore: ["Recipes"], barsAfter: ["Recipes", "Filter"]))
        #expect(!FeelWayBack.replacedBar(barsBefore: [], barsAfter: ["Settings"]))
        // A bar that arrives with a back button is a push, even from a screen with no bar.
        #expect(FeelWayBack.replacedBar(barsBefore: [], barsAfter: [FeelWayBack.barIdentity(key: "Hosting", backLabels: ["Back"])]))
    }

    /// A tap after which most of the screen's own content (its texts and controls, not the tab or navigation bars that
    /// every screen shares) is gone left the screen, even when its bar and a shared control stayed. Too little content
    /// to judge says nothing.
    @Test func mostContentGoneLeftTheScreen() {
        #expect(FeelWayBack.leftContent(kept: 2, of: 9))
        #expect(FeelWayBack.leftContent(kept: 2, of: 5))
        #expect(!FeelWayBack.leftContent(kept: 5, of: 9))
        #expect(!FeelWayBack.leftContent(kept: 9, of: 9))
        #expect(!FeelWayBack.leftContent(kept: 0, of: 3))
    }

    @Test func emptyStartKeepsNothing() {
        let r = FeelPlace.compare(start: FeelPlace.empty, after: ["relaunch": FeelPlace.empty])
        #expect(!r.passed)
        #expect(r.measures["kept"] == nil)
    }

    @Test func noHitchReadingHasNoMeasures() {
        let r = FeelHitches.analyze(timestamps: [], refresh: 1.0 / 60).result()
        #expect(r.measures["ratio"] == nil)
        #expect(r.measures["hitches"] == nil)
    }

    @Test func anOverlayThatNeverAppearedIsNotCountedAsFailing() {
        let r = FeelOverlays.evaluate([FeelOverlayTrial(name: "a", appeared: true, outsideDismisses: false, pickDismisses: true),
                                       FeelOverlayTrial(name: "c", appeared: true, outsideDismisses: true, pickDismisses: true),
                                       FeelOverlayTrial(name: "b", appeared: false)])
        #expect(!r.passed)
        #expect(r.summary.hasPrefix("1 of 2 overlays"), "\(r.summary)")
    }
}

@Suite struct SnapNeedsMotionTests {
    /// Fixture run 7b: the card had already moved when the film began, so only the late 40-point nudge was seen. A
    /// snap check that saw no move past its distance cannot pass.
    @Test func aSnapCheckThatSawNoMotionCannotPass() {
        let f = film((0..<60).map { (Double($0) * 0.05, [card($0 < 30 ? 582 : 622)]) })
        let r = f.snaps(of: "card")
        #expect(!r.passed)
        #expect(r.summary.hasPrefix("could not check"))
        #expect(r.measures["snaps"] == 0)
    }
}

@Suite struct LeavingIsNotArrivingTests {
    @Test func anElementThatLeavesHasNotArrived() {
        let f = FeelFilm(window: phone, frames: (0..<10).map { i in
            FeelFrame(t: Double(i) * 0.05, seen: i < 5 ? [FeelSeen(key: "panel", label: "Panel", frame: CGRect(x: 0, y: 400, width: 200, height: 200))] : []) })
        let r = f.snaps(of: "panel", appearing: true)
        #expect(!r.passed)
        #expect(r.summary.hasPrefix("could not check"))
    }
}

/// The walk hands any overlay a tap opened (a menu, a popover) to the overlay-dismissal check, and lists every
/// relaunch it needed, so neither passes silently.
@Suite struct WalkOverlayTests {
    let good = FeelDestination(path: ["launch", "nav.recipe"], affordance: "Back", affordanceReturns: true, gesture: "edge swipe")

    @Test func anOverlayThatStaysOpenFailsTheWayBack() {
        let r = FeelWayBack.evaluate([good], overlays: [FeelOverlayTrial(name: "launch › nav.filter", appeared: true, outsideDismisses: false, pickDismisses: false)])
        #expect(!r.passed)
        #expect(r.detections.contains { $0.what.contains("nav.filter: a tap outside it did not dismiss it") })
        #expect(r.detections.contains { $0.what.contains("nav.filter: still on screen after picking an item") })
        #expect(r.summary.contains("0 of 1 overlays the walk opened dismiss"))
        #expect(r.measures["overlays"] == 1)
    }

    @Test func aWellBehavedOverlayPassesWithANote() {
        let r = FeelWayBack.evaluate([good], overlays: [FeelOverlayTrial(name: "launch › Sort: Newest", appeared: true, outsideDismisses: true, pickDismisses: true)])
        #expect(r.passed)
        #expect(r.summary.contains("1 of 1 overlays the walk opened dismiss"))
    }

    @Test func everyRelaunchIsReported() {
        let r = FeelWayBack.evaluate([good], relaunches: ["after launch › nav.filter, which stayed open"])
        #expect(r.findings.contains { $0.what.contains("relaunched the app after launch › nav.filter") })
        #expect(r.measures["relaunches"] == 1)
    }
}

/// A system menu hides the screen behind it from the accessibility tree, so the walk sees the old controls gone, as
/// after a push. What tells them apart: no new navigation bar, a small area, and no way back of its own.
@Suite struct OpensOverlayTests {
    let window = CGRect(x: 0, y: 0, width: 402, height: 874)

    @Test func aSystemMenuIsAnOverlay() {
        #expect(FeelWayBack.opensOverlay(barsBefore: ["Recipes"], barsAfter: [],
                                        appeared: [CGRect(x: 36, y: 255, width: 250, height: 42), CGRect(x: 36, y: 297, width: 250, height: 42)],
                                        appearedSaysBack: false, window: window))
    }

    @Test func aPushIsNot() {
        #expect(!FeelWayBack.opensOverlay(barsBefore: ["Recipes"], barsAfter: ["Pancakes"],
                                         appeared: [CGRect(x: 0, y: 300, width: 200, height: 40)], appearedSaysBack: false, window: window))
    }

    @Test func aCoverWithACloseButtonIsNot() {
        #expect(!FeelWayBack.opensOverlay(barsBefore: ["Recipes"], barsAfter: [],
                                         appeared: [CGRect(x: 16, y: 60, width: 60, height: 44)], appearedSaysBack: true, window: window))
    }

    @Test func somethingFillingTheWindowIsNot() {
        #expect(!FeelWayBack.opensOverlay(barsBefore: ["Recipes"], barsAfter: [],
                                         appeared: [CGRect(x: 0, y: 0, width: 402, height: 800)], appearedSaysBack: false, window: window))
    }

    @Test func nothingAppearingIsNot() {
        #expect(!FeelWayBack.opensOverlay(barsBefore: ["Recipes"], barsAfter: [], appeared: [], appearedSaysBack: false, window: window))
    }
}

/// People tap while a control is still animating. Every double tap must end where it started: our bar is higher than
/// UIKit's, so the OS switch's rate is context in the report and never turns a fail into a pass.
@Suite struct LateTapTests {
    @Test func aTapThatLandedLateLandedAndIsNoted() {
        // A loaded machine reports a change late; the tap was sent once, and it landed.
        let r = FeelTaps.evaluate([FeelTapTrial(spot: .centre, landed: true), FeelTapTrial(spot: .centre, landed: true, late: true)])
        #expect(r.passed)
        #expect(r.summary.contains("2 of 2 single taps landed, no retries"))
        #expect(r.findings.contains { $0.note && $0.what.contains("centre: 1 of 2 single taps landed late") })
        #expect(r.measures["late"] == 1)
    }

    @Test func aTapThatNeverLandedStillFails() {
        #expect(!FeelTaps.evaluate([FeelTapTrial(spot: .trailingEdge, landed: false)]).passed)
    }

    @Test func anOlderTrialDecodes() throws {
        let t = try JSONDecoder().decode(FeelTapTrial.self, from: Data(#"{"spot":"centre","landed":true,"expected":true}"#.utf8))
        #expect(!t.late)
    }
}

@Suite struct RapidTapTests {
    let paced = (0..<5).map { _ in FeelTapTrial(spot: .centre, landed: true) }

    @Test func lostRapidTapsFailAndTheReportGivesBothRates() {
        let r = FeelTaps.evaluate(paced, rapid: FeelRapidTaps(pairs: 5, endedWhereStarted: 0), rapidBaseline: 1)
        #expect(!r.passed)
        #expect(r.measures["rapid rate"] == 0)
        #expect(r.measures["rapid baseline"] == 1)
        #expect(r.detections.contains { $0.inferred && $0.what.contains("0 of 5") && $0.what.contains("5 of 5") })
        #expect(r.summary.contains("rapid: 0 of 5 double taps ended where they started"))
    }

    @Test func anOSControlThatAlsoDropsThemNeverTurnsAFailIntoAPass() {
        let r = FeelTaps.evaluate(paced, rapid: FeelRapidTaps(pairs: 5, endedWhereStarted: 0), rapidBaseline: 0)
        #expect(!r.passed)
        #expect(r.detections.contains { $0.what.contains("the OS control also drops these") })
    }

    @Test func everyPairMustEndWhereItStartedWithOrWithoutABaseline() {
        #expect(!FeelTaps.evaluate(paced, rapid: FeelRapidTaps(pairs: 5, endedWhereStarted: 4)).passed)
        #expect(!FeelTaps.evaluate(paced, rapid: FeelRapidTaps(pairs: 5, endedWhereStarted: 4), rapidBaseline: 1).passed)
        #expect(FeelTaps.evaluate(paced, rapid: FeelRapidTaps(pairs: 5, endedWhereStarted: 5, tripleChanged: true)).passed)
        #expect(FeelTaps.evaluate(paced, rapid: FeelRapidTaps(pairs: 5, endedWhereStarted: 5, tripleChanged: true), rapidBaseline: 0).passed)
    }

    @Test func pairsThatAllEndedWhereTheyStartedNeedATripleThatChanged() {
        // A control that swallows quick bursts ends where it started every time; the triple shows bursts arrive.
        let swallowed = FeelTaps.evaluate(paced, rapid: FeelRapidTaps(pairs: 5, endedWhereStarted: 5, tripleChanged: false))
        #expect(!swallowed.passed)
        #expect(swallowed.findings.contains { $0.unchecked && $0.what.contains("triple tap left the control unchanged") })
        let unprobed = FeelTaps.evaluate(paced, rapid: FeelRapidTaps(pairs: 5, endedWhereStarted: 5))
        #expect(!unprobed.passed)
        #expect(unprobed.findings.contains { $0.unchecked })
    }

    @Test func notScoredWhenCentreTapsMissed() {
        // A pair that ended where it started may have had no tap land, so it says nothing when the centre misses.
        let r = FeelTaps.evaluate([FeelTapTrial(spot: .centre, landed: false)], rapid: FeelRapidTaps(pairs: 5, endedWhereStarted: 5, tripleChanged: true), rapidBaseline: 1)
        #expect(!r.passed)
        #expect(r.findings.contains { $0.unchecked && $0.what.contains("not scored") })
    }

    @Test func requestedButNotScoredIsNotAPass() {
        // No centre singles were tried, so the pairs say nothing; a requested check that was not scored fails.
        let edges = (0..<3).map { _ in FeelTapTrial(spot: .leadingEdge, landed: true) }
        let r = FeelTaps.evaluate(edges, rapid: FeelRapidTaps(pairs: 5, endedWhereStarted: 5, tripleChanged: true))
        #expect(!r.passed)
        #expect(r.findings.contains { $0.unchecked && $0.what.contains("not scored") })
    }

    @Test func scoredWhenOnlyAnEdgeMissed() {
        let r = FeelTaps.evaluate(paced + [FeelTapTrial(spot: .trailingEdge, landed: false)], rapid: FeelRapidTaps(pairs: 5, endedWhereStarted: 0), rapidBaseline: 1)
        #expect(r.detections.contains { $0.what.contains("rapid taps") })
    }
}

/// A tap that keeps the screen can open an overlay or change the screen in place (edit mode, a row expanding, "Show
/// more", validation text). Only an overlay floats over controls that stayed where they were.
@Suite struct FloatsOverTests {
    let row = CGRect(x: 16, y: 385, width: 370, height: 52)

    @Test func aMenuOverRowsThatStayedFloats() {
        #expect(FeelWayBack.floatsOver(appeared: [CGRect(x: 91, y: 400, width: 220, height: 44)], stayed: [row]))
    }

    @Test func rowsInsertedBelowDoNotFloat() {
        // A disclosure group's children appear below; the rows under them moved, so they did not stay.
        #expect(!FeelWayBack.floatsOver(appeared: [CGRect(x: 16, y: 437, width: 370, height: 44)], stayed: [row]))
    }

    @Test func aSliverOfOverlapDoesNotCount() {
        #expect(!FeelWayBack.floatsOver(appeared: [CGRect(x: 16, y: 435, width: 370, height: 44)], stayed: [row]))
    }

    @Test func nothingStayedNothingFloats() {
        #expect(!FeelWayBack.floatsOver(appeared: [row], stayed: []))
    }
}

/// Every relaunch shows in the summary, so a quoted PASS line is never read as recovery-free.
@Suite struct RelaunchSummaryTests {
    @Test func aPassingWalkThatRelaunchedSaysSo() {
        let good = FeelDestination(path: ["launch", "a"], affordance: "Back", affordanceReturns: true, gesture: "edge swipe")
        let r = FeelWayBack.evaluate([good], relaunches: ["after x"])
        #expect(r.passed)
        #expect(r.summary.contains("1 relaunch"))
    }
}

@Suite struct RecordingTests {
    @Test("each recording request names its own marker and film, so a late film is never read as the next one's")
    func requestsAreNamedApart() throws {
        let first = FeelRecording.Request(keys: ["recipe.title"])
        let second = FeelRecording.Request(keys: ["recipe.title"])
        #expect(first.id != second.id)
        #expect(FeelRecording.filmFile(first.id) != FeelRecording.filmFile(second.id))
        #expect(FeelRecording.recordingFile(first.id) != FeelRecording.recordingFile(second.id))
        let decoded = try JSONDecoder().decode(FeelRecording.Request.self, from: JSONEncoder().encode(first))
        #expect(decoded == first)
    }

    @Test("a request can ask for every copy of a key, for double draws counted frame by frame; an older one cannot")
    func requestsAskForCopies() throws {
        let copies = FeelRecording.Request(keys: ["recipe.title"], copies: true)
        #expect(copies.copies)
        #expect(try JSONDecoder().decode(FeelRecording.Request.self, from: JSONEncoder().encode(copies)) == copies)
        #expect(!FeelRecording.Request(keys: ["recipe.title"]).copies)
        let older = try JSONDecoder().decode(FeelRecording.Request.self, from: Data(#"{"id":"a","keys":["k"]}"#.utf8))
        #expect(!older.copies)
    }

    @Test("a film cut at the recorder's cap reads as stalled, so no motion check passes on what came after")
    func aCappedFilmIsNotJudged() {
        let frames = (0..<10).map { FeelFrame(t: Double($0) * 0.016, seen: [FeelSeen(key: "card", frame: CGRect(x: Double($0) * 10, y: 0, width: 50, height: 50))]) }
        let film = FeelFilm(window: CGRect(x: 0, y: 0, width: 400, height: 800), frames: frames, stalledAt: 0.144, timedBy: FeelRecording.timedBy)
        let settle = film.settles("card", within: 1)
        #expect(!settle.passed)
        #expect(settle.text.contains(FeelRecording.timedBy))
    }
}
