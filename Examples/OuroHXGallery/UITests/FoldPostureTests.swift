import OuroHX
import OuroHXTesting
import XCTest

/// The fold postures on a real iPhone Duo simulator, its hinge moved by Device Hub (`ouro-devicehub serve`). Runs only in
/// CI's "Gallery on an iPhone Duo" job, which passes the request directory as `TEST_RUNNER_OURO_DUO_POSTURE_DIR`;
/// anywhere else it skips. Folding.md says what each component does:
///
/// - **Sheet.** Held as a tabletop, it rests on the lower half, below the fold, even when it asks for full height; open
///   flat it keeps its own height.
/// - **Item and card.** No posture of their own: placed in one pane, they lay out in its width. In a book's leading
///   page every control stays left of the fold, and the page passes the accessibility audit and VoiceOver's checks.
///
/// One test, in order, because the hinge is the simulator's state: open flat (a book), turned a quarter (one tall
/// page) and bent (a tabletop). Device Hub shots of each posture are kept in the request directory's `shots/`.
@MainActor
final class FoldPostureTests: XCTestCase {
    private var hinge: OuroDuoHinge!

    override func setUp() async throws {
        continueAfterFailure = true
        guard ProcessInfo.processInfo.environment["OURO_DUO_POSTURE_DIR"] != nil else {
            throw XCTSkip("Needs an iPhone Duo and ouro-devicehub serve; CI's Duo job runs it.")
        }
        hinge = try OuroDuoHinge()
    }

    private func launch(_ page: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", "pearl", "-page", page, "-scheme", "light", "-foldProbe", "1"] + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        sleep(3)
        return app
    }

    /// The posture the gallery's fold reader gives ("tabletop, fold 371 to 419") and its fold band's two edges.
    private func posture(_ app: XCUIApplication) -> (name: String, from: CGFloat, to: CGFloat) {
        let probe = app.staticTexts["fold.posture"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10), "the gallery shows no fold probe")
        let text = probe.label
        let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }.map { CGFloat($0) }
        let name = String(text.prefix { $0 != "," })
        return (name, numbers.first ?? 0, numbers.dropFirst().first ?? 0)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func sheet(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: OuroSheetMetrics.accessibilityIdentifier).firstMatch
    }

    func testEachComponentFollowsTheFold() throws {
        // Open flat: the inner screen is wide and folds down the middle, a book.
        try hinge.set(.open)
        try hinge.shot("1-book")
        for page in ["items", "cards"] {
            let app = launch(page, ["-open", "1", "-foldPane", "1"])
            let book = posture(app)
            XCTAssertEqual(book.name, "book", "open flat, the Duo should read as a book")
            attach(app, "book \(page) in the leading page")
            var controls: [XCUIElementSnapshot] = []
            func walk(_ e: XCUIElementSnapshot) {
                if [.button, .staticText, .switch, .textField].contains(e.elementType), e.identifier != "fold.posture" { controls.append(e) }
                e.children.forEach(walk)
            }
            walk(try app.snapshot())
            XCTAssertFalse(controls.isEmpty, "\(page): nothing found")
            for c in controls where c.frame.width > 0 {
                XCTAssertLessThanOrEqual(c.frame.maxX, book.from + 0.5, "\(page): \"\(c.label)\" reaches past the fold (\(c.frame))")
            }
            GalleryPageClaims.named(page)?.voiceOver(app)
            XCTContext.runActivity(named: "\(page) audit in a book's leading page") { _ in
                // The probe is drawn nearly clear on purpose, for the test to read; the page's own excuses apply as in
                // ComponentClaimTests.
                let excused = GalleryPageClaims.named(page)?.excuse(app)
                let excuse: (XCUIAccessibilityAuditIssue) -> Bool = { $0.element?.identifier == "fold.posture" || excused?($0) == true }
                do { try app.ouroAccessibilityAudit(excuse: excuse) } catch { XCTFail("\(page) in a book: \(error)") }
            }
            app.terminate()
        }

        // A sheet asking for full height, open flat: it keeps its height and reaches the top half.
        let flat = launch("sheet", ["-open", "1", "-sheetDetent", "large"])
        XCTAssertTrue(sheet(flat).waitForExistence(timeout: 10))
        attach(flat, "book sheet at full height")
        XCTAssertLessThan(sheet(flat).frame.minY, flat.windows.firstMatch.frame.midY, "open flat, a full-height sheet keeps its height")
        flat.terminate()

        // Turned a quarter and bent: held tall with the fold across the middle, a tabletop.
        try hinge.rotateRight()
        try hinge.set(.partiallyOpen)
        try hinge.shot("2-tabletop")
        for detent in ["large", "fitted"] {
            let app = launch("sheet", ["-open", "1"] + (detent == "large" ? ["-sheetDetent", "large"] : []))
            let tabletop = posture(app)
            XCTAssertEqual(tabletop.name, "tabletop", "turned and bent, the Duo should read as a tabletop")
            let drawn = sheet(app)
            XCTAssertTrue(drawn.waitForExistence(timeout: 10))
            attach(app, "tabletop sheet, \(detent)")
            XCTAssertGreaterThanOrEqual(drawn.frame.minY, tabletop.to - 0.5, "held as a tabletop, the \(detent) sheet should rest below the fold (\(drawn.frame), fold to \(tabletop.to))")
            XCTAssertTrue(app.buttons["Save"].firstMatch.isHittable, "\(detent): the sheet's action is out of reach below the fold")
            app.terminate()
        }

        // Back as it was: flat, then three more quarter turns.
        try hinge.set(.open)
        for _ in 0..<3 { try hinge.rotateRight() }
    }
}
