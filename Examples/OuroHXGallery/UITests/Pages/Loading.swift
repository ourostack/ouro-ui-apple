import OuroHX
import OuroHXTesting
import XCTest

final class LoadingPageClaims: GalleryPageClaims {
    override class var page: String { "loading" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        // A spinner says what it waits for; a bar says what it is and how far along; a skeleton says Loading once.
        XCTAssertTrue(app.descendants(matching: .any)["Saving the draft"].firstMatch.exists, "loading: the spinner is not named")
        // XCUI lists the bar and the views inside it under one name; the bar is the one with a value.
        func bar(_ name: String) -> XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value != nil", name)).firstMatch }
        let upload = bar("Uploading photos")
        XCTAssertTrue(upload.exists, "loading: the bar is not named")
        XCTAssertEqual(upload.value as? String, "38%", "loading: the bar's value is \(String(describing: upload.value))")
        XCTAssertEqual(bar("Preparing your cookbook").value as? String, "Loading", "loading: an unknown value is not Loading")
        XCTAssertGreaterThan(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Loading'")).count, 0, "loading: a skeleton is silent")
    }
}
