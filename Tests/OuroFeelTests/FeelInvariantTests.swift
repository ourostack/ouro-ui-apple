import CoreGraphics
import Foundation
import OuroFeelCore
import Testing

private let phone = CGRect(x: 0, y: 0, width: 402, height: 874)
private let page = CGRect(x: 0, y: 62, width: 402, height: 778)

private func text(_ key: String, _ frame: CGRect) -> FeelElement { FeelElement(key: key, type: "text", frame: frame) }

@Suite struct ViewportTests {
    private func reader(_ content: [FeelElement], scrolls: FeelAxes = .vertical, inferred: Bool = false) -> FeelViewportRead {
        FeelViewportRead(key: "reader.page", kind: "scroll view", frame: page, scrolls: scrolls, inferred: inferred, content: content)
    }

    @Test func aColumnThatFitsItsWidthHolds() {
        // Lines run far below the page (it scrolls that way) but never past its sides.
        let lines = (0..<40).map { text("line \($0)", CGRect(x: 24, y: 80 + CGFloat($0) * 30, width: 354, height: 22)) }
        let result = FeelViewport.check([reader(lines)], drags: [], pose: "portrait")
        #expect(result.passed, "\(result.text)")
        #expect(result.check == FeelCheck.viewportHolds.name)
    }

    @Test func aLineWiderThanAPageThatScrollsUpAndDownFails() {
        // As Gatefold's page: one line runs past the trailing side, so the page pans sideways.
        let lines = [text("line 1", CGRect(x: 24, y: 80, width: 354, height: 22)),
                     text("line 2", CGRect(x: 24, y: 110, width: 520, height: 22)),
                     text("line 3", CGRect(x: 24, y: 2_000, width: 354, height: 22))]
        let result = FeelViewport.check([reader(lines)], drags: [], pose: "portrait")
        #expect(!result.passed)
        #expect(result.detections.count == 1)
        #expect(result.detections[0].what.contains("\"line 2\" runs 142 pt past the trailing side of scroll view \"reader.page\""))
        // Running far past the bottom is how it scrolls, so it is not judged.
        #expect(!result.text.contains("past the bottom"))
    }

    @Test func anImageWiderThanItsPageIsLeftToTheDrag() {
        // A cover filled to its frame and cropped reads wider than the page; only a drag that pans it fails.
        let cover = FeelElement(key: "recipe.cover", type: "image", frame: CGRect(x: -135, y: 62, width: 672, height: 300))
        let line = text("line 1", CGRect(x: 24, y: 380, width: 354, height: 22))
        #expect(FeelViewport.check([reader([cover, line])], drags: [], pose: "p").passed)
        // Past one side only, it is cut off.
        let shifted = FeelElement(key: "page.image", type: "image", frame: CGRect(x: -60, y: 62, width: 462, height: 300))
        let cut = FeelViewport.check([reader([shifted, line])], drags: [], pose: "p")
        #expect(cut.detections.count == 1)
        #expect(cut.detections[0].what.contains("runs 60 pt past the leading side"))
    }

    @Test func aPagerMayRunPastItsSidesButNotItsBottom() {
        let pages = [text("page 1", CGRect(x: 0, y: 62, width: 402, height: 778)),
                     text("page 2", CGRect(x: 402, y: 62, width: 402, height: 778))]
        #expect(FeelViewport.check([reader(pages, scrolls: .horizontal)], drags: [], pose: "p").passed)
        let tall = pages + [text("footnote", CGRect(x: 0, y: 800, width: 402, height: 80))]
        let result = FeelViewport.check([reader(tall, scrolls: .horizontal)], drags: [], pose: "p")
        #expect(result.detections.count == 1)
        #expect(result.detections[0].what.contains("past the bottom"))
    }

    @Test func aDragThatMovesTheContentOnAFixedAxisFails() {
        let start: [String: CGRect] = ["line 1": CGRect(x: 24, y: 80, width: 354, height: 22)]
        let stuck = FeelDrag(viewport: "reader.page", axis: .horizontal, before: start,
                             during: [["line 1": start["line 1"]!.offsetBy(dx: -60, dy: 0)]],
                             after: ["line 1": start["line 1"]!.offsetBy(dx: -48, dy: 0)])
        let viewport = reader([text("line 1", start["line 1"]!)])
        let result = FeelViewport.check([viewport], drags: [stuck], pose: "portrait")
        #expect(!result.passed)
        #expect(result.detections[0].what.contains("moved its content 60 pt sideways and left it 48 pt off"))

        let bounce = FeelDrag(viewport: "reader.page", axis: .horizontal, before: start,
                              during: [["line 1": start["line 1"]!.offsetBy(dx: -30, dy: 0)]], after: start)
        let sprang = FeelViewport.check([viewport], drags: [bounce], pose: "portrait")
        #expect(sprang.detections[0].what.contains("sprang back"))
    }

    @Test func aDragThatHoldsStillPassesAndMovementAlongTheOtherAxisIsNotJudged() {
        let start: [String: CGRect] = ["line 1": CGRect(x: 24, y: 80, width: 354, height: 22)]
        let drag = FeelDrag(viewport: "reader.page", axis: .horizontal, before: start,
                            during: [["line 1": start["line 1"]!.offsetBy(dx: 1, dy: -40)]],
                            after: ["line 1": start["line 1"]!.offsetBy(dx: 0, dy: -12)])
        let result = FeelViewport.check([reader([text("line 1", start["line 1"]!)])], drags: [drag], pose: "p")
        #expect(result.passed, "\(result.text)")
        #expect(result.measures["drags"] == 1)
    }

    @Test func aTextWhoseWordsChangeDuringADragHasNotPanned() {
        // Its trailing edge moves as its words change; its leading edge holds, so the content did not move.
        let start: [String: CGRect] = ["row": CGRect(x: 24, y: 80, width: 180, height: 22)]
        let grew = FeelDrag(viewport: "reader.page", axis: .horizontal, before: start,
                            during: [["row": CGRect(x: 24, y: 80, width: 264, height: 22)]],
                            after: ["row": CGRect(x: 24, y: 80, width: 264, height: 22)])
        let result = FeelViewport.check([reader([text("row", start["row"]!)])], drags: [grew], pose: "p")
        #expect(result.passed, "\(result.text)")
    }

    @Test func aDragThatChangesTheScreenIsAGestureNotAPan() {
        let start: [String: CGRect] = ["a": CGRect(x: 24, y: 80, width: 100, height: 22), "b": CGRect(x: 24, y: 110, width: 100, height: 22)]
        let drag = FeelDrag(viewport: "reader.page", axis: .horizontal, before: start, during: [], after: [:])
        let result = FeelViewport.check([reader([text("a", start["a"]!)], inferred: true)], drags: [drag], pose: "p")
        #expect(result.passed, "\(result.text)")
        #expect(result.findings.contains { $0.note && $0.what.contains("page turn") })
    }

    @Test func aGuessedAxisMarksItsFindingsAsInference() {
        let lines = [text("wide", CGRect(x: 24, y: 80, width: 600, height: 22)), text("low", CGRect(x: 24, y: 2_000, width: 100, height: 22))]
        let result = FeelViewport.check([reader(lines, inferred: true)], drags: [], pose: "p")
        #expect(!result.detections.isEmpty && !result.detections.contains { !$0.inferred })
        #expect(result.findings.contains { $0.note && $0.what.contains("declare a pager or carousel") })
    }

    @Test func aPageNoDragCouldCrossIsSaid() {
        let lines = [text("line 1", CGRect(x: 24, y: 80, width: 354, height: 22))]
        let result = FeelViewport.check([reader(lines)], drags: [], undragged: ["reader.page": [.horizontal]], pose: "p")
        #expect(result.summary.hasPrefix("could not check"), "\(result.text)")
        #expect(result.findings.contains { $0.note && $0.what.contains("no drag sideways could cross scroll view \"reader.page\"") })
    }

    @Test func nothingOnScreenCouldNotBeChecked() {
        #expect(FeelViewport.check([reader([])], drags: [], pose: "p").summary.hasPrefix("could not check"))
    }

    @Test func theAxesAreGuessedFromTheContentsShape() {
        let carousel = CGRect(x: 0, y: 300, width: 402, height: 220)
        let covers = [CGRect(x: 16, y: 300, width: 150, height: 220), CGRect(x: 500, y: 300, width: 150, height: 220)]
        #expect(FeelViewport.guessAxes(kind: "scroll view", frame: carousel, content: covers) == .horizontal)
        let wideAndLong = [CGRect(x: 0, y: 80, width: 600, height: 22), CGRect(x: 0, y: 2_000, width: 100, height: 22)]
        #expect(FeelViewport.guessAxes(kind: "scroll view", frame: page, content: wideAndLong) == .vertical)
        #expect(FeelViewport.guessAxes(kind: "web view", frame: carousel, content: covers) == .vertical)
        // A short page with one line wider than it is no carousel: a line is never a card, so it scrolls up and down,
        // and the line is judged as running past its side.
        let shortWide = [CGRect(x: 24, y: 80, width: 354, height: 22), CGRect(x: 24, y: 110, width: 520, height: 22)]
        #expect(FeelViewport.guessAxes(kind: "scroll view", frame: page, content: shortWide) == .vertical)
        // A carousel in a list: the list scrolls the way the carousel doesn't, so nothing is fixed at that point.
        #expect(FeelViewport.fixedAt([.vertical, .horizontal]).isEmpty)
        #expect(FeelViewport.fixedAt([.vertical]) == .horizontal)
        #expect(FeelViewport.fixedAt([]) == .both)
    }
}

@Suite struct FloatTests {
    private let pageView = FeelElement(key: "reader.page", type: "scroll view", frame: page)
    private let lastLine = text("words 3f2a", CGRect(x: 24, y: 740, width: 354, height: 22))

    @Test func aPillOverThePageWhoseEndComesClearPasses() {
        let pill = FeelElement(key: "reader.restart", type: "button", frame: CGRect(x: 120, y: 780, width: 162, height: 44))
        let result = FeelFloat.check(viewport: pageView, chrome: [pill], end: [lastLine], endViewport: page, endChrome: [pill],
                                     window: phone, reachedEnd: true, expected: ["reader.restart"], pose: "portrait")
        #expect(result.passed, "\(result.text)")
        #expect(result.check == FeelCheck.chromeFloats.name)
    }

    @Test func aPillThatShrinksThePageFails() {
        // As Gatefold's: the page stops above the pill instead of running under it.
        let shrunk = FeelElement(key: "reader.page", type: "scroll view", frame: CGRect(x: 0, y: 62, width: 402, height: 710))
        let pill = FeelElement(key: "reader.restart", type: "button", frame: CGRect(x: 120, y: 780, width: 162, height: 44))
        let result = FeelFloat.check(viewport: shrunk, chrome: [pill], end: [text("l", CGRect(x: 24, y: 740, width: 354, height: 22))],
                                     endViewport: shrunk.frame, endChrome: [pill], window: phone, reachedEnd: true,
                                     expected: ["reader.restart"], pose: "portrait")
        #expect(!result.passed)
        #expect(result.detections.count == 1)
        #expect(result.detections[0].what.contains("sits beside scroll view \"reader.page\", not over it: the content stops at its bottom, 52 pt short"))
    }

    @Test func aLastLineLeftUnderThePillFails() {
        let pill = FeelElement(key: "reader.restart", type: "button", frame: CGRect(x: 120, y: 780, width: 162, height: 44))
        let under = text("words 3f2a", CGRect(x: 24, y: 790, width: 354, height: 22))
        let result = FeelFloat.check(viewport: pageView, chrome: [pill], end: [lastLine.with(y: 700), under], endViewport: page,
                                     endChrome: [pill], window: phone, reachedEnd: true, expected: [], pose: "p")
        #expect(result.detections.count == 1)
        #expect(result.detections[0].what.contains("stays 22 pt under button \"reader.restart\""))
    }

    @Test func aLastLineCutOffByTheViewportFails() {
        let cut = text("words 3f2a", CGRect(x: 24, y: 830, width: 354, height: 22))
        let result = FeelFloat.check(viewport: pageView, chrome: [], end: [cut], endViewport: page, endChrome: [], window: phone,
                                     reachedEnd: true, expected: [], pose: "p")
        #expect(result.detections.count == 1)
        #expect(result.detections[0].what.contains("is cut off: it runs 12 pt past the bottom"))
    }

    @Test func aLastLineCutOffAtTheSideFails() {
        let wide = text("words 3f2a", CGRect(x: 24, y: 740, width: 420, height: 22))
        let result = FeelFloat.check(viewport: pageView, chrome: [], end: [wide], endViewport: page, endChrome: [], window: phone,
                                     reachedEnd: true, expected: [], pose: "p")
        #expect(result.detections.count == 1)
        #expect(result.detections[0].what.contains("runs 42 pt past the trailing side"))
    }

    @Test func aLastLineNeverBroughtOnScreenCouldNotBeChecked() {
        // Below the window altogether: the swipes did not reach the end, so the end is not judged as cut off.
        let below = text("words 7881", CGRect(x: 24, y: 1_200, width: 354, height: 22))
        let result = FeelFloat.check(viewport: pageView, chrome: [], end: [below], endViewport: page, endChrome: [], window: phone,
                                     reachedEnd: true, expected: [], pose: "p")
        #expect(result.detections.isEmpty, "\(result.text)")
        #expect(result.summary.hasPrefix("could not check"))
        #expect(result.text.contains("never brought into the window"))
        // Swipes that moved the content and stopped with the line still below: no finger can bring it on screen.
        let stuck = FeelFloat.check(viewport: pageView, chrome: [], end: [below], endViewport: page, endChrome: [], window: phone,
                                    reachedEnd: true, swiped: true, expected: [], pose: "p")
        #expect(stuck.detections.count == 1)
        #expect(stuck.detections[0].inferred)
        #expect(stuck.detections[0].what.contains("cannot be brought on screen"))
        #expect(stuck.detections[0].what.contains("326 pt outside the window"))
    }

    @Test func noPosesCouldNotBeChecked() {
        #expect(FeelFloat.combine([]).summary.hasPrefix("could not check"))
    }

    @Test func whatCouldNotBeSeenCouldNotBeChecked() {
        let none = FeelFloat.check(viewport: nil, chrome: [], end: [], endViewport: nil, endChrome: [], window: phone,
                                   reachedEnd: true, expected: [], pose: "p")
        #expect(none.summary.hasPrefix("could not check"))
        let moving = FeelFloat.check(viewport: pageView, chrome: [], end: [lastLine], endViewport: page, endChrome: [],
                                     window: phone, reachedEnd: false, expected: ["reader.restart"], pose: "p")
        #expect(!moving.passed)
        #expect(moving.detections.isEmpty)
    }
}

@Suite struct IntentTests {
    @Test func oneTapThatFinishesPasses() {
        let result = FeelIntent.judge(FeelIntentTrail(intent: "open the book", control: "book", doneAfterFirst: 2.4, within: 30))
        #expect(result.passed, "\(result.text)")
        #expect(result.measures["seconds"] == 2.4)
        #expect(result.check == FeelCheck.finishesIntent.name)
    }

    @Test func aSecondTapThatFinishesFails() {
        // As Gatefold's: the download finished and the book stayed shut until he tapped it again.
        let result = FeelIntent.judge(FeelIntentTrail(intent: "open the book", control: "book", settledAfter: 4.2,
                                                      controlBack: true, doneAfterSecond: 0.6, tappedTwice: true, within: 30))
        #expect(!result.passed)
        #expect(result.detections.count == 1)
        #expect(result.detections[0].what.contains("took a second tap on \"book\": the first tap's work ended after 4.2 s"))
    }

    @Test func workThatNeverFinishesCouldNotBeChecked() {
        let twice = FeelIntent.judge(FeelIntentTrail(intent: "open", control: "book", settledAfter: 4, controlBack: true, tappedTwice: true, within: 30))
        #expect(!twice.passed && twice.detections.isEmpty)
        let gone = FeelIntent.judge(FeelIntentTrail(intent: "open", control: "book", settledAfter: 4, controlBack: false, within: 30))
        #expect(gone.summary.contains("was gone"))
        let busy = FeelIntent.judge(FeelIntentTrail(intent: "open", control: "book", within: 30))
        #expect(busy.summary.contains("still busy"))
        // Pointed at something already on screen, a pass would mean nothing.
        let already = FeelIntent.judge(FeelIntentTrail(intent: "open", control: "book", doneAfterFirst: 0, within: 30, doneBefore: true))
        #expect(already.summary.hasPrefix("could not check") && already.summary.contains("already done"))
    }
}

@Suite struct CatalogTests {
    @Test func everyCheckHasAPrincipleAndEveryPrincipleHasChecks() {
        for principle in FeelPrinciple.all {
            #expect(!principle.checks.isEmpty)
            #expect(!principle.promise.isEmpty)
        }
        #expect(FeelPrinciple.all.flatMap(\.checks).count == FeelCheck.all.count)
        #expect(Set(FeelCheck.all.map(\.name)).count == FeelCheck.all.count, "every check has its own name")
        for check in FeelCheck.all { #expect(!check.calls.isEmpty, "\(check.name) names the calls that run it") }
        #expect(FeelCheck.all.prefix(FeelGenre.allCases.count).map(\.name) == FeelGenre.allCases.map(\.rawValue))
    }

    /// docs/ouro-feel/checks.json is the catalog, byte for byte; the site reads it.
    @Test func theCommittedCatalogIsCurrent() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/ouro-feel/checks.json")
        let current = FeelCatalog.current.json
        if ProcessInfo.processInfo.environment["OURO_FEEL_WRITE_CATALOG"] == "1" { try current.write(to: url) }
        let committed = try Data(contentsOf: url)
        #expect(committed == current, "docs/ouro-feel/checks.json is stale: run OURO_FEEL_WRITE_CATALOG=1 swift test --filter CatalogTests")
    }
}

extension CatalogTests {
    /// The guide's tables list every check under its principle, with its calls, so a new check is never only in code.
    @Test func theGuideListsEveryCheckUnderItsPrinciple() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/ouro-feel/README.md")
        let guide = try String(contentsOf: url, encoding: .utf8)
        for principle in FeelPrinciple.all {
            let heading = "## " + principle.name.prefix(1).uppercased() + principle.name.dropFirst()
            guard let start = guide.range(of: heading + "\n") else {
                Issue.record("the guide has no section \"\(heading)\"")
                continue
            }
            let section = guide[start.upperBound...].prefix { _ in true }
            let end = section.range(of: "\n## ")?.lowerBound ?? section.endIndex
            let body = section[..<end]
            for check in principle.checks {
                #expect(body.contains("| \(check.name)") , "\(heading) lists \(check.name)")
                for call in check.calls { #expect(body.contains(call), "\(heading) names \(call)") }
            }
        }
    }
}

private extension FeelElement {
    func with(y: CGFloat) -> FeelElement {
        var e = self
        e.frame.origin.y = y
        return e
    }
}
