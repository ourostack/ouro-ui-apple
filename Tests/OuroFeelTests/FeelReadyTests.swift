import CoreGraphics
import Foundation
import OuroFeelCore
import Testing

/// A fake clock for the wait: `pause` moves it on, and so does each look (a loaded runner's slow snapshot).
private final class FakeClock {
    var now: Double = 0
    let lookTakes: Double
    init(lookTakes: Double = 0) { self.lookTakes = lookTakes }
}

/// Gatefold run 46076998864 (duo-feel-closed, a loaded runner): covered content was reported as finding no content in
/// the reader's page, and failed without measuring. A check waits for the content it measures first, and says the page never became ready
/// rather than scoring an empty one.
@Suite struct ReadyTests {
    @Test func aPageWhoseWordsArriveLateIsWaitedFor() {
        let clock = FakeClock(lookTakes: 0.8)
        // No words for the first 80 s, then the page; each look takes 0.8 s, as on a loaded runner.
        let readiness = FeelReady.wait(timeout: 120, every: 0.25, now: { clock.now },
                                       look: { clock.now += clock.lookTakes; return FeelReadyLook(content: clock.now < 80 ? 0 : 41) },
                                       pause: { clock.now += $0 })
        #expect(readiness.ready)
        #expect(readiness.waited >= 79 && readiness.waited < 81)
        #expect(readiness.last.content == 41)
    }

    @Test func pausesBetweenLooksAndNeverSleepsWhenReadyAtOnce() {
        let clock = FakeClock()
        var pauses = 0
        let readiness = FeelReady.wait(timeout: 120, every: 0.25, now: { clock.now }, look: { FeelReadyLook(content: 3) },
                                       pause: { pauses += 1; clock.now += $0 })
        #expect(readiness.ready)
        #expect(readiness.looks == 1)
        #expect(pauses == 0)
        #expect(readiness.waited == 0)
    }

    @Test func theAppsOwnSignalHoldsTheCheckEvenWithWordsOnScreen() {
        // Placeholder text can be on screen before the page is laid out; the app's signal decides.
        let clock = FakeClock(lookTakes: 0.1)
        let readiness = FeelReady.wait(timeout: 120, every: 0.25, now: { clock.now },
                                       look: { clock.now += clock.lookTakes; return FeelReadyLook(content: 5, signal: clock.now >= 30) },
                                       pause: { clock.now += $0 })
        #expect(readiness.ready)
        #expect(readiness.waited >= 29.8)
    }

    @Test func contentThatNeverArrivesIsNeverReadyAndFailsAsSuch() {
        let clock = FakeClock(lookTakes: 0.5)
        let readiness = FeelReady.wait(timeout: 120, every: 0.25, now: { clock.now },
                                       look: { clock.now += clock.lookTakes; return FeelReadyLook(content: 0) },
                                       pause: { clock.now += $0 })
        #expect(!readiness.ready)
        #expect(readiness.waited >= 120)
        let result = FeelReady.neverReady(check: FeelGenre.insideWindow.rawValue, readiness: readiness,
                                          what: "reader.page", pose: "closed")
        #expect(!result.passed)
        #expect(result.summary.hasPrefix("never became ready:"), "\(result.text)")
        #expect(result.summary.contains("no content came on screen in \"reader.page\""), "\(result.text)")
        #expect(result.findings.count == 1)
        #expect(result.findings[0].neverReady)
        #expect(!result.findings[0].unchecked, "never ready is its own failure, not a could-not-check")
        #expect(result.detections.isEmpty, "an empty page is never scored as a bug found")
        #expect(result.measures["waited"] ?? 0 >= 120)
        #expect(result.text.contains("(never ready)"))
    }

    @Test func aSignalThatNeverComesSaysSo() {
        let clock = FakeClock()
        let readiness = FeelReady.wait(timeout: 10, every: 0.25, now: { clock.now },
                                       look: { FeelReadyLook(content: 7, signal: false) }, pause: { clock.now += $0 })
        #expect(!readiness.ready)
        let result = FeelReady.neverReady(check: "viewport holds still", readiness: readiness, what: nil, pose: "landscape")
        #expect(result.summary.contains("the app never signalled ready"), "\(result.text)")
        #expect(result.summary.contains("in landscape"))
    }

    @Test func aNeverReadyFindingSurvivesJSONAndOldReportsStillDecode() throws {
        let finding = FeelFinding.neverBecameReady("no content came on screen")
        let back = try JSONDecoder().decode(FeelFinding.self, from: JSONEncoder().encode(finding))
        #expect(back.neverReady)
        let old = try JSONDecoder().decode(FeelFinding.self, from: Data(#"{"what":"x"}"#.utf8))
        #expect(!old.neverReady)
    }
}

@Suite struct ReadyCombineTests {
    @Test func aPoseThatNeverBecameReadyIsNotCountedAsABugWhenPosesAreCombined() {
        let result = FeelResult.judged(check: FeelGenre.insideWindow.rawValue, passing: "clear", failing: { "\($0) covered" },
                                       findings: [.neverBecameReady("no content came on screen in landscape after 120.0 s")])
        #expect(!result.passed)
        #expect(result.summary.hasPrefix("never became ready:"), "\(result.text)")
        #expect(result.detections.isEmpty)
    }

    @Test func aRealBugInAnotherPoseStillLeads() {
        let result = FeelResult.judged(check: FeelGenre.insideWindow.rawValue, passing: "clear", failing: { "\($0) covered" },
                                       findings: [FeelFinding(what: "a line under the head"),
                                                  .neverBecameReady("no content came on screen in landscape")])
        #expect(!result.passed)
        #expect(result.summary == "1 covered; 1 never became ready")
    }
}

@Suite struct ReadyWhyTests {
    @Test func theReasonTheWalkGaveIsKept() {
        let readiness = FeelReadiness(ready: false, waited: 120, looks: 90,
                                      last: FeelReadyLook(content: 0, why: "\"reader.page\" was on screen but held no text or image in the window"))
        let result = FeelReady.neverReady(check: FeelGenre.insideWindow.rawValue, readiness: readiness, what: "reader.page", pose: "closed")
        #expect(result.summary.contains("no content came on screen in \"reader.page\" (\"reader.page\" was on screen but held no text"),
                "\(result.text)")
    }

    @Test func coveredContentScoresOnlyWhatShowsInTheWindow() {
        // A paged book's next column past the side is not content on screen.
        let window = CGRect(x: 0, y: 0, width: 400, height: 800)
        #expect(FeelCover.visible(CGRect(x: 20, y: 100, width: 300, height: 20), in: window))
        #expect(!FeelCover.visible(CGRect(x: 420, y: 100, width: 300, height: 20), in: window))
    }
}

@Suite struct ReadyCostTests {
    @Test func aPoseWithNoTimeLeftStillGetsOneLook() {
        // The poses of one call share one deadline; a later pose that finds it passed looks once and does not pause.
        let clock = FakeClock()
        var pauses = 0
        let late = FeelReady.wait(timeout: 0, every: 0.25, now: { clock.now }, look: { FeelReadyLook(content: 0) },
                                  pause: { pauses += 1; clock.now += $0 })
        #expect(!late.ready)
        #expect(late.looks == 1)
        #expect(pauses == 0)
        let ready = FeelReady.wait(timeout: 0, every: 0.25, now: { clock.now }, look: { FeelReadyLook(content: 2) },
                                   pause: { clock.now += $0 })
        #expect(ready.ready)
    }

    @Test func theLookThatFoundTheScreenReadyIsTheIdleWatchsFirst() {
        // Gatefold times one look with stillWhileIdle(for: 0.001, every: 0): the ready look must not add another.
        let clock = FakeClock(lookTakes: 8)
        var looks = 0
        let first = FeelIdleSample(at: 5, elements: ["head": CGRect(x: 0, y: 0, width: 10, height: 10)], statusBar: true)
        clock.now = 8 // the ready look began at 0 and took 8 s
        let samples = FeelIdle.watch(for: 0.001, every: 0, now: { clock.now }, first: (first, 0),
                                     look: { at in looks += 1; clock.now += clock.lookTakes
                                         return FeelIdleSample(at: at, elements: [:], statusBar: true) },
                                     pause: { clock.now += $0 })
        #expect(looks == 0)
        #expect(samples.count == 1)
        #expect(samples[0].at == 0)
        #expect(samples[0].elements == first.elements)
    }

    @Test func aWatchFromAFirstLookStillTakesItsLeastLooks() {
        let clock = FakeClock()
        let first = FeelIdleSample(at: 0, elements: [:], statusBar: nil)
        let samples = FeelIdle.watch(for: 1, every: 0.25, now: { clock.now }, first: (first, 0),
                                     look: { at in FeelIdleSample(at: at, elements: [:], statusBar: nil) },
                                     pause: { clock.now += $0 })
        #expect(samples.count >= FeelIdle.leastLooks)
        #expect(samples.first?.at == 0)
    }
}
