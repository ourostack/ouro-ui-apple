import OuroHX
import OuroHXTesting
import XCTest

final class BadgesPageClaims: GalleryPageClaims {
    override class var page: String { "badges" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        // A badge is words, not a control: VoiceOver reads it with its row, and its icon stays out of the way.
        for variant in ["solid", "soft", "outline"] {
            XCTAssertTrue(app.descendants(matching: .any)["badges.\(variant)"].exists, "badges: no \(variant) row")
        }
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Lemon orzo with peas'")).firstMatch
        XCTAssertTrue(row.exists, "badges: the recipe row is not one element")
        XCTAssertTrue(row.label.contains("Vegan") && row.label.contains("25 min"), "badges: the row says \"\(row.label)\"")
        XCTAssertFalse(row.label.contains("leaf"), "badges: the decorative icon is spoken: \"\(row.label)\"")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Vegan'")).count, 0, "badges: a badge is not a button")
    }
}
