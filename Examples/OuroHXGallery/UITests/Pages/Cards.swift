import OuroHX
import OuroHXTesting
import XCTest

final class CardsPageClaims: GalleryPageClaims {
    override class var page: String { "cards" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        // A card's title is text VoiceOver reads (a heading; the audit checks traits), and its action is a button.
        XCTAssertTrue(app.staticTexts["Pantry"].exists, "cards: no title")
        XCTAssertTrue(app.staticTexts["What you have on hand"].exists, "cards: no description")
        XCTAssertTrue(app.buttons["Edit"].exists, "cards: the action is not a button")
        XCTAssertTrue(app.buttons["Start cooking"].exists)
        // A pressable card is one button, named by its title and description, as web's stretched link.
        let linked = app.buttons["card.media"]
        XCTAssertTrue(linked.exists, "cards: the pressable card is not a button")
        XCTAssertTrue(linked.label.contains("Weeknight dinners"), "cards: the pressable card is not named by its title: \(linked.label)")
    }
}
