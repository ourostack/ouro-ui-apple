import OuroHX
import OuroHXTesting
import XCTest

final class EmptyStatesPageClaims: GalleryPageClaims {
    override class var page: String { "empty" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["No recipes yet"].exists)
        XCTAssertTrue(app.buttons["Create recipe"].exists)
        // The icon is accessibilityHidden; XCUITest's tree still lists hidden images, so the audit's
        // sufficientElementDescription run, not an element query, is what checks it stays out of VoiceOver's way.
    }
}
