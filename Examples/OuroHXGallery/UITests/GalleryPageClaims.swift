import OuroHXTesting
import XCTest

/// A component page's part in `ComponentClaimTests`: what VoiceOver must find on it, which of the audit's misreadings
/// it excuses, and what it checks after the audit to prove those excuses hide nothing. Each page is a subclass in its
/// own file under `Pages/`, found when the tests start, so a new component adds one file and edits no shared list. Its
/// gallery page registers the same way (`Sources/Pages/`, `GalleryComponentPage`), and `scripts/ui-shards.py check`
/// fails when a page has one and not the other.
class GalleryPageClaims: NSObject {
    /// The gallery page, as `-page` opens it and the audit's activities name it.
    class var page: String { fatalError("\(self) must name its page") }

    /// Each way the audit opens the page: a suffix for the activity's name and extra launch arguments. Most pages are
    /// audited once; the sheet also at full height.
    class var auditVariants: [(suffix: String, extra: [String])] { [("", [])] }

    /// Claim name.spoken: VoiceOver finds each control by the name it speaks, as a button, and each title as text.
    /// Every page proves it, so a new page must too.
    @MainActor class func voiceOver(_ app: XCUIApplication) { fatalError("\(self) must check what VoiceOver finds") }

    /// What the audit misreads on this page and may excuse, each with its reason; nil excuses nothing.
    @MainActor class func excuse(_ app: XCUIApplication) -> ((XCUIAccessibilityAuditIssue) -> Bool)? { nil }

    /// Waits after launch until the page has settled, before anything reads it.
    @MainActor class func settle(_ app: XCUIApplication) {}

    /// Runs after each audit run: what an excuse could hide, checked another way.
    @MainActor class func afterAudit(_ app: XCUIApplication, _ run: GalleryAuditRun) {}

    /// Every page's claims, by page.
    @MainActor static let all: [GalleryPageClaims.Type] = subclasses(of: GalleryPageClaims.self).sorted { $0.page < $1.page }

    @MainActor static func named(_ page: String) -> GalleryPageClaims.Type? { all.first { $0.page == page } }
}

/// One run of the accessibility audit: its activity's name, its text size (nil for the default) and its launch arguments.
struct GalleryAuditRun {
    let name: String
    let size: String?
    let extra: [String]
}
