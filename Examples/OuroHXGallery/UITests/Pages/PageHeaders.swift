import OuroHX
import OuroHXTesting
import XCTest

final class PageHeadersPageClaims: GalleryPageClaims {
    override class var page: String { "pageheaders" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        // A header's title is a heading; its actions are buttons; its picture is not spoken.
        let heading = app.staticTexts["Lemon orzo with peas"]
        XCTAssertTrue(heading.exists, "pageheaders: no title")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Lemon orzo with peas'")).allElementsBoundByIndex.contains { $0.elementType == .staticText }, "pageheaders: the title is not text")
        XCTAssertTrue(app.buttons["Cook"].exists && app.buttons["Share"].exists, "pageheaders: an action is not a button")
        XCTAssertTrue(app.staticTexts["Shopping list"].exists, "pageheaders: no section title")
    }
}
