import OuroHX
import OuroHXTesting
import UIKit
import XCTest

final class ButtonsPageClaims: GalleryPageClaims {
    override class var page: String { "buttons" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        for name in ["Save recipe", "Primary", "Destructive", "Glass pill", "Small", "Unavailable"] {
            XCTAssertTrue(app.buttons[name].firstMatch.exists, "buttons: no button named \"\(name)\"")
        }
    }

    /// The audit misreads words on Liquid Glass: on the gallery's glass row it reported white "Primary" on near-black
    /// glass (well over 15:1 in `gallery-r10/buttons-dark.png`) as failing contrast, and raising every glass label to
    /// 6:1 made it report more failures, not fewer (W8 evidence, taste round 5). So contrast on a glass button is
    /// measured from the screen's pixels instead (`inkContrast`, in `afterAudit`).
    @MainActor override class func excuse(_ app: XCUIApplication) -> ((XCUIAccessibilityAuditIssue) -> Bool)? {
        { issue in issue.auditType == .contrast && (issue.element?.identifier.hasPrefix("button.glass.") ?? false) }
    }

    /// What that excuse could hide: each glass button's words, measured from the screen's own pixels, read at 5:1
    /// against the glass under them.
    @MainActor override class func afterAudit(_ app: XCUIApplication, _ run: GalleryAuditRun) {
        let shot = app.windows.firstMatch.screenshot().image
        let glass = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'button.glass.'")).allElementsBoundByIndex
        var measured = 0
        for button in glass where app.windows.firstMatch.frame.contains(button.frame) {
            let ratio = ComponentClaimTests.inkContrast(shot, in: button.frame.insetBy(dx: 12, dy: 10))
            XCTAssertGreaterThanOrEqual(ratio, 5, "\(run.name): glass \(button.label) reads at \(ratio):1")
            measured += 1
        }
        // The glass row is shown first, so some of it is always on screen to measure.
        XCTAssertGreaterThan(measured, 0, "\(run.name): no glass button on screen to measure")
    }
}
