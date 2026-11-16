import OuroHX
import OuroHXTesting
import XCTest

final class AvatarsPageClaims: GalleryPageClaims {
    override class var page: String { "avatars" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        // An avatar is an image named by its person, then its presence; its initials are drawn, not read; one beside
        // its name is not read twice; one still loading says so.
        XCTAssertTrue(app.images["Ana Lind"].exists, "avatars: no image named Ana Lind")
        XCTAssertTrue(app.images["Ana Lind, Busy"].exists, "avatars: the presence is not read after the name")
        // Each presence reads as words, never as code.
        XCTAssertTrue(app.images["Ana Lind, Do not disturb"].exists, "avatars: do not disturb is not read as words")
        XCTAssertTrue(app.images["Name loading"].exists, "avatars: a loading avatar is silent")
        // XCUI lists the drawn initials under the avatar even though the avatar ignores its children, so VoiceOver's
        // reading is proven by the image's name above, not by the initials' absence here.
        // The sizes row has its own Kenji Sato; the row beside the name is one element, read once.
        XCTAssertEqual(app.images.matching(NSPredicate(format: "label == 'Kenji Sato'")).count, 1, "avatars: a name beside its avatar is read twice")
        XCTAssertTrue(app.descendants(matching: .any)["Kenji Sato, 12 recipes"].firstMatch.exists, "avatars: a name beside its avatar is not one element")
    }

    /// An avatar's initials are drawn in its fixed-size tile, as web's are: they grow with Dynamic Type until they fill
    /// it, then hold (`OuroAvatarMetrics.initialsMinimumScale`), so the audit reads them as "partially unsupported".
    /// VoiceOver never reads them (the avatar is one image named by its person), and a tile that grew with the text
    /// would break every row it sits in. Excused for one or two capital letters on the avatars page only.
    @MainActor override class func excuse(_ app: XCUIApplication) -> ((XCUIAccessibilityAuditIssue) -> Bool)? {
        { issue in issue.auditType == .dynamicType && (issue.element.map { $0.label.range(of: "^[A-Z]{1,2}$", options: .regularExpression) != nil } ?? false) }
    }
}
