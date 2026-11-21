import OuroHX
import OuroHXTesting
import UIKit
import XCTest

final class ImmersiveControlsPageClaims: GalleryPageClaims {
    override class var page: String { "immersive" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        // The bars' controls are buttons named by their words, never their icons; the picture under them is one button.
        for name in names {
            XCTAssertTrue(app.buttons[name].exists, "immersive: no \(name) button")
        }
        XCTAssertTrue(app.buttons["immersive.content"].exists, "immersive: the picture is not one button")
    }

    /// The audit misreads words on Liquid Glass (see `ButtonsPageClaims.excuse`), so contrast on the bars' glass buttons
    /// is measured from the screen's pixels instead, in `afterAudit`.
    /// The audit reports them by name, with no identifier (a node inside the bar's glass container).
    @MainActor override class func excuse(_ app: XCUIApplication) -> ((XCUIAccessibilityAuditIssue) -> Bool)? {
        { issue in issue.auditType == .contrast && names.contains(issue.element?.label ?? "") }
    }

    static let names = ["Close", "Share", "Edit", "Favourite"]

    /// What that excuse could hide: each glass button's ink, measured from the screen's own pixels, at 5:1 against the
    /// glass under it.
    @MainActor override class func afterAudit(_ app: XCUIApplication, _ run: GalleryAuditRun) {
        let shot = app.windows.firstMatch.screenshot().image
        var measured = 0
        for button in names.map({ app.buttons[$0].firstMatch }) where button.exists && app.windows.firstMatch.frame.contains(button.frame) {
            let ratio = ComponentClaimTests.inkContrast(shot, in: button.frame.insetBy(dx: 10, dy: 10))
            XCTAssertGreaterThanOrEqual(ratio, 5, "\(run.name): glass \(button.label) reads at \(ratio):1")
            measured += 1
        }
        XCTAssertGreaterThan(measured, 0, "\(run.name): no glass button on screen to measure")
    }
}
