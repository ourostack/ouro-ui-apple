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
    /// audit reads that scaled text as "Text clipped", so the fitted sheet is audited for everything else and the same
    /// sheet at full height (`-sheetDetent large`, drawn unscaled) is audited for clipping too.
    func testEveryComponentPagePassesTheAccessibilityAudit() throws {
        let runs: [(page: String, extra: [String], known: [String])] =
            Self.pages.map { ($0, [], $0 == "sheet" ? ["Text clipped"] : []) } + [("sheet", ["-sheetDetent", "large"], [])]
        for run in runs {
            for size in [nil, Self.largest] {
                for scheme in ["light", "dark"] {
                    let name = "\(run.page)\(run.extra.isEmpty ? "" : " large") \(size ?? "default") \(scheme)"
                    let app = launch(run.page, size: size, scheme: scheme, extra: run.extra)
                    XCTContext.runActivity(named: name) { _ in
                        do { try app.ouroAccessibilityAudit(knownIssues: run.known) } catch { XCTFail("\(name): \(error)") }
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
        XCTAssertTrue(app.buttons["Undo"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "Dismiss").count, 3, "every toast has a dismiss button")
        XCTAssertTrue(app.otherElements["Notifications"].exists || app.descendants(matching: .any)["Notifications"].exists, "the toasts' region is named")
        app.terminate()
    }

    /// Claim dismiss.reachable: the banner, the sheet and a toast each close from their labelled control.
    func testCloseControlsClose() {
        var app = launch("banners")
        app.buttons["Dismiss"].tap()
        XCTAssertTrue(app.staticTexts["Couldn't save"].waitForNonExistence(timeout: 3))
        app.terminate()
        app = launch("sheet")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Pick where this recipe lives."].waitForNonExistence(timeout: 3))
        app.terminate()
        app = launch("toasts")
        app.buttons.matching(identifier: "Dismiss").firstMatch.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: app.buttons.matching(identifier: "Dismiss"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 3), .completed)
        app.terminate()
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
    func testAToastShowsAboveASheet() {
        let app = launch("sheet", open: false)
        app.buttons["Filters"].tap()
        XCTAssertTrue(app.buttons["Remember these"].waitForExistence(timeout: 3))
        app.buttons["Remember these"].tap()
        XCTAssertTrue(app.staticTexts["Filters remembered"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Filters remembered"].isHittable, "the toast is behind the sheet")
        app.buttons.matching(identifier: "Dismiss").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Filters remembered"].waitForNonExistence(timeout: 3), "its Dismiss closes it")
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
}
