import OuroHX
import OuroHXTesting
import XCTest

final class BannersPageClaims: GalleryPageClaims {
    override class var page: String { "banners" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Dismiss"].exists, "the dismissible banner's close button")
        XCTAssertTrue(app.buttons["Try again"].exists)
    }
}
