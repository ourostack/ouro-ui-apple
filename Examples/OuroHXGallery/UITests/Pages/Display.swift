import OuroHX
import OuroHXTesting
import XCTest

final class DisplayPageClaims: GalleryPageClaims {
    override class var page: String { "display" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        // A pair is heard as one; a pair whose details are a view keeps its parts; a line is silent, its label is not.
        XCTAssertTrue(app.descendants(matching: .any)["Prep time, 20 minutes"].exists, "display: a pair is not heard as one")
        XCTAssertTrue(app.staticTexts["Diet"].exists && app.descendants(matching: .any)["Vegan"].exists, "display: a pair with a view lost its parts")
        XCTAssertTrue(app.staticTexts["or"].exists, "display: a separator's label is not text")
    }
}
