import OuroHX
import OuroHXTesting
import XCTest

final class SyncStatusPageClaims: GalleryPageClaims {
    override class var page: String { "sync" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        // The line is words a reader can find; Retry is its own button, and pressing it saves.
        XCTAssertTrue(app.staticTexts["Not saved: the server refused the changes"].exists, "sync: the error is not text")
        let retry = app.buttons["Retry"]
        XCTAssertTrue(retry.exists, "sync: no Retry button")
        retry.tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 4), "sync: Retry did not save")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'checkmark'")).firstMatch.exists, "sync: the symbol is spoken")
    }
}
