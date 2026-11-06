import OuroHX
import OuroHXTesting
import XCTest

/// Core's HX component claims (`components.claims.json`), proven on the running gallery. Each test names the claims
/// it proves; `Tests/OuroHXTests/ClaimCoverageTests.swift` checks every claim has a proof.
@MainActor
final class ComponentClaimTests: XCTestCase {
    static let pages = ["buttons", "empty", "banners", "sheet", "toasts"]
    static let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUp() { continueAfterFailure = true }

    private func launch(_ page: String, open: Bool = true, size: String? = nil, scheme: String = "light", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", "pearl", "-page", page, "-open", open ? "1" : "0", "-scheme", scheme] + extra
        if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        // Let sheets and toasts finish arriving.
        sleep(2)
        return app
    }

    /// Claims target.touch, name.spoken, text.reflows and contrast.text: Xcode's accessibility audit (hit regions,
    /// descriptions, traits, clipped text, Dynamic Type, contrast) on every component page, at the default and the
    /// largest accessibility text size, in light and dark.
    ///
    /// The sheet runs twice. iOS 26 draws a sheet below full height at 96% (see `OuroSheetMetrics.drawnScale`), and the
    /// audit reads that scaled text as "Text clipped"; `ouroAccessibilityAudit` excuses that inside a scaled
    /// `.ouroSheet` only, so the same sheet at full height (`-sheetDetent large`, drawn unscaled) is audited for
    /// clipping too.
    func testEveryComponentPagePassesTheAccessibilityAudit() throws {
        let runs: [(page: String, extra: [String], known: [String])] =
            Self.pages.map { ($0, [], []) } + [("sheet", ["-sheetDetent", "large"], [])]
        // `OURO_AUDIT_PAGES=toasts,sheet` (as `TEST_RUNNER_OURO_AUDIT_PAGES` to xcodebuild) audits only those pages.
        let only = ProcessInfo.processInfo.environment["OURO_AUDIT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        for run in runs where only?.contains(run.page) ?? true {
            for size in [nil, Self.largest] {
                for scheme in ["light", "dark"] {
                    let name = "\(run.page)\(run.extra.isEmpty ? "" : " large") \(size ?? "default") \(scheme)"
                    let app = launch(run.page, size: size, scheme: scheme, extra: run.extra)
                    XCTContext.runActivity(named: name) { _ in
                        let excuse = run.page == "buttons" ? Self.glassMisreadings : nil
                        do { try app.ouroAccessibilityAudit(knownIssues: run.known, excuse: excuse) } catch { XCTFail("\(name): \(error)") }
                    }
                    if run.page == "buttons" {
                        // What that excuse could hide: each glass button's words, measured from the screen's own
                        // pixels, read at 5:1 against the glass under them.
                        let shot = app.windows.firstMatch.screenshot().image
                        let glass = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'button.glass.'")).allElementsBoundByIndex
                        var measured = 0
                        for button in glass where app.windows.firstMatch.frame.contains(button.frame) {
                            let ratio = Self.inkContrast(shot, in: button.frame.insetBy(dx: 12, dy: 10))
                            XCTAssertGreaterThanOrEqual(ratio, 5, "\(name): glass \(button.label) reads at \(ratio):1")
                            measured += 1
                        }
                        // The glass row is shown first, so some of it is always on screen to measure.
                        XCTAssertGreaterThan(measured, 0, "\(name): no glass button on screen to measure")
                    }
                    if run.page == "toasts", size == nil {
                        // Expanded, as VoiceOver users always see the stack: every toast's own words are measured.
                        expandToasts(app)
                        XCTContext.runActivity(named: "\(name) expanded") { _ in
                            do { try app.ouroAccessibilityAudit(knownIssues: run.known, excuse: Self.expandedStackMisreadings) } catch { XCTFail("\(name) expanded: \(error)") }
                        }
                        // What those excuses could hide: every toast's buttons are full targets, reachable.
                        for button in app.buttons.matching(NSPredicate(format: "label IN %@", ["Dismiss", "Undo"])).allElementsBoundByIndex {
                            XCTAssertTrue(button.isHittable, "\(name) expanded: \(button.label) is not reachable")
                            XCTAssertGreaterThanOrEqual(min(button.frame.width, button.frame.height), 44, "\(name) expanded: \(button.label) is \(button.frame.size)")
                        }
                    }
                    if run.page == "sheet", run.extra.isEmpty {
                        // What the excused "Text clipped" could hide: the fitted sheet's last row and its action
                        // are on screen and reachable.
                        for control in ["Party food", "Save"] {
                            XCTAssertTrue(app.buttons[control].firstMatch.isHittable, "\(name): \"\(control)\" is not reachable in the fitted sheet")
                        }
                    }
                    app.terminate()
                }
            }
        }
    }

    /// Claim target.touch: every button on every component page is at least 44 by 44 points. One accessibility
    /// snapshot per page, the gallery's own controls included; the system's sheet grabber is not ours to size.
    func testEveryControlIs44Points() throws {
        for page in Self.pages {
            let app = launch(page)
            var buttons: [XCUIElementSnapshot] = []
            func walk(_ e: XCUIElementSnapshot) {
                if e.elementType == .button { buttons.append(e) }
                e.children.forEach(walk)
            }
            walk(try app.snapshot())
            XCTAssertFalse(buttons.isEmpty, "\(page): no buttons found")
            for b in buttons where b.label != "Sheet Grabber" {
                // Frames come back in fractional points; 0.01 of slack is rounding, not a smaller target.
                XCTAssertGreaterThanOrEqual(b.frame.height, 43.99, "\(page): \"\(b.label)\" is \(b.frame.height) tall")
                XCTAssertGreaterThanOrEqual(b.frame.width, 43.99, "\(page): \"\(b.label)\" is \(b.frame.width) wide")
            }
            app.terminate()
        }
    }

    /// Claim name.spoken: VoiceOver finds each control by the name it speaks, as a button, and each title as text.
    func testVoiceOverLabels() {
        var app = launch("buttons")
        for name in ["Save recipe", "Primary", "Destructive", "Glass pill", "Small", "Unavailable"] {
            XCTAssertTrue(app.buttons[name].firstMatch.exists, "buttons: no button named \"\(name)\"")
        }
        app.terminate()
        app = launch("empty")
        XCTAssertTrue(app.staticTexts["No recipes yet"].exists)
        XCTAssertTrue(app.buttons["Create recipe"].exists)
        // The icon is accessibilityHidden; XCUITest's tree still lists hidden images, so the audit's
        // sufficientElementDescription run, not an element query, is what checks it stays out of VoiceOver's way.
        app.terminate()
        app = launch("banners")
        XCTAssertTrue(app.buttons["Dismiss"].exists, "the dismissible banner's close button")
        XCTAssertTrue(app.buttons["Try again"].exists)
        app.terminate()
        app = launch("sheet")
        XCTAssertTrue(app.staticTexts["Save to cookbook"].exists)
        XCTAssertTrue(app.buttons["Close"].exists)
        app.terminate()
        app = launch("toasts")
        // Stacked, only the newest toast is shown; the older ones tuck behind it, out of VoiceOver's way. With
        // VoiceOver or Switch Control running the stack opens by itself; here a tap opens it.
        XCTAssertEqual(shownDismissButtons(app), 1, "only the front toast is shown")
        expandToasts(app)
        XCTAssertTrue(app.buttons["Undo"].exists)
        XCTAssertEqual(shownDismissButtons(app), 3, "every toast has a dismiss button")
        XCTAssertTrue(app.otherElements["Notifications"].exists || app.descendants(matching: .any)["Notifications"].exists, "the toasts' region is named")
        app.terminate()
    }

    /// How long a close may take to be reported, on the slowest runner: a toast's own time on screen plus margin. A
    /// fixed 3 s was too short on a busy CI runner, which reported a dismissed toast gone late though its recording
    /// shows it left (#21, 2026-11-05; the rerun passed). Nothing on these pages closes by itself, so only the close
    /// can meet the wait.
    static let closeBudget = OuroToastMetrics.defaultSeconds + 5

    /// Claim dismiss.reachable: the banner, the sheet and a toast each close from their labelled control.
    func testCloseControlsClose() {
        var app = launch("banners")
        app.buttons["Dismiss"].tap()
        XCTAssertTrue(app.staticTexts["Couldn\u{2019}t save"].waitForNonExistence(timeout: Self.closeBudget))
        app.terminate()
        app = launch("sheet")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Pick where this recipe lives."].waitForNonExistence(timeout: Self.closeBudget))
        app.terminate()
        app = launch("toasts")
        expandToasts(app)
        // Every toast on this page waits to be dismissed, so no timer can meet this wait: only the close can.
        let close = app.buttons.matching(identifier: "Dismiss").allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(close, "a toast's close is reachable")
        close?.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: app.buttons.matching(identifier: "Dismiss"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: Self.closeBudget), .completed, "the toast's close dismissed it, and only it")
        app.terminate()
    }

    /// Toasts' close buttons a finger can reach: the shown toasts' (a tucked one draws no buttons).
    private func shownDismissButtons(_ app: XCUIApplication) -> Int {
        app.buttons.matching(identifier: "Dismiss").allElementsBoundByIndex.filter(\.isHittable).count
    }

    /// Two readings the audit gets wrong on an expanded stack (W8, 2026-11-04, with diagnostics of each issue's
    /// element): it fails Undo's contrast even with Undo drawn black on the white surface (21:1), and reads the oldest
    /// toast's plain words, a static text with no action, as an undersized target, with a second such issue that has
    /// no element at all. Contrast is proven by the palette tests; the targets by the assertions after the audit.
    /// The audit misreads words on Liquid Glass: on the gallery's glass row it reported white "Primary" on near-black
    /// glass (well over 15:1 in `gallery-r10/buttons-dark.png`) as failing contrast, and raising every glass label to
    /// 6:1 made it report more failures, not fewer (W8 evidence, taste round 5). The same misreading as Undo on the glass
    /// toast. So contrast on a glass button is measured from the screen's pixels instead (`inkContrast`).
    static let glassMisreadings: (XCUIAccessibilityAuditIssue) -> Bool = { issue in
        issue.auditType == .contrast && (issue.element?.identifier.hasPrefix("button.glass.") ?? false)
    }

    /// The contrast between the darkest and lightest pixels in `rect` (points): the words and what is under them.
    /// The 2nd and 98th percentiles, so antialiasing and a stray highlight don't decide it.
    static func inkContrast(_ image: UIImage, in rect: CGRect) -> Double {
        guard let cg = image.cgImage else { return 0 }
        let scale = image.scale
        let r = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
        guard let crop = cg.cropping(to: r) else { return 0 }
        let w = crop.width, h = crop.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        func lin(_ v: UInt8) -> Double { let c = Double(v) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        var lum: [Double] = []
        lum.reserveCapacity(w * h)
        for i in stride(from: 0, to: px.count, by: 4) { lum.append(0.2126 * lin(px[i]) + 0.7152 * lin(px[i + 1]) + 0.0722 * lin(px[i + 2])) }
        lum.sort()
        guard !lum.isEmpty else { return 0 }
        let lo = lum[lum.count * 2 / 100], hi = lum[lum.count * 98 / 100]
        return (hi + 0.05) / (lo + 0.05)
    }

    static let expandedStackMisreadings: (XCUIAccessibilityAuditIssue) -> Bool = { issue in
        switch issue.auditType {
        case .contrast: issue.element?.label == "Undo"
        case .hitRegion: issue.element == nil || issue.element?.elementType == .staticText
        default: false
        }
    }

    /// Opens the toast stack by tapping its front toast, the newest, "Couldn’t save".
    private func expandToasts(_ app: XCUIApplication) {
        app.staticTexts["Couldn\u{2019}t save"].tap()
        // Until the stack has fanned out and its words have faded in: an audit mid-way reads fading words and moving
        // targets (CI failed it after a fixed second).
        var last: [CGRect] = []
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.25)
            let frames = app.buttons.matching(identifier: "Dismiss").allElementsBoundByIndex.map(\.frame)
            if frames.count == 3, frames == last { break }
            last = frames
        }
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(shownDismissButtons(app), 3, "a tap opens the stack")
    }

    /// Claim toast.action-stays: a toast with an action is still there after the five seconds a plain one gets. The
    /// Undo toast goes first, so by the time the plain one has gone it has outlived five seconds.
    func testAToastWithAnActionWaits() {
        let app = launch("toasts", open: false)
        app.buttons["Delete"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Recipe saved"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Recipe saved"].waitForNonExistence(timeout: 8), "a plain toast dismisses itself")
        sleep(1)
        XCTAssertTrue(app.buttons["Undo"].exists, "the toast with Undo stays")
        app.terminate()
    }

    /// Claim dismiss.reachable: a toast sent while a sheet is open shows above the sheet, where it can be read and
    /// closed from its Dismiss button.
    /// Claim text.reflows in a sheet with the keyboard up: at the largest size the whole sheet scrolls, so the field
    /// being typed in and the action under it stay in sight, nothing runs past the top of the screen, and the action's
    /// capsule keeps its words inside.
    /// The audit's clipped-text check holds there, with no excuse, as this sheet sits at full height.
    func testASheetWithTheKeyboardUpKeepsItsWordsInsideAtTheLargestSize() throws {
        for scheme in ["light", "dark"] {
            let app = launch("sheet", open: false, size: Self.largest, scheme: scheme, extra: ["-sheetKeyboard", "1"])
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "\(scheme): the keyboard is not up")
            sleep(1)
            let screen = app.windows.firstMatch.frame
            let action = app.buttons["Create cookbook"].firstMatch
            XCTAssertTrue(action.exists, "\(scheme): no Create cookbook")
            let words = action.staticTexts.firstMatch
            if words.exists {
                XCTAssertTrue(action.frame.insetBy(dx: -1, dy: -1).contains(words.frame), "\(scheme): the action's words \(words.frame) spill out of its capsule \(action.frame)")
            }
            XCTAssertLessThanOrEqual(action.frame.maxY, app.keyboards.firstMatch.frame.minY + 1, "\(scheme): the action is under the keyboard")
            let field = app.textFields["sheet.name"].firstMatch
            XCTAssertTrue(field.isHittable && field.frame.maxY <= app.keyboards.firstMatch.frame.minY + 1, "\(scheme): the field being typed in is out of sight at \(field.frame)")
            let sheet = app.descendants(matching: .any).matching(identifier: OuroSheetMetrics.accessibilityIdentifier).firstMatch
            XCTAssertGreaterThanOrEqual(sheet.frame.minY, screen.minY + 40, "\(scheme): the sheet runs up under the status bar at \(sheet.frame)")
            // The audit reads the description and the action, scrolled to with the keyboard up, as "Text clipped",
            // though both wrap in full (each grows to fit its words, at every size). What that excuse could hide is
            // checked here: each is wholly in sight, between the sheet's top and the keyboard.
            let inSight = CGRect(x: screen.minX, y: sheet.frame.minY, width: screen.width, height: app.keyboards.firstMatch.frame.minY - sheet.frame.minY + 1)
            for label in ["Name it after what goes inside.", "Create cookbook"] {
                let element = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
                XCTAssertTrue(inSight.contains(element.frame), "\(scheme): \(label) at \(element.frame) is not wholly in sight")
            }
            let scrolledTo: Set<String> = ["Name it after what goes inside.", "Create cookbook"]
            do {
                try app.ouroAccessibilityAudit(excuse: { issue in
                    issue.compactDescription == "Text clipped" && scrolledTo.contains(issue.element?.label ?? "")
                })
            } catch { XCTFail("\(scheme) audit: \(error)") }
            app.terminate()
        }
    }

    func testAToastShowsAboveASheet() {
        // Kept until dismissed: a busy CI runner took longer than its five seconds to reach the Dismiss tap (#14,
        // 2026-11-06), so the toast had gone by itself.
        let app = launch("sheet", open: false, extra: ["-toastSeconds", "0"])
        app.buttons["Filters"].tap()
        XCTAssertTrue(app.buttons["Remember these"].waitForExistence(timeout: 3))
        app.buttons["Remember these"].tap()
        XCTAssertTrue(app.staticTexts["Filters remembered"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Filters remembered"].isHittable, "the toast is behind the sheet")
        app.buttons.matching(identifier: "Dismiss").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Filters remembered"].waitForNonExistence(timeout: Self.closeBudget), "its Dismiss closes it")
        app.terminate()
    }

    /// Claim text.reflows: at the accessibility sizes an empty state's action spans the width, so its words have room.
    func testAnEmptyStatesActionSpansTheWidthAtAccessibilitySizes() {
        let app = launch("empty", size: Self.largest)
        let action = app.buttons["Create recipe"]
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(action.frame.width, app.windows.firstMatch.frame.width * 0.7, "the action hugs its label")
        app.terminate()
    }

    /// An empty state's symbol is drawn just above its title, centred on it, once it has arrived (round 4's cascade drew
    /// it at the screen's origin, over the page title). The symbol is hidden from VoiceOver, so this reads the pixels.
    func testAnEmptyStatesSymbolSitsAboveItsTitle() throws {
        let app = launch("empty")
        let title = app.staticTexts["No recipes yet"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 1.5)
        let shot = app.windows.firstMatch.screenshot().image
        let t = title.frame
        let above = CGRect(x: t.midX - 40, y: t.minY - 64, width: 80, height: 56)
        let corner = CGRect(x: 0, y: 60, width: 80, height: 56)
        let inked = Self.inkedFraction(shot, in: above)
        XCTAssertGreaterThan(inked, 0.05, "no symbol drawn above the title (\(inked))")
        let stray = Self.inkedFraction(shot, in: corner)
        let pageTitle = app.staticTexts.matching(NSPredicate(format: "label == 'Pearl'")).firstMatch
        XCTAssertTrue(pageTitle.exists)
        // The corner holds only the page title's ink, never more than the title alone draws there.
        XCTAssertLessThan(stray, 0.35, "something drawn over the page title (\(stray))")
        app.terminate()
    }

    /// The share of pixels in `rect` (points) darker than the page, on a light page.
    static func inkedFraction(_ image: UIImage, in rect: CGRect) -> Double {
        guard let cg = image.cgImage else { return 0 }
        let scale = image.scale
        let r = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
        guard let crop = cg.cropping(to: r) else { return 0 }
        let w = crop.width, h = crop.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        var inked = 0
        for i in stride(from: 0, to: px.count, by: 4) where Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2]) < 600 { inked += 1 }
        return Double(inked) / Double(w * h)
    }
}
