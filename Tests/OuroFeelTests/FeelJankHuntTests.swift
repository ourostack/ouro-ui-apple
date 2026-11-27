import CoreGraphics
import Foundation
import OuroFeelCore
import Testing

// The checks from Gatefold's jank hunt of 2026-11-27 (ourostack/gatefold#646 to #654).

private let duo = CGRect(x: 0, y: 0, width: 951, height: 669)
private let hinge = CGRect(x: 467, y: 0, width: 17, height: 669)
private let phone = CGRect(x: 0, y: 0, width: 402, height: 874)

private func text(_ key: String, _ frame: CGRect) -> FeelElement { FeelElement(key: key, type: "text", frame: frame) }
private func button(_ key: String, _ frame: CGRect) -> FeelElement { FeelElement(key: key, type: "button", frame: frame) }

@Suite struct FoldTests {
    @Test func aSpreadWithAPageEachSideClearsTheFold() {
        let left = (0..<10).map { text("left \($0)", CGRect(x: 32, y: 40 + CGFloat($0) * 30, width: 400, height: 22)) }
        let right = (0..<10).map { text("right \($0)", CGRect(x: 516, y: 40 + CGFloat($0) * 30, width: 400, height: 22)) }
        let result = FeelFold.check(content: left + right, fold: hinge, window: duo, spread: true, posture: "book")
        #expect(result.passed, "\(result.text)")
        #expect(result.check == FeelCheck.clearsTheFold.name)
    }

    @Test func oneColumnAcrossTheFoldFails() {
        // As Gatefold#646: one column of text straight across the hinge.
        let lines = (0..<6).map { text("line \($0)", CGRect(x: 32, y: 40 + CGFloat($0) * 30, width: 887, height: 22)) }
        let result = FeelFold.check(content: lines, fold: hinge, window: duo, spread: true, posture: "half-open like a book")
        #expect(!result.passed)
        #expect(result.detections.count == 7)
        #expect(result.detections[0].what == "text \"line 0\" runs across the fold in half-open like a book: 435 pt of it on one side and 435 pt on the other")
        #expect(result.detections.last?.what.contains("the leading side of the fold has no page") == true)
    }

    @Test func aSeamIsCrossedOnlyByWhatReachesPastIt() {
        let seam = CGRect(x: 475, y: 0, width: 0, height: 669)
        let edge = text("edge", CGRect(x: 32, y: 40, width: 443.5, height: 22))
        #expect(FeelFold.check(content: [edge], fold: seam, window: duo, posture: "flat").passed)
        let across = text("across", CGRect(x: 32, y: 40, width: 460, height: 22))
        #expect(!FeelFold.check(content: [across], fold: seam, window: duo, posture: "flat").passed)
    }

    @Test func contentThatReachesUnderTheFoldSaysSo() {
        // A column whose edge runs under the hinge but not past it is under the fold, not across it.
        let under = text("edge", CGRect(x: 32, y: 40, width: 445, height: 22))
        let result = FeelFold.check(content: [under], fold: hinge, window: duo, posture: "book")
        #expect(result.detections.map(\.what) == ["text \"edge\" reaches under the fold in book: 10 pt of it lies under the fold"])
    }

    @Test func aFoldAcrossIsJudgedForCrossingOnly() {
        let tabletop = CGRect(x: 0, y: 326, width: 951, height: 17)
        let top = text("top", CGRect(x: 32, y: 40, width: 887, height: 22))
        let result = FeelFold.check(content: [top], fold: tabletop, window: duo, spread: true, posture: "tabletop")
        #expect(result.passed, "\(result.text)")
        #expect(result.findings.contains { $0.note && $0.what.contains("only crossing was judged") })
        let panel = text("panel", CGRect(x: 0, y: 300, width: 951, height: 100))
        #expect(!FeelFold.check(content: [panel], fold: tabletop, window: duo, posture: "tabletop").passed)
    }

    @Test func noFoldOrNoContentCannotBeChecked() {
        let none = FeelFold.check(content: [text("a", CGRect(x: 0, y: 0, width: 10, height: 10))], fold: nil, window: duo, posture: "flat")
        #expect(!none.passed)
        #expect(none.detections.isEmpty)
        #expect(none.summary.hasPrefix("could not check: no fold"))
        let empty = FeelFold.check(content: [], fold: hinge, window: duo, posture: "flat")
        #expect(!empty.passed)
        #expect(empty.detections.isEmpty)
    }
}

@Suite struct RelayoutTests {
    private let page = text("reader.page", CGRect(x: 0, y: 0, width: 874, height: 402))
    private let close = button("reader.close", CGRect(x: 810, y: 20, width: 44, height: 44))

    @Test func theSameLayoutAsAFreshLaunchPasses() {
        let result = FeelRelayout.compare(turned: [page, close], fresh: [close, page], turnedWindow: CGRect(x: 0, y: 0, width: 874, height: 402),
                                          freshWindow: CGRect(x: 0, y: 0, width: 874, height: 402), change: "turning to landscape", waited: 3)
        #expect(result.passed, "\(result.text)")
        #expect(result.check == FeelCheck.laysOutFresh.name)
    }

    @Test func aPanelThatLingersFails() {
        // As Gatefold#647: the tabletop panel stays after the Duo opens flat; the page is cut to its old height.
        let panel = FeelElement(key: "reader.panel", type: "other", frame: CGRect(x: 0, y: 335, width: 951, height: 334))
        let cut = text("reader.page", CGRect(x: 0, y: 0, width: 951, height: 319))
        let full = text("reader.page", CGRect(x: 0, y: 0, width: 951, height: 669))
        let result = FeelRelayout.compare(turned: [cut, panel], fresh: [full], turnedWindow: duo, freshWindow: duo,
                                          change: "opening flat", waited: 3)
        #expect(!result.passed)
        #expect(result.detections.map(\.what) == [
            "text \"reader.page\" is at (0, 0, 951×319) 3.0 s after opening flat, but at (0, 0, 951×669) on a fresh launch",
            "other \"reader.panel\" is still on screen 3.0 s after opening flat, but a fresh launch in that posture has none: it lingers from the layout before",
        ])
    }

    @Test func somethingMissingOrAMovedCopyFails() {
        let missing = FeelRelayout.compare(turned: [page], fresh: [page, close], turnedWindow: phone, freshWindow: phone,
                                           change: "turning", waited: 3)
        #expect(missing.detections.count == 1)
        #expect(missing.detections[0].what.contains("is on screen on a fresh launch, but not 3.0 s after turning"))
        let twice = FeelRelayout.compare(turned: [page, page], fresh: [page], turnedWindow: phone, freshWindow: phone,
                                         change: "turning", waited: 3)
        #expect(twice.detections.count == 1)
        // A point or two is rounding.
        var nudged = close
        nudged.frame.origin.x += 1.5
        #expect(FeelRelayout.compare(turned: [page, nudged], fresh: [page, close], turnedWindow: phone, freshWindow: phone,
                                     change: "turning", waited: 3).passed)
    }

    @Test func aTurnThatKeptTheWindowsShapeCannotBeChecked() {
        // A portrait-only app, or a platform with nothing to turn: the window never changed, so nothing was tried.
        let result = FeelRelayout.compare(turned: [page], fresh: [page], turnedWindow: phone, freshWindow: phone,
                                          change: "turning to landscape", waited: 3, beforeWindow: phone)
        #expect(!result.passed)
        #expect(result.detections.isEmpty)
        #expect(result.summary.contains("kept its shape"), "\(result.text)")
        // A change the test names (a fold) may keep the window's size, and is judged.
        #expect(FeelRelayout.compare(turned: [page], fresh: [page], turnedWindow: phone, freshWindow: phone,
                                     change: "opening flat", waited: 3).passed)
    }

    @Test func aLaunchInAnotherPostureOrWithNothingCannotBeChecked() {
        let other = FeelRelayout.compare(turned: [page], fresh: [page], turnedWindow: CGRect(x: 0, y: 0, width: 874, height: 402),
                                         freshWindow: phone, change: "turning", waited: 3)
        #expect(!other.passed)
        #expect(other.detections.isEmpty)
        let empty = FeelRelayout.compare(turned: [page], fresh: [], turnedWindow: phone, freshWindow: phone, change: "turning", waited: 3)
        #expect(!empty.passed)
        #expect(empty.detections.isEmpty)
    }
}

@Suite struct TurnPlaceTests {
    private let book = (0..<400).map { "word\($0)" }
    private func at(_ start: Int, _ count: Int = 60) -> [String] { FeelTurnPlace.words(book[start..<(start + count)].joined(separator: " ")) }

    @Test func wordsAreFingerprintsWithoutPunctuationOrCase() {
        let words = FeelTurnPlace.words("Call me Ishmael. Some years ago,")
        #expect(words.count == 6)
        #expect(words == FeelTurnPlace.words("call ME ishmael some years ago"))
        #expect(!words.contains("ishmael"))
        #expect(words.allSatisfy { $0.count == 8 })
    }

    @Test func aReflowWithinALinePasses() {
        // Landscape's longer lines start the screen a few words earlier.
        let result = FeelTurnPlace.judge([FeelTurnRead(turn: "landscape", before: at(100), after: at(96), line: 8),
                                          FeelTurnRead(turn: "portrait", before: at(96), after: at(103), line: 8, scrolledFirst: true)])
        #expect(result.passed, "\(result.text)")
        #expect(result.measures["most words moved"] == 7)
        #expect(result.check == FeelCheck.placeSurvivesTurns.name)
    }

    @Test func aTurnBackToTheLastTurnsPlaceFails() {
        // As Gatefold#650: scrolled on to word 200, the turn lands back at word 100, more than a screen away.
        let lost = FeelTurnPlace.judge([FeelTurnRead(turn: "landscape", before: at(200), after: at(100), line: 8, scrolledFirst: true)])
        #expect(!lost.passed)
        #expect(lost.detections.map(\.what) == ["turning to landscape, after a scroll, lost the place: the first words after it are nowhere in the 60 words on screen before it, nor are those in the 60 after"])
        // Within the screen, but more than a line: it says how far.
        let moved = FeelTurnPlace.judge([FeelTurnRead(turn: "landscape", before: at(100), after: at(130), line: 8)])
        #expect(moved.detections.map(\.what) == ["turning to landscape moved the place 30 words on, more than a line (8 words)"])
        let back = FeelTurnPlace.judge([FeelTurnRead(turn: "landscape", before: at(130), after: at(100), line: 8)])
        #expect(back.detections.first?.what.contains("30 words back") == true)
    }

    @Test func aTurnThatKeptTheWindowsShapeCannotBeChecked() {
        let result = FeelTurnPlace.judge([FeelTurnRead(turn: "landscape", before: at(100), after: at(100), line: 8, shapeChanged: false)])
        #expect(!result.passed)
        #expect(result.detections.isEmpty)
        #expect(result.summary.contains("kept its shape"), "\(result.text)")
    }

    @Test func aScrollThatMovedNothingCannotBeChecked() {
        let result = FeelTurnPlace.judge([FeelTurnRead(turn: "landscape", before: at(100), after: at(100), line: 8,
                                                       scrolledFirst: true, scrollMoved: false)])
        #expect(!result.passed)
        #expect(result.detections.isEmpty)
        #expect(result.summary.contains("moved nothing"), "\(result.text)")
    }

    @Test func aPageKeptAtTheSafeAreaTopPasses() {
        // UIKit's adjustedContentInset or a TextKit reader keeps the place below the bars. Read from the window's top,
        // portrait counts three lines under the status and navigation bars that landscape has no room for; read from
        // below the bars, both start at the same words.
        let result = FeelTurnPlace.judge([FeelTurnRead(turn: "landscape", before: at(100), after: at(116), line: 8,
                                                       beforeBelowBars: at(124), afterBelowBars: at(124))])
        #expect(result.passed, "\(result.text)")
        #expect(result.measures["most words moved"] == 0)
    }

    @Test func aPageKeptAtTheBoundsTopPasses() {
        // SwiftUI's scrollPosition(anchor: .top) keeps the place at the scroll view's top, under the bars.
        let result = FeelTurnPlace.judge([FeelTurnRead(turn: "landscape", before: at(100), after: at(100), line: 8,
                                                       beforeBelowBars: at(124), afterBelowBars: at(108))])
        #expect(result.passed, "\(result.text)")
        // A lost place is lost from either top edge.
        let lost = FeelTurnPlace.judge([FeelTurnRead(turn: "landscape", before: at(200), after: at(100), line: 8, scrolledFirst: true,
                                                     beforeBelowBars: at(224), afterBelowBars: at(108))])
        #expect(!lost.passed)
        #expect(lost.detections.count == 1)
    }

    @Test func theReadingIsTakenFromTheTopAndFromBelowTheBars() {
        let window = CGRect(x: 0, y: 0, width: 402, height: 874)
        let texts: [(frame: CGRect, text: String)] = (0..<10).map { (CGRect(x: 24, y: CGFloat($0) * 40, width: 300, height: 32), "line \($0)") }
        let both = FeelTurnPlace.readings(texts, in: window, below: 103)
        #expect(both.fromTop.first == "line 0")
        // The bars end at 103 pt; line 2 (80 to 112 pt) shows 9 pt below them, so that reading starts there.
        #expect(both.belowBars.first == "line 2")
        #expect(FeelTurnPlace.readings(texts, in: window, below: 0).belowBars == both.fromTop)
    }

    @Test func theReadingStartsAtTheViewportsTopAndCountsTextPartlyShown() {
        // The same top edge in every orientation: a line partly under the status bar, or a paragraph that started
        // above the screen, is where the reading starts; one wholly above or below the viewport is not read.
        let viewport = CGRect(x: 0, y: 0, width: 402, height: 874)
        let texts: [(frame: CGRect, text: String)] = [
            (CGRect(x: 24, y: 20, width: 300, height: 32), "second"),
            (CGRect(x: 24, y: -100, width: 300, height: 112), "paragraph"),
            (CGRect(x: 24, y: -40, width: 300, height: 32), "gone above"),
            (CGRect(x: 24, y: 873.5, width: 300, height: 32), "a sliver below"),
            (CGRect(x: 24, y: 900, width: 300, height: 32), "gone below"),
            (CGRect(x: 24, y: 860, width: 300, height: 32), "last"),
        ]
        #expect(FeelTurnPlace.reading(texts, in: viewport) == ["paragraph", "second", "last"])
    }

    @Test func noWordsCannotBeChecked() {
        let result = FeelTurnPlace.judge([FeelTurnRead(turn: "landscape", before: [], after: at(0), line: 8)])
        #expect(!result.passed)
        #expect(result.detections.isEmpty)
        #expect(!FeelTurnPlace.judge([]).passed)
    }
}

@Suite struct JumpTests {
    @Test func aJumpThatLandsInItsBudgetPasses() {
        let result = FeelJump.judge(FeelJumpTrail(intent: "Contents to Chapter 3", landedAfter: 0.4, budget: 2, within: 10))
        #expect(result.passed, "\(result.text)")
        #expect(result.check == FeelCheck.landsOnItsOwn.name)
        #expect(result.summary == "Contents to Chapter 3 landed in 0.4 s, within its 2.0 s budget, with no further input")
    }

    @Test func aSlowJumpFails() {
        // As Gatefold#651 on the iPad: the old page held for 4.5 s.
        let result = FeelJump.judge(FeelJumpTrail(intent: "Contents to Chapter 3", landedAfter: 4.5, budget: 2, within: 10))
        #expect(result.detections.map(\.what) == ["Contents to Chapter 3 took 4.5 s to land, past its 2.0 s budget"])
    }

    @Test func aJumpThatWaitsForATapFails() {
        // As Gatefold#651 on the Duo's cover: it landed only at the next tap.
        let result = FeelJump.judge(FeelJumpTrail(intent: "search to \"Darcy\"", budget: 2, within: 10, nudged: true, landedAfterNudge: 0.3))
        #expect(!result.passed)
        #expect(result.detections.count == 1)
        #expect(result.detections[0].what.contains("landed only after a tap on the middle of the window"))
    }

    @Test func aJumpThatNeverLandsOrWasAlreadyThereCannotBeChecked() {
        let never = FeelJump.judge(FeelJumpTrail(intent: "the scrubber to the end", budget: 2, within: 10, nudged: true))
        #expect(!never.passed)
        #expect(never.detections.isEmpty)
        let there = FeelJump.judge(FeelJumpTrail(intent: "x", landedAfter: 0, budget: 2, within: 10, landedBefore: true))
        #expect(!there.passed)
        #expect(there.detections.isEmpty)
    }
}

@Suite struct ClearViewTests {
    private let pill = button("Back to where you were", CGRect(x: 100, y: 760, width: 202, height: 44))

    @Test func aHitInClearViewPasses() {
        let hit = text("hit", CGRect(x: 24, y: 120, width: 354, height: 22))
        let result = FeelClearView.check(target: hit, chrome: [pill], window: phone, expected: [pill.key], intent: "the search")
        #expect(result.passed, "\(result.text)")
        #expect(result.check == FeelCheck.landsInClearView.name)
    }

    @Test func aHitUnderThePillFails() {
        // As Gatefold#652: the hit lands on the second-to-last line, under the pill.
        let hit = text("hit", CGRect(x: 24, y: 770, width: 354, height: 22))
        let result = FeelClearView.check(target: hit, chrome: [pill], window: phone, intent: "the search")
        #expect(result.detections.map(\.what) == ["text \"hit\" landed under button \"Back to where you were\": 202×22 pt of it is covered after the search"])
    }

    @Test func aHitCutOffByItsViewportFails() {
        let hit = text("hit", CGRect(x: 24, y: 830, width: 354, height: 22))
        let viewport = CGRect(x: 0, y: 62, width: 402, height: 778)
        let result = FeelClearView.check(target: hit, chrome: [], window: phone, viewport: viewport, intent: "the search")
        #expect(result.detections.map(\.what) == ["text \"hit\" landed cut off: it runs 12 pt past the bottom of its viewport after the search"])
    }

    @Test func chromeThatHasGoneCoversNothingAndAMissingTargetCannotBeChecked() {
        let hit = text("hit", CGRect(x: 24, y: 120, width: 354, height: 22))
        let gone = FeelClearView.check(target: hit, chrome: [], window: phone, expected: ["pill"], intent: "the search")
        #expect(gone.passed)
        #expect(gone.findings.contains { $0.note })
        let none = FeelClearView.check(target: nil, chrome: [pill], window: phone, intent: "the search")
        #expect(!none.passed)
        #expect(none.detections.isEmpty)
    }
}

@Suite struct NoticeTests {
    private let notice = FeelElement(key: "notice", type: "other", frame: CGRect(x: 16, y: 62, width: 370, height: 56))
    private let first = text("words 1", CGRect(x: 24, y: 80, width: 354, height: 22))
    private let second = text("words 2", CGRect(x: 24, y: 140, width: 354, height: 22))

    @Test func aNoticeThatStaysOverTheTextFails() {
        // As Gatefold#654: over the first line, and still over the next page's first line after a turn.
        let result = FeelNotice.check(notice: notice, first: [first, second], later: notice, laterContent: [first, second],
                                      window: phone, then: "a page turn")
        #expect(!result.passed)
        #expect(result.check == FeelCheck.noticeGivesWay.name)
        #expect(result.detections.map(\.what) == ["other \"notice\" still covers text \"words 1\" after a page turn, as it covered one when it first showed"])
    }

    @Test func aNoticeThatGoesOrMakesRoomPasses() {
        let gone = FeelNotice.check(notice: notice, first: [first], later: nil, laterContent: [first], window: phone, then: "5.0 s")
        #expect(gone.passed, "\(gone.text)")
        #expect(gone.summary == "\"notice\" was gone after 5.0 s")
        let inset = text("words 1", CGRect(x: 24, y: 130, width: 354, height: 22))
        let room = FeelNotice.check(notice: notice, first: [inset], later: notice, laterContent: [inset], window: phone, then: "5.0 s")
        #expect(room.passed, "\(room.text)")
    }

    @Test func aNoticeThatNeverShowedCannotBeChecked() {
        let result = FeelNotice.check(notice: nil, first: [], later: nil, laterContent: [], window: phone, then: "5.0 s")
        #expect(!result.passed)
        #expect(result.detections.isEmpty)
    }
}

@Suite struct TargetTests {
    @Test func targetsOf44PointsPass() {
        let ok = [button("close", CGRect(x: 340, y: 62, width: 44, height: 44)),
                  button("rounded", CGRect(x: 20, y: 62, width: 43.995, height: 120))]
        let result = FeelTargets.check(ok, window: phone, minimum: 44, pose: "portrait")
        #expect(result.passed, "\(result.text)")
        #expect(result.check == FeelCheck.targetsBigEnough.name)
    }

    @Test func aSmallCloseButtonFailsAsInference() {
        // As the Duo dump in the jank hunt: reader.close was 14 by 14.
        let result = FeelTargets.check([button("reader.close", CGRect(x: 900, y: 20, width: 14, height: 14))], window: duo,
                                       minimum: 44, pose: "open")
        #expect(result.detections.map(\.what) == ["button \"reader.close\" is 14×14 pt, under 44 pt on a side, in open"])
        #expect(result.detections[0].inferred)
    }

    @Test func theMinimumIsThePlatformsDefaultControlSize() {
        // Apple's HIG, Accessibility, "Offer sufficiently sized controls": the default control size per platform.
        #if os(macOS) || targetEnvironment(macCatalyst)
        #expect(FeelTargets.minimum == 28)
        #elseif os(visionOS)
        #expect(FeelTargets.minimum == 60)
        #elseif os(tvOS)
        #expect(FeelTargets.minimum == 66)
        #else
        #expect(FeelTargets.minimum == 44)
        #endif
    }

    @Test func offScreenTargetsAreNotJudgedAndNoTargetsCannotBeChecked() {
        let off = button("off", CGRect(x: 500, y: 62, width: 10, height: 10))
        let result = FeelTargets.check([off], window: phone, pose: "portrait")
        #expect(!result.passed)
        #expect(result.detections.isEmpty)
    }
}

@Suite struct BeforeAfterOrVeilTests {
    private func pic(_ t: Double, _ v: UInt8, w: Int = 4, h: Int = 4, stripe: UInt8? = nil) -> FeelScreenFrame {
        var gray = [UInt8](repeating: v, count: w * h)
        if let stripe { for i in 0..<w { gray[i] = stripe } }  // a line of "text", so it is no veil
        return FeelScreenFrame(t: t, width: w, height: h, gray: gray)
    }

    /// A 4×4 page with its line of "text" on `row`.
    private func page(_ t: Double, _ v: UInt8, row: Int) -> FeelScreenFrame {
        var gray = [UInt8](repeating: v, count: 16)
        for i in 0..<4 { gray[row * 4 + i] = 20 }
        return FeelScreenFrame(t: t, width: 4, height: 4, gray: gray)
    }

    /// The film's last picture again, shot later: the screen stayed on the after.
    private func later(_ f: FeelScreenFilm) -> FeelScreenFrame? { f.frames.last }

    private func film(_ values: [(UInt8, Int, Int)], cover: FeelScreenFrame) -> FeelScreenFilm {
        var f = FeelScreenFilm(frames: values.enumerated().map { pic(Double($0.offset) / 10, $0.element.0, w: $0.element.1, h: $0.element.2, stripe: 20) })
        f.byReads = true
        f.cover = cover
        return f
    }

    @Test func beforeThenAfterPasses() {
        let before = pic(0, 200, stripe: 20)
        let f = film([(200, 4, 4), (200, 4, 4), (100, 4, 4), (100, 4, 4), (100, 4, 4)], cover: before)
        let result = f.beforeAfterOrVeil(later: later(f))
        #expect(result.passed, "\(result.text)")
        #expect(result.check == FeelCheck.beforeAfterOrVeil.name)
    }

    @Test func aVeilBetweenPasses() {
        let before = pic(0, 200, stripe: 20)
        var f = film([(200, 4, 4), (200, 4, 4), (100, 4, 4), (100, 4, 4)], cover: before)
        // A plain grey veil, with the status band painted black.
        let veil = FeelScreenFrame(t: 0.15, width: 4, height: 4, gray: [0, 0, 0, 0] + [UInt8](repeating: 128, count: 12))
        f.frames.insert(contentsOf: [veil, veil, veil], at: 2)
        #expect(f.beforeAfterOrVeil(later: later(f)).passed, "\(f.beforeAfterOrVeil(later: later(f)).text)")
        #expect(FeelScreenFilm.isVeil(veil))
        #expect(!FeelScreenFilm.isVeil(pic(0, 200, stripe: 20)))
    }

    @Test func anotherPageOnTheWayFails() {
        // A page that is neither the old one nor the target, held for a moment (as Gatefold#653, there for 0.2 s).
        let before = page(0, 200, row: 0)
        var f = FeelScreenFilm(frames: [page(0, 200, row: 0), page(0.1, 200, row: 0), page(0.2, 150, row: 2), page(0.3, 150, row: 2),
                                        page(0.4, 100, row: 1), page(0.5, 100, row: 1)])
        f.byReads = true
        f.cover = before
        let result = f.beforeAfterOrVeil(later: later(f))
        #expect(!result.passed)
        #expect(result.detections.count == 1)
        #expect(result.detections[0].what.hasPrefix("the screen rested on a state that is neither the before, the after nor a veil, for 2 samples from 0.20 s to 0.30 s"))
        // The app's own loading picture, passed as a veil, is allowed.
        let declared = f.beforeAfterOrVeil(veils: [page(0, 150, row: 2)], later: later(f))
        #expect(declared.passed, "\(declared.text)")
    }

    @Test func aDimmedOrWashedCopyOfTheBeforeIsAVeil() {
        // The old page dimmed while the jump loads (as Gatefold#651's greyed page), or washed with a light material.
        let before = FeelScreenFrame(t: 0, width: 4, height: 4, gray: [20, 60, 100, 140, 180, 220, 200, 200, 200, 200, 40, 200, 200, 200, 200, 200])
        let dimmed = FeelScreenFrame(t: 0, width: 4, height: 4, gray: before.gray.map { UInt8(Double($0) * 0.5) })
        let washed = FeelScreenFrame(t: 0, width: 4, height: 4, gray: before.gray.map { UInt8(Double($0) * 0.4 + 150) })
        #expect(FeelScreenFilm.isDimmed(dimmed, of: before))
        #expect(FeelScreenFilm.isDimmed(washed, of: before))
        // Another page is no dimmed copy, nor is the before itself.
        #expect(!FeelScreenFilm.isDimmed(page(0, 100, row: 2), of: before))
        #expect(!FeelScreenFilm.isDimmed(before, of: before))
        var f = FeelScreenFilm(frames: [before, before, dimmed, dimmed, dimmed, page(0.5, 100, row: 1), page(0.6, 100, row: 1)])
        f.byReads = true
        f.cover = before
        #expect(f.beforeAfterOrVeil(later: later(f)).passed, "\(f.beforeAfterOrVeil(later: later(f)).text)")
    }

    @Test func aDimmedDifferentPageIsNoVeil() {
        // Two pages with the same layout differ only in their text's texture at a film's width; dimming the other one
        // shrinks that difference, which must be measured on the before's scale, not the dimmed one.
        let before = FeelScreenFrame(t: 0, width: 4, height: 4, gray: [20, 60, 100, 140, 180, 220, 200, 200, 200, 200, 40, 200, 200, 200, 200, 200])
        let other = before.gray.enumerated().map { i, v in i >= 6 && i != 10 ? (i % 2 == 0 ? v + 4 : v - 4) : v }
        let dimmed = FeelScreenFrame(t: 0, width: 4, height: 4, gray: other.map { UInt8(Double($0) * 0.4) })
        #expect(!FeelScreenFilm.isDimmed(dimmed, of: before))
    }

    @Test func aWrongPictureThatOutlastsTheFilmCannotBeChecked() {
        // The film ended on a wrong page that was still up; a later picture shows the real after.
        let before = page(0, 200, row: 0)
        var f = FeelScreenFilm(frames: [before, before, page(0.2, 150, row: 2), page(0.3, 150, row: 2)])
        f.byReads = true
        f.cover = before
        let moved = f.beforeAfterOrVeil(later: page(2, 100, row: 1))
        #expect(!moved.passed)
        #expect(moved.detections.isEmpty)
        #expect(moved.summary.contains("changed after the film ended"), "\(moved.text)")
        let none = f.beforeAfterOrVeil()
        #expect(!none.passed)
        #expect(none.detections.isEmpty)
        #expect(none.summary.contains("no later picture"), "\(none.text)")
    }

    @Test func aStretchedPictureInTheNewShapeFails() {
        // As Gatefold#649: the turn shows the old page stretched to the new shape before the new layout lands.
        let before = pic(0, 200, w: 4, h: 8, stripe: 20)
        let f = film([(200, 4, 8), (200, 4, 8), (180, 8, 4), (180, 8, 4), (100, 8, 4), (100, 8, 4), (100, 8, 4)], cover: before)
        let result = f.beforeAfterOrVeil(later: later(f))
        #expect(!result.passed, "\(result.text)")
        #expect(result.detections.count == 1)
        #expect(result.detections[0].what.contains("another shape than the before"))
    }

    @Test func noCoverOrNoEndCannotBeChecked() {
        var bare = film([(200, 4, 4), (200, 4, 4)], cover: pic(0, 200))
        bare.cover = nil
        #expect(!bare.beforeAfterOrVeil().passed)
        #expect(bare.beforeAfterOrVeil().detections.isEmpty)
        let still = film([(200, 4, 4), (200, 4, 4), (100, 4, 4), (150, 4, 4)], cover: pic(0, 200, stripe: 20))
        let moving = still.beforeAfterOrVeil(later: later(still))
        #expect(!moving.passed)
        #expect(moving.detections.isEmpty)
    }
}
