import OuroHX
import OuroHXTesting
import XCTest

final class SheetsPageClaims: GalleryPageClaims {
    override class var page: String { "sheet" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Save to cookbook"].exists)
        XCTAssertTrue(app.buttons["Close"].exists)
    }

    /// The sheet is audited at its fitted height and at full height (`-sheetDetent large`). iOS 26 draws a sheet below
    /// full height at 96% (`OuroSheetMetrics.drawnScale`) and the audit reads that scaled text as "Text clipped";
    /// `ouroAccessibilityAudit` excuses that inside a scaled `.ouroSheet` only, so the same sheet drawn unscaled is
    /// audited for clipping too.
    override class var auditVariants: [(suffix: String, extra: [String])] { [("", []), (" large", ["-sheetDetent", "large"])] }

    /// On iPad a sheet is a form sheet in the middle of the screen, and the page behind it stays in sight, dimmed. The
    /// sheet is modal, so that page is out of the accessibility tree, and the audit reads its words as "Potentially
    /// inaccessible text" with no element (every sheet run in main's iPad shard 2, 2026-11-14). Excused only with no
    /// element and only while the sheet is narrower than the window. On an iPhone the sheet spans the screen's width, so
    /// the same check there still fails any of the sheet's own words that VoiceOver can't reach.
    @MainActor override class func excuse(_ app: XCUIApplication) -> ((XCUIAccessibilityAuditIssue) -> Bool)? {
        { issue in
            guard issue.compactDescription == "Potentially inaccessible text", issue.element == nil else { return false }
            let sheet = app.descendants(matching: .any).matching(identifier: OuroSheetMetrics.accessibilityIdentifier).firstMatch
            return sheet.exists && sheet.frame.width < app.windows.firstMatch.frame.width - 1
        }
    }

    /// What the excused "Text clipped" could hide: the fitted sheet's last row and its action are on screen and
    /// reachable.
    @MainActor override class func afterAudit(_ app: XCUIApplication, _ run: GalleryAuditRun) {
        guard run.extra.isEmpty else { return }
        for control in ["Party food", "Save"] {
            XCTAssertTrue(app.buttons[control].firstMatch.isHittable, "\(run.name): \"\(control)\" is not reachable in the fitted sheet")
        }
    }
}
