import OuroHX
import OuroHXTesting
import XCTest

final class ItemsPageClaims: GalleryPageClaims {
    override class var page: String { "items" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        // A pressable row is one button named by its title and description; its actions stay their own buttons, and
        // its icon tile is not spoken.
        let soup = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Black bean soup'")).firstMatch
        XCTAssertTrue(soup.exists, "items: the pressable row is not a button")
        XCTAssertTrue(soup.label.contains("40 minutes"), "items: the row says \"\(soup.label)\"")
        XCTAssertTrue(app.buttons["Cook"].exists, "items: the row's action is not its own button")
        XCTAssertTrue(app.staticTexts["Braised short ribs"].exists || app.descendants(matching: .any)["Braised short ribs, 3 hours, serves six"].exists, "items: no title")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'flame'")).firstMatch.exists, "items: the decorative icon is spoken")
    }
}
