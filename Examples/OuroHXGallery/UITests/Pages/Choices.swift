import OuroHX
import OuroHXTesting
import XCTest

final class ChoicesPageClaims: GalleryPageClaims {
    override class var page: String { "choices" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        // A segment is a button, the pressed one selected; a checkbox says its name, its state, and changes it.
        let grid = app.buttons["Grid"]
        XCTAssertTrue(grid.exists, "choices: no Grid segment")
        XCTAssertTrue(app.buttons["List"].isSelected, "choices: the pressed segment is not selected")
        grid.tap()
        XCTAssertTrue(grid.isSelected, "choices: pressing a segment does not select it")
        // XCUI lists a checkbox's toggle, its button and its words under one name; VoiceOver hears only the toggle.
        let terms = app.descendants(matching: .toggle)["I agree to the terms, required"]
        XCTAssertTrue(terms.exists, "choices: the checkbox is not named with required")
        XCTAssertEqual(terms.value as? String, "Not checked", "choices: the checkbox's value is \(String(describing: terms.value))")
        terms.tap()
        XCTAssertEqual(terms.value as? String, "Checked", "choices: checking does not check")
        XCTAssertEqual(app.descendants(matching: .toggle)["Whole basket"].value as? String, "Mixed", "choices: a partial select-all is not mixed")
    }

    /// The choices page's disabled segment and checkbox, faded as web fades them (`opacity-50`). WCAG 1.4.3 exempts
    /// text in an inactive control, so contrast is excused for them, by name and only on that page; every enabled
    /// segment and box on it is still audited.
    static let inactiveExamples: Set<String> = ["Board", "Archived"]
    @MainActor override class func excuse(_ app: XCUIApplication) -> ((XCUIAccessibilityAuditIssue) -> Bool)? {
        { issue in issue.auditType == .contrast && (issue.element.map { !$0.isEnabled || inactiveExamples.contains($0.label) } ?? false) }
    }
}
