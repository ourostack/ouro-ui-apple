import OuroHX
import OuroHXTesting
import UIKit
import XCTest

final class TextFieldsPageClaims: GalleryPageClaims {
    override class var page: String { "textfields" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        // A field is named by its label, never its placeholder, keeps the label with hideLabel, says it is required,
        // and reads its error; its buttons are named.
        XCTAssertTrue(app.textFields["Email, required"].exists, "textfields: no field named \"Email, required\"")
        XCTAssertTrue(app.secureTextFields["Password"].exists, "textfields: the password is not a secure field named Password")
        XCTAssertTrue(app.buttons["Show password"].exists, "textfields: no show password button")
        XCTAssertTrue(app.textFields["Search recipes"].exists, "textfields: a hidden label is not the field's name")
        XCTAssertTrue(app.buttons["Clear"].exists, "textfields: no clear button while the search has text")
        let titleField = app.textFields["Recipe title, required"]
        XCTAssertTrue(titleField.exists, "textfields: no recipe title field")
        // XCUI's subscript also matches a placeholder, so the name is read from `label`.
        XCTAssertFalse(app.textFields.matching(NSPredicate(format: "label == %@", "Lemon orzo with peas")).firstMatch.exists, "textfields: a placeholder is a field's name")
        app.buttons["Show password"].tap()
        XCTAssertTrue(app.textFields["Password"].waitForExistence(timeout: 2), "textfields: show password does not show it")
        app.buttons["Clear"].tap()
        XCTAssertFalse(app.buttons["Clear"].waitForExistence(timeout: 1), "textfields: clear did not empty the search")
    }

    /// A single-line field scrolls its text sideways, as every platform's input does, and the audit reads every
    /// `UITextField` as "Text clipped". It is excused only for a field at least a line of its text tall at the size
    /// the app runs at, so a field that didn't grow with Dynamic Type still fails.
    @MainActor override class func excuse(_ app: XCUIApplication) -> ((XCUIAccessibilityAuditIssue) -> Bool)? {
        { issue in
            guard issue.auditType == .textClipped, let element = issue.element, element.exists,
                  [.textField, .secureTextField].contains(element.elementType) else { return false }
            let size = app.launchArguments.firstIndex(of: "-UIPreferredContentSizeCategoryName")
                .flatMap { app.launchArguments.indices.contains($0 + 1) ? UIContentSizeCategory(rawValue: app.launchArguments[$0 + 1]) : nil } ?? .large
            let line = UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: size)).lineHeight
            return element.frame.height >= line - 1
        }
    }
}
