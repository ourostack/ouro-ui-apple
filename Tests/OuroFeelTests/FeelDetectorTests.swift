import CoreGraphics
import Foundation
import OuroFeelCore
import Testing

private let screen = CGRect(x: 0, y: 0, width: 402, height: 874)
private let words = CGRect(x: 20, y: 100, width: 360, height: 600)

/// A film one sample a frame (1/60 s), each sample showing the given element, or nothing.
private func film(_ samples: [FeelSeen?], key: String = "page") -> FeelFilm {
    FeelFilm(window: screen, frames: samples.enumerated().map { i, s in FeelFrame(t: Double(i) / 60, seen: s.map { [$0] } ?? []) })
}

private func page(_ label: String, y: Double = 100) -> FeelSeen {
    FeelSeen(key: "page", label: label, frame: CGRect(x: 20, y: y, width: 360, height: 600))
}

@Suite struct FlickerTests {
    @Test func oneChangeOfWordsPasses() {
        let f = film(Array(repeating: page("p1"), count: 5) + Array(repeating: page("p2"), count: 10))
        let result = f.flickers(of: ["page"])
        #expect(result.passed, "\(result.text)")
        #expect(result.check == "flicker")
    }

    /// Gatefold build 20 (Ari, 2026-11-07: "literally spazzes!"): the page showed the next page, the old one, then the
    /// next one again before it settled.
    @Test func wordsTakenBackFail() {
        let f = film([page("p1"), page("p1"), page("p2"), page("p1"), page("p2"), page("p2"), page("p2"), page("p2")])
        let result = f.flickers(of: ["page"])
        #expect(!result.passed)
        #expect(result.detections.contains { $0.what.contains("taken back") })
        #expect(result.summary.contains("flicker"))
    }

    @Test func wordsChangingSeveralTimesBeforeSettlingFail() {
        let f = film([page("p1"), page("p2"), page("p3"), page("p4"), page("p4"), page("p4"), page("p4")])
        let result = f.flickers(of: ["page"])
        #expect(!result.passed)
        #expect(result.detections.contains { $0.what.contains("changed 3 times") })
    }

    @Test func changesFarApartAreNotAFlicker() {
        let f = film(Array(repeating: page("p1"), count: 5) + Array(repeating: page("p2"), count: 40) + Array(repeating: page("p3"), count: 5))
        #expect(f.flickers(of: ["page"], within: 30).passed)
    }

    @Test func aBlinkFails() {
        let f = film([page("p1"), page("p1"), nil, page("p1"), page("p1"), page("p1")])
        let result = f.flickers(of: ["page"])
        #expect(!result.passed)
        #expect(result.detections.contains { $0.what.contains("went away for 1 sample") })
    }

    @Test func aBadgeThatBlinksOnFails() {
        let badge = FeelSeen(key: "badge", frame: CGRect(x: 300, y: 40, width: 40, height: 20))
        let f = film([nil, nil, badge, nil, nil, nil], key: "badge")
        let result = f.flickers(of: ["badge"])
        #expect(!result.passed)
        #expect(result.detections.contains { $0.what.contains("blinked on") })
    }

    @Test func appearingOnceIsNoFlicker() {
        #expect(film([nil, nil, page("p1"), page("p1"), page("p1"), page("p1")]).flickers(of: ["page"]).passed)
    }

    @Test func goingAndComingBackToTheSamePlaceFails() {
        let f = film([page("p", y: 100), page("p", y: 100), page("p", y: 160), page("p", y: 100), page("p", y: 100), page("p", y: 100)])
        let result = f.flickers(of: ["page"])
        #expect(!result.passed)
        #expect(result.detections.contains { $0.what.contains("left its place by 60 pt") })
    }

    @Test func aSpringThatOvershootsIsNoFlicker() {
        let ys: [Double] = [100, 100, 140, 180, 210, 206, 200, 200, 200, 200]
        #expect(film(ys.map { page("p", y: $0) }).flickers(of: ["page"]).passed)
    }

    @Test func stillChangingAtTheEndCouldNotBeChecked() {
        let f = film([page("p1"), page("p1"), page("p1"), page("p1"), page("p2")])
        let result = f.flickers(of: ["page"])
        #expect(!result.passed)
        #expect(result.detections.isEmpty)
        #expect(result.summary.hasPrefix("could not check"))
    }

    @Test func neverSeenCouldNotBeChecked() {
        let result = film([nil, nil, nil]).flickers(of: ["page"])
        #expect(!result.passed && result.detections.isEmpty)
    }

    @Test func aSparseFilmThatSawNoFlickerCouldNotBeChecked() {
        let f = FeelFilm(window: screen, frames: [0.0, 0.1, 1.2, 1.3, 1.4].map { FeelFrame(t: $0, seen: [page("p1")]) })
        let result = f.flickers(of: ["page"])
        #expect(!result.passed && result.detections.isEmpty)
        #expect(result.findings.contains { $0.what.contains("1.100 s apart") })
    }

    @Test func aOneSampleFilmNeverPasses() {
        #expect(!film([page("p1")]).flickers(of: ["page"], hold: 1).passed)
    }

    @Test func aStalledFilmCouldNotBeChecked() {
        var f = film(Array(repeating: page("p1"), count: 6))
        f.stalledAt = 0.05
        #expect(!f.flickers(of: ["page"]).passed)
    }
}

@Suite struct PlaceTrailTests {
    private let a = FeelPlace.fingerprint("place a"), b = FeelPlace.fingerprint("place b"), c = FeelPlace.fingerprint("place c")

    @Test func strayActionsThatKeepThePlacePass() {
        let trail = FeelPlaceTrail([.read(a), .action("stray tap", deliberate: false), .read(a), .read(a),
                                    .action("sheet dismissed", deliberate: false), .read(FeelPlace.empty), .read(a)])
        let result = trail.strayInput()
        #expect(result.passed, "\(result.text)")
        #expect(result.check == "place kept through stray input")
        #expect(result.measures["kept"] == 2)
    }

    /// Gatefold build 20 (Ari, 2026-11-07: "fucked my location with accidental navigation").
    @Test func aStrayTapThatMovesThePlaceFails() {
        let trail = FeelPlaceTrail([.read(a), .action("stray tap", deliberate: false), .read(b), .read(b)])
        let result = trail.strayInput()
        #expect(!result.passed)
        #expect(result.detections.count == 1)
        #expect(result.detections[0].what.contains("stray tap moved the place"))
    }

    @Test func aStrayActionThatMovesThePlaceAndBackStillFails() {
        let trail = FeelPlaceTrail([.read(a), .action("sheet dismissed", deliberate: false), .read(a), .read(b), .read(a)])
        let result = trail.strayInput()
        #expect(!result.passed)
        #expect(result.detections[0].what.contains("came back"))
    }

    @Test func deliberateMovesAreNotStray() {
        let trail = FeelPlaceTrail([.read(a), .action("next page", deliberate: true), .read(b), .action("stray tap", deliberate: false), .read(b)])
        #expect(trail.strayInput().passed)
    }

    @Test func aStrayActionNeverReadAfterCouldNotBeChecked() {
        let result = FeelPlaceTrail([.read(a), .action("stray tap", deliberate: false)]).strayInput()
        #expect(!result.passed && result.detections.isEmpty)
    }

    @Test func aMoveThatLandsAndHoldsPasses() {
        let trail = FeelPlaceTrail([.read(a), .action("next page", deliberate: true), .read(a), .read(b), .read(b), .read(b)])
        let result = trail.fights()
        #expect(result.passed, "\(result.text)")
        #expect(result.check == "navigation that fights you")
    }

    @Test func aLateRestoreAfterYourMoveFails() {
        let trail = FeelPlaceTrail([.read(a), .action("next page", deliberate: true), .read(b), .read(b), .read(a), .read(a), .read(a)])
        let result = trail.fights()
        #expect(!result.passed)
        #expect(result.detections[0].what.contains("late restore"))
    }

    @Test func aReSentJumpAfterYourMoveFails() {
        let trail = FeelPlaceTrail([.read(a), .action("next page", deliberate: true), .read(b), .read(b), .read(c), .read(c), .read(c)])
        let result = trail.fights()
        #expect(!result.passed)
        #expect(result.detections[0].what.contains("re-sent or late jump"))
    }

    /// W12's case: a page that lands across two reads mid-animation shows a place for one read on its way.
    @Test func aPageThatLandsAcrossTwoReadsIsNoFight() {
        let trail = FeelPlaceTrail([.read(a), .action("next page", deliberate: true), .read(b), .read(c), .read(c), .read(c)])
        #expect(trail.fights().passed)
    }

    @Test func aRestoreOneReadAfterTheMoveFails() {
        let trail = FeelPlaceTrail([.read(a), .action("next page", deliberate: true), .read(b), .read(a), .read(a), .read(a)])
        let result = trail.fights()
        #expect(!result.passed)
        #expect(result.detections[0].what.contains("late restore"))
    }

    /// The reviewer's case: snapped back for one read, then forward again. Where you came from is never a page on the way.
    @Test func aOneReadPullBackFails() {
        let trail = FeelPlaceTrail([.read(a), .action("next page", deliberate: true), .read(b), .read(a), .read(b), .read(b), .read(b)])
        let result = trail.fights()
        #expect(!result.passed)
        #expect(result.detections[0].what.contains("late restore"))
    }

    /// Gatefold build 20: a tap on the right edge while a Contents jump's veil was up landed a page past the chapter.
    @Test func landingOffWhereYouChoseFails() {
        let trail = FeelPlaceTrail([.read(a), .action("Contents to chapter 3", deliberate: true), .chose(b),
                                    .read(FeelPlace.empty), .read(c), .read(c), .read(c)])
        let result = trail.fights()
        #expect(!result.passed)
        #expect(result.detections[0].what.contains("not where you chose"))
    }

    @Test func landingWhereYouChosePasses() {
        let trail = FeelPlaceTrail([.read(a), .action("Contents to chapter 3", deliberate: true), .chose(b),
                                    .read(FeelPlace.empty), .read(b), .read(b), .read(b)])
        #expect(trail.fights().passed)
    }

    @Test func aChosenJumpStillLoadingCouldNotBeChecked() {
        let trail = FeelPlaceTrail([.read(a), .action("Contents to chapter 3", deliberate: true), .chose(b),
                                    .read(FeelPlace.empty), .read(FeelPlace.empty)])
        let result = trail.fights()
        #expect(!result.passed && result.detections.isEmpty)
    }

    @Test func aChosenMoveThatNeverLeftFails() {
        let trail = FeelPlaceTrail([.read(a), .action("Contents to chapter 3", deliberate: true), .chose(b), .read(a), .read(a), .read(a)])
        #expect(!trail.fights().passed)
        #expect(!trail.fights().detections.isEmpty)
    }

    /// No input at all: a late cloud reply moves the place while you are idle.
    @Test func aLateReplyWithNoInputFails() {
        let trail = FeelPlaceTrail([.read(a), .action("no input", deliberate: false), .read(a), .read(a), .read(c), .read(c)])
        let result = trail.strayInput()
        #expect(!result.passed)
        #expect(result.detections[0].what.hasPrefix("no input moved the place"))
    }

    @Test func aStepThatDidNotHappenCouldNotBeChecked() {
        let trail = FeelPlaceTrail([.read(a), .action("Contents opened and swiped away", deliberate: false),
                                    .unchecked("the sheet did not close"), .read(a), .read(a)])
        let result = trail.strayInput()
        #expect(!result.passed && result.detections.isEmpty)
        #expect(result.summary.contains("the sheet did not close"))
    }

    @Test func holdIsAtLeastTwoReads() {
        let trail = FeelPlaceTrail([.read(a), .action("next page", deliberate: true), .read(a)])
        let result = trail.fights(hold: 1)
        #expect(!result.passed && result.detections.isEmpty)
    }

    @Test func aMoveReadTooBrieflyCouldNotBeChecked() {
        let result = FeelPlaceTrail([.read(a), .action("next page", deliberate: true), .read(b)]).fights()
        #expect(!result.passed && result.detections.isEmpty)
    }

    @Test func aMoveThatWentNowhereIsNoFight() {
        let result = FeelPlaceTrail([.read(a), .action("next page", deliberate: true), .read(a), .read(a), .read(a)]).fights()
        #expect(result.passed)
    }

    @Test func aTrailWithNoMovesCouldNotBeChecked() {
        #expect(!FeelPlaceTrail([.read(a)]).fights().passed)
        #expect(!FeelPlaceTrail([.read(a)]).strayInput().passed)
    }

    @Test func aTrailRoundTripsThroughJSON() throws {
        let trail = FeelPlaceTrail([.read(a), .action("jump", deliberate: true), .chose(b), .unchecked("why"), .read(b)])
        let data = try JSONEncoder().encode(trail)
        #expect(try JSONDecoder().decode(FeelPlaceTrail.self, from: data) == trail)
    }
}
