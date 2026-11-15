import OuroHX
import OuroHXTesting
import UIKit
import XCTest

/// Core's HX component claims (`components.claims.json`), proven on the running gallery. Each test names the claims
/// it proves; `Tests/OuroHXTests/ClaimCoverageTests.swift` checks every claim has a proof.
@MainActor
final class ComponentClaimTests: XCTestCase {
    /// Every component page, each registered by its own file under `Pages/` (`GalleryPageClaims`).
    static var pages: [String] { GalleryPageClaims.all.map { $0.page } }
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
        if open { GalleryPageClaims.named(page)?.settle(app) }
        waitForTheScreenToHoldStill(app)
        return app
    }

    /// The first launch on a fresh simulator can still be fading the page in after two seconds, and the audit then
    /// reads its words at part opacity as failing contrast (PR #150's shard 3, 2026-11-15: the buttons page's title and
    /// version line, default size, light, the run's first launch). So the audit waits until two screenshots half a
    /// second apart are the same, for at most `timeout` seconds: a page that never holds still (a blinking caret) is
    /// audited when the time is up, as before.
    private func waitForTheScreenToHoldStill(_ app: XCUIApplication, timeout: TimeInterval = 6) {
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        var last = window.screenshot().pngRepresentation
        while Date() < deadline {
            usleep(500_000)
            let now = window.screenshot().pngRepresentation
            if now == last { return }
            last = now
        }
    }

    /// The audit ran out of time and found nothing either way: Xcode's "Audit failed to complete in time" (-56), or
    /// XCTest's own "Timed out while running accessibility audit" (XCTFuture 1000).
    static func auditTimedOut(_ error: NSError) -> Bool {
        (error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56)
            || (error.domain == "com.apple.dt.XCTest.XCTFuture" && error.code == 1000)
    }

    /// Runs `audit`, and on a timeout runs it again after a pause, up to three runs in all. A loaded runner timed out
    /// on two pages in a row, then on the sheet page twice running (main, run 43715261672), and the keyboard sheet's
    /// clipped-text audit once (run 43710948223). Every finding and every other error fails at once; only a third
    /// timeout fails as a timeout.
    static func auditing(_ name: String, _ audit: () throws -> Void) {
        for attempt in 1...3 {
            do {
                try audit()
                return
            } catch let error as NSError where auditTimedOut(error) {
                if attempt == 3 { XCTFail("\(name), audited 3 times and timed out each time: \(error)") }
                Thread.sleep(forTimeInterval: 5)
            } catch {
                XCTFail("\(name): \(error)")
                return
            }
        }
    }

    /// Claims target.touch, name.spoken, text.reflows and contrast.text: Xcode's accessibility audit (hit regions,
    /// descriptions, traits, clipped text, Dynamic Type, contrast) on every component page, at the default and the
    /// largest accessibility text size, in light and dark. Each page's file under `Pages/` says how its audit runs, what
    /// it excuses and why, and what it checks after the audit to prove the excuse hides nothing.
    func testEveryComponentPagePassesTheAccessibilityAudit() throws {
        // `OURO_AUDIT_PAGES=toasts,sheet` (as `TEST_RUNNER_OURO_AUDIT_PAGES` to xcodebuild) audits only those pages.
        let only = ProcessInfo.processInfo.environment["OURO_AUDIT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        for claims in GalleryPageClaims.all where only?.contains(claims.page) ?? true {
            for variant in claims.auditVariants {
                for size in [nil, Self.largest] {
                    for scheme in ["light", "dark"] {
                        let run = GalleryAuditRun(name: "\(claims.page)\(variant.suffix) \(size ?? "default") \(scheme)", size: size, extra: variant.extra)
                        let app = launch(claims.page, size: size, scheme: scheme, extra: variant.extra)
                        XCTContext.runActivity(named: run.name) { _ in
                            Self.auditing(run.name) { try app.ouroAccessibilityAudit(excuse: claims.excuse(app)) }
                        }
                        claims.afterAudit(app, run)
                        app.terminate()
                    }
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
        for claims in GalleryPageClaims.all {
            let app = launch(claims.page)
            claims.voiceOver(app)
            app.terminate()
        }
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
        ToastsPageClaims.expand(app)
        // Every toast on this page waits to be dismissed, so no timer can meet this wait: only the close can.
        let close = app.buttons.matching(identifier: "Dismiss").allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(close, "a toast's close is reachable")
        close?.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: app.buttons.matching(identifier: "Dismiss"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: Self.closeBudget), .completed, "the toast's close dismissed it, and only it")
        app.terminate()
    }

    /// The contrast between the darkest and lightest pixels in `rect` (points): the words and what is under them.
    /// The 2nd and 98th percentiles, so antialiasing and a stray highlight don't decide it.
    static func inkContrast(_ image: UIImage, in rect: CGRect) -> Double {
        let rows = luminanceRows(image, in: rect)
        return rows.isEmpty ? 0 : contrast(rows.flatMap { $0 })
    }

    /// The lowest contrast of any line of ink in `rect`: rows that hold ink, split wherever a row holds none, each
    /// measured on its own. So a near-white message can never carry a faint description under it past 5:1. `lineHeight`
    /// is the tallest line the words can have, in points: a band taller than 1.3 lines (two lines run together), or
    /// fewer bands than the height holds lines (one too faint to count as ink), reads as 0.
    static func lineInkContrast(_ image: UIImage, in rect: CGRect, lineHeight: CGFloat) -> Double {
        let rows = luminanceRows(image, in: rect)
        guard !rows.isEmpty else { return 0 }
        let all = rows.flatMap { $0 }.sorted()
        let paper = all[all.count / 2]
        func ratio(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }
        let inked = rows.map { row in row.contains { ratio($0, paper) > 1.5 } }
        var lines: [[Double]] = [], heights: [Int] = [], line: [Double] = [], height = 0
        for (row, ink) in zip(rows + [[]], inked + [false]) {
            if ink { line += row; height += 1; continue }
            if height >= 4 { lines.append(line); heights.append(height) }
            line = []; height = 0
        }
        let tallest = lineHeight * image.scale
        let expected = max(1, Int((rect.height * image.scale / tallest).rounded()))
        guard lines.count >= expected, heights.allSatisfy({ CGFloat($0) <= 1.3 * tallest }) else {
            print("toast words: \(lines.count) lines of ink, heights \(heights) px; expected \(expected) of at most \(tallest) px")
            return 0
        }
        return lines.map(contrast).min() ?? 0
    }

    private static func luminanceRows(_ image: UIImage, in rect: CGRect) -> [[Double]] {
        guard let cg = image.cgImage else { return [] }
        let scale = image.scale
        let r = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
        guard let crop = cg.cropping(to: r) else { return [] }
        let w = crop.width, h = crop.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        func lin(_ v: UInt8) -> Double { let c = Double(v) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return (0..<h).map { y in
            (0..<w).map { x in
                let i = (y * w + x) * 4
                return 0.2126 * lin(px[i]) + 0.7152 * lin(px[i + 1]) + 0.0722 * lin(px[i + 2])
            }
        }
    }

    /// The contrast between the darkest and lightest 2% of `lum`.
    private static func contrast(_ lum: [Double]) -> Double {
        let lum = lum.sorted()
        guard !lum.isEmpty else { return 0 }
        let lo = lum[lum.count * 2 / 100], hi = lum[lum.count * 98 / 100]
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Claim toast.action-stays: a toast with an action is still there after the five seconds a plain one gets. The
    /// Undo toast goes first, so by the time the plain one has gone it has outlived five seconds.
    func testAToastWithAnActionWaits() {
        let app = launch("toasts", open: false)
        // Each toast is waited for, not timed: a loaded runner can drop a tap or show a toast late, and a toast that
        // never showed is a tap that didn't take, so it is tapped once more before anything is judged (#91).
        // A retap is never silent: it is logged and attached, so a dropped tap shows in the run.
        let undo = app.buttons["Undo"], saved = app.staticTexts["Recipe saved"]
        // Whether the toast showed is what the wait saw, not a later look: a plain toast leaves on its own after a few
        // seconds, and on a loaded runner the idle wait after a tap took 4.4 s, so "Recipe saved" was found and then
        // gone 50 ms later, before an `exists` check (main, run 43731240135).
        func tapUntil(_ button: String, shows toast: XCUIElement) -> Bool {
            var shown = toast.exists
            for attempt in 1...2 where !shown {
                if attempt > 1 {
                    let note = "retap: \(button) showed no toast within 10 s, so it was tapped again (#91)"
                    print("[ouro-hx] \(note)")
                    let attachment = XCTAttachment(string: note)
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
                app.buttons[button].tap()
                shown = toast.waitForExistence(timeout: 10)
            }
            return shown
        }
        XCTAssertTrue(tapUntil("Delete", shows: undo), "Delete never showed its Undo toast")
        XCTAssertTrue(tapUntil("Save", shows: saved), "Save never showed its toast")
        XCTAssertTrue(saved.waitForNonExistence(timeout: 15), "a plain toast dismisses itself")
        sleep(1)
        XCTAssertTrue(app.buttons["Undo"].exists, "the toast with Undo stays")
        app.terminate()
    }

    /// Whether the keyboard came up for the sheet's name field, which the page focuses on its own. On a freshly booted
    /// CI simulator it sometimes never came up (#81: "No matches found for ... Keyboard" on shard 1's first test), so a
    /// keyboard not up in 10 s gets one tap on the field, as a person would give it, and 10 s more.
    func keyboardUp(_ app: XCUIApplication) -> Bool {
        let keyboard = app.keyboards.firstMatch
        if keyboard.waitForExistence(timeout: 10) { return true }
        let field = app.descendants(matching: .any).matching(identifier: "sheet.name").firstMatch
        guard field.waitForExistence(timeout: 5) else { return false }
        let note = "the keyboard was not up 10 s after the sheet opened, so its name field was tapped (#81)"
        print("[ouro-hx] \(note)")
        let attachment = XCTAttachment(string: note)
        attachment.lifetime = .keepAlways
        add(attachment)
        field.tap()
        return keyboard.waitForExistence(timeout: 10)
    }

    /// Claim text.reflows in a sheet with two fields, the upper one focused, at the largest size: as the keyboard comes
    /// up the whole sheet scrolls only as far toward its actions as keeps the field being typed in wholly in sight.
    /// At the default size the fitted sheet, which iOS lifts clear of the keyboard, shows everything: its title, both
    /// fields and its action (iOS 27 still insets it by the keyboard's whole height, which once squeezed its body to
    /// nothing and scrolled the fields away).
    func testASheetKeepsTheFocusedFieldInSightRatherThanItsEnd() throws {
        for size in [nil, Self.largest] as [String?] {
            for scheme in ["light", "dark"] {
                let name = "\(size ?? "default") \(scheme)"
                let app = launch("sheet", open: false, size: size, scheme: scheme, extra: ["-sheetKeyboard", "1", "-sheetNotes", "1"])
                let keyboard = app.keyboards.firstMatch
                XCTAssertTrue(keyboardUp(app), "\(name): the keyboard is not up")
                let field = app.descendants(matching: .any).matching(identifier: "sheet.name").firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 5), "\(name): no name field")
                // Settled: the field stops moving once the keyboard has arrived (unmoved over two looks).
                var last = CGRect.null, still = 0
                for _ in 0..<16 where still < 2 {
                    let now = field.frame
                    still = now == last ? still + 1 : 0
                    last = now
                    Thread.sleep(forTimeInterval: 0.3)
                }
                let sheet = app.descendants(matching: .any).matching(identifier: OuroSheetMetrics.accessibilityIdentifier).firstMatch
                let screen = app.windows.firstMatch.frame
                let inSight = CGRect(x: screen.minX, y: sheet.frame.minY, width: screen.width, height: keyboard.frame.minY - sheet.frame.minY + 1)
                XCTAssertTrue(inSight.contains(field.frame), "\(name): the focused field is out of sight at \(field.frame), keyboard at \(keyboard.frame.minY)")
                // It is the name field that has the keyboard, not the notes below it.
                XCTAssertEqual(field.value(forKey: "hasKeyboardFocus") as? Bool, true, "\(name): the name field is not focused")
                if size == nil {
                    let notes = app.descendants(matching: .any).matching(identifier: "sheet.notes").firstMatch
                    let title = app.staticTexts["New cookbook"].firstMatch
                    let action = app.buttons["Create cookbook"].firstMatch
                    for (what, element) in [("title", title), ("notes", notes), ("action", action)] {
                        XCTAssertTrue(element.exists && inSight.contains(element.frame), "\(name): the \(what) is out of sight at \(element.frame), keyboard at \(keyboard.frame.minY)")
                    }
                }
                app.terminate()
            }
        }
    }

    /// Claim text.reflows in a sheet with the keyboard up, at the default and the largest size: the field being typed in
    /// and the action under it stay in sight above the keyboard and nothing runs up under the status bar. At the
    /// largest size the whole sheet scrolls to keep them there, and the action's capsule grows to hold its two lines.
    /// A sheet with a detent, which the keyboard covers rather than iOS lifting it, is checked too, at the default size.
    func testASheetWithTheKeyboardUpKeepsItsFieldAndActionInSight() throws {
        for (size, detent) in [(nil, false), (nil, true), (Self.largest, false)] as [(String?, Bool)] {
            for scheme in ["light", "dark"] {
                let name = "\(size ?? "default")\(detent ? " large detent" : "") \(scheme)"
                let app = launch("sheet", open: false, size: size, scheme: scheme, extra: ["-sheetKeyboard", "1"] + (detent ? ["-sheetDetent", "large"] : []))
                let keyboard = app.keyboards.firstMatch
                XCTAssertTrue(keyboardUp(app), "\(name): the keyboard is not up")
                let action = app.buttons["Create cookbook"].firstMatch
                XCTAssertTrue(action.waitForExistence(timeout: 5), "\(name): no Create cookbook")
                // Settled: the action stops moving once the keyboard has arrived (unmoved over two looks).
                var last = CGRect.null, still = 0
                for _ in 0..<16 where still < 2 {
                    let now = action.frame
                    still = now == last ? still + 1 : 0
                    last = now
                    Thread.sleep(forTimeInterval: 0.3)
                }
                let screen = app.windows.firstMatch.frame
                let sheet = app.descendants(matching: .any).matching(identifier: OuroSheetMetrics.accessibilityIdentifier).firstMatch
                XCTAssertGreaterThanOrEqual(sheet.frame.minY, screen.minY + 40, "\(name): the sheet runs up under the status bar at \(sheet.frame)")
                let inSight = CGRect(x: screen.minX, y: sheet.frame.minY, width: screen.width, height: keyboard.frame.minY - sheet.frame.minY + 1)
                let field = app.descendants(matching: .any).matching(identifier: "sheet.name").firstMatch
                XCTAssertTrue(field.exists && inSight.contains(field.frame), "\(name): the field being typed in is out of sight at \(field.frame)")
                XCTAssertTrue(inSight.contains(action.frame), "\(name): the action is out of sight at \(action.frame), keyboard at \(keyboard.frame.minY)")
                guard size != nil else {
                    // Clipped text only: the full audit, with the keyboard's own elements in the tree, outran its time
                    // limit on CI's hosted VM twice in four runs (even retried). Everything else on this page is
                    // audited without the keyboard in testEveryComponentPagePassesTheAccessibilityAudit.
                    Self.auditing("\(name) audit") { try app.ouroAccessibilityAudit(for: .textClipped, excuse: Self.keyboardsOwn) }
                    app.terminate()
                    continue
                }
                // "Create cookbook" wraps onto two lines on a phone; squeezed, its capsule stayed one line tall and the
                // words spilled out. Two lines need at least twice a line's 44 points. An iPad's form sheet is wide
                // enough to hold it on one line, so there the capsule needs only one line's 44.
                let actionHeight: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 88 : 44
                XCTAssertGreaterThanOrEqual(action.frame.height, actionHeight, "\(name): the action's capsule is \(action.frame.height) tall, under \(actionHeight)")
                // The audit reads the title, the description and the action, scrolled to with the keyboard up, as "Text clipped",
                // though both wrap in full; it also reads the clipping where the scroll's edge cuts the title. Excused,
                // by where they are as the audit reads them: the two labels only while wholly in sight (the action
                // only while its capsule is as tall as its lines need); anything cut by the sheet's edge, outside the sheet or not
                // the sheet's own.
                // Everything else wholly in sight must pass. Clipped text and Dynamic Type only, like the default size,
                // for the audit's time limit on CI; contrast and targets are audited without the keyboard elsewhere.
                let description = app.staticTexts["Name it after what goes inside."].firstMatch
                XCTAssertTrue(inSight.contains(description.frame), "\(name): the description is out of sight at \(description.frame)")
                do {
                    try app.ouroAccessibilityAudit(for: [.textClipped, .dynamicType], excuse: { issue in
                        if Self.keyboardsOwn(issue) { return true }
                        guard issue.compactDescription == "Text clipped", let element = issue.element else { return false }
                        let frame = element.frame, sheetNow = sheet.frame
                        let sightNow = CGRect(x: screen.minX, y: sheetNow.minY, width: screen.width,
                                              height: keyboard.frame.minY - sheetNow.minY + 1)
                        if !sheetNow.contains(frame) || !sightNow.contains(frame) { return true }
                        // The page behind the modal sheet, which iOS 27's audit reads (at the size its text-size check
                        // sets) though it is not the sheet's: only the sheet's own elements are held to this.
                        let own = sheet.descendants(matching: .any).matching(NSPredicate(format: "label == %@", element.label))
                            .allElementsBoundByIndex.map(\.frame)
                        if !own.contains(where: { abs($0.minX - frame.minX) < 1 && abs($0.minY - frame.minY) < 1 && abs($0.height - frame.height) < 1 }) { return true }
                        switch element.label {
                        // The title too, now that the sheet stops with it in sight (where its top edge falls
                        // between lines): it wraps in full (taste round 8's largest-size captures).
                        case "Name it after what goes inside.", "New cookbook": return true
                        case "Create cookbook": return frame.height >= actionHeight
                        default: return false
                        }
                    })
                } catch { XCTFail("\(name) audit: \(error)") }
                app.terminate()
            }
        }
    }

    /// Claim text.reflows: at the largest size, with no keyboard, a sheet shorter than its content opens at its top, its
    /// title in sight, and stays there as its height settles.
    /// The system keyboard's own parts, which the audit also reads while it is up: CI's simulator leaves the prediction
    /// bar's cells empty, and the audit flags each as having no description. They are iOS's, not the sheet's.
    private static func keyboardsOwn(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        issue.detailedDescription.contains("TUIPredictionViewCell")
    }

    func testATallSheetOpensAtItsTopAtTheLargestSize() {
        let app = launch("sheet", size: Self.largest, extra: ["-sheetDetent", "medium"])
        let sheet = app.descendants(matching: .any).matching(identifier: OuroSheetMetrics.accessibilityIdentifier).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "no sheet")
        sleep(1)
        // The sheet's own title, not the page's button of the same name behind it.
        let title = sheet.staticTexts["Save to cookbook"].firstMatch
        XCTAssertTrue(title.exists, "no title in the sheet")
        XCTAssertGreaterThanOrEqual(title.frame.minY, sheet.frame.minY - 1, "the title is scrolled away, at \(title.frame) in a sheet at \(sheet.frame)")
        // Shorter than its content: its Save action starts below the sheet's visible bottom, so the anchor is what's tested.
        let save = sheet.buttons["Save"].firstMatch
        XCTAssertGreaterThan(save.frame.maxY, sheet.frame.maxY, "the sheet fits, at \(sheet.frame) with Save at \(save.frame), so this checks nothing")
        app.terminate()
    }

    /// Claim dismiss.reachable: a toast sent while a sheet is open shows above the sheet, where it can be read and
    /// closed from its Dismiss button.
    func testAToastShowsAboveASheet() {
        // Kept until dismissed: a busy CI runner took longer than its five seconds to reach the Dismiss tap (#14,
        // 2026-11-06), so the toast had gone by itself.
        let app = launch("sheet", open: false, extra: ["-toastSeconds", "0"])
        // A busy runner can drop the Filters tap or open the sheet late (#85): tap again once if no sheet came in 10 s.
        let remember = app.buttons["Remember these"]
        for attempt in 1...2 where !remember.exists {
            if attempt > 1 { print("[ouro-hx] retap: Filters opened no sheet within 10 s, so it was tapped again (#85)") }
            app.buttons["Filters"].tap()
            _ = remember.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(remember.exists, "Filters opened no sheet")
        remember.tap()
        let toast = app.staticTexts["Filters remembered"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        // Hittable once its arrival has settled: a toast caught mid-arrival is not hittable yet (#85), while one behind
        // the sheet never is.
        let above = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: toast)
        XCTAssertEqual(XCTWaiter().wait(for: [above], timeout: 3), .completed, "the toast is behind the sheet")
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
