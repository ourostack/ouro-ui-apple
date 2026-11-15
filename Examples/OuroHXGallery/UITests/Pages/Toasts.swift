import OuroHX
import OuroHXTesting
import UIKit
import XCTest

final class ToastsPageClaims: GalleryPageClaims {
    override class var page: String { "toasts" }

    @MainActor override class func voiceOver(_ app: XCUIApplication) {
        // Stacked, only the newest toast is shown; the older ones tuck behind it, out of VoiceOver's way. With
        // VoiceOver or Switch Control running the stack opens by itself; here a tap opens it.
        XCTAssertEqual(shownDismissButtons(app), 1, "only the front toast is shown")
        expand(app)
        XCTAssertTrue(app.buttons["Undo"].exists)
        XCTAssertEqual(shownDismissButtons(app), 3, "every toast has a dismiss button")
        XCTAssertTrue(app.otherElements["Notifications"].exists || app.descendants(matching: .any)["Notifications"].exists, "the toasts' region is named")
    }

    /// The toasts page pushes its toasts at launch. On a loaded runner two seconds have caught the stack still arriving,
    /// its region 8 points tall, and the audit read that sliver as "Potentially inaccessible text" with no element.
    /// So the audit waits until the stack's region is at least 44 points tall and has held still for half a second. (The
    /// region is the element to watch: XCUI doesn't always list the toasts inside it by their own identifier.)
    @MainActor override class func settle(_ app: XCUIApplication) {
        let timeout: TimeInterval = 15
        let region = app.descendants(matching: .any).matching(identifier: OuroToastMetrics.regionIdentifier).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        var last: [CGRect] = []
        while Date() < deadline {
            let frames = [region.exists ? region.frame : .zero]
            if frames[0].height >= 44, frames == last { return }
            last = frames
            usleep(500_000)
        }
        XCTFail("toasts: the stack had not settled after \(Int(timeout)) seconds: \(last)")
    }

    @MainActor override class func excuse(_ app: XCUIApplication) -> ((XCUIAccessibilityAuditIssue) -> Bool)? { glassMisreadings(app) }

    /// Expanded, as VoiceOver users always see the stack, at the default size: every toast's own words are audited,
    /// and every toast's buttons are full targets a finger can reach, which is what the expanded stack's excuses could
    /// hide.
    @MainActor override class func afterAudit(_ app: XCUIApplication, _ run: GalleryAuditRun) {
        guard run.size == nil else { return }
        expand(app)
        XCTContext.runActivity(named: "\(run.name) expanded") { _ in
            do { try app.ouroAccessibilityAudit(excuse: { expandedStackMisreadings($0) || glassMisreadings(app)($0) }) } catch { XCTFail("\(run.name) expanded: \(error)") }
        }
        for button in app.buttons.matching(NSPredicate(format: "label IN %@", ["Dismiss", "Undo"])).allElementsBoundByIndex {
            XCTAssertTrue(button.isHittable, "\(run.name) expanded: \(button.label) is not reachable")
            XCTAssertGreaterThanOrEqual(min(button.frame.width, button.frame.height), 44, "\(run.name) expanded: \(button.label) is \(button.frame.size)")
        }
    }

    /// iOS 27's audit reads a toast's words on glass as failing contrast though the screen shows them above 5:1 (the
    /// dark error toast's description, 5.65:1 measured from a screenshot; the message, near white, 14.9:1). Excused
    /// only for words inside a toast, and only when their own pixels, measured from the screen as the audit runs,
    /// read at 5:1 or more, each line of ink on its own (a message and its description are one element, so measured
    /// together the message's ink could carry a faint description): the claim itself, held another way.
    @MainActor static func glassMisreadings(_ app: XCUIApplication) -> (XCUIAccessibilityAuditIssue) -> Bool {
        { issue in
            guard issue.auditType == .contrast, let element = issue.element, element.exists else { return false }
            let frame = element.frame
            let toasts = app.descendants(matching: .any).matching(identifier: OuroToastMetrics.toastIdentifier).allElementsBoundByIndex.map(\.frame)
            guard !frame.isEmpty, toasts.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(frame) }) else { return false }
            // The toast's message line (`.subheadline`) is its tallest, at the size the app runs at.
            let size = app.launchArguments.firstIndex(of: "-UIPreferredContentSizeCategoryName")
                .flatMap { app.launchArguments.indices.contains($0 + 1) ? UIContentSizeCategory(rawValue: app.launchArguments[$0 + 1]) : nil } ?? .large
            let line = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: UITraitCollection(preferredContentSizeCategory: size)).lineHeight
            let ratio = ComponentClaimTests.lineInkContrast(app.windows.firstMatch.screenshot().image, in: frame, lineHeight: line)
            print("toast words \"\(element.label)\" read at \(ratio):1 on screen")
            return ratio >= 5
        }
    }

    /// Two readings the audit gets wrong on an expanded stack (W8, 2026-11-04, with diagnostics of each issue's
    /// element): it fails Undo's contrast even with Undo drawn black on the white surface (21:1), and reads the oldest
    /// toast's plain words, a static text with no action, as an undersized target, with a second such issue that has
    /// no element at all. Contrast is proven by the palette tests; the targets by the assertions after the audit.
    @MainActor static let expandedStackMisreadings: (XCUIAccessibilityAuditIssue) -> Bool = { issue in
        switch issue.auditType {
        case .contrast: issue.element?.label == "Undo"
        case .hitRegion: issue.element == nil || issue.element?.elementType == .staticText
        default: false
        }
    }

    /// Opens the toast stack by tapping its front toast, the newest, "Couldn’t save".
    @MainActor static func expand(_ app: XCUIApplication) {
        app.staticTexts["Couldn\u{2019}t save"].tap()
        // Until the stack has fanned out and its words have faded in: an audit mid-way reads fading words and moving
        // targets (CI failed it after a fixed second).
        var last: [CGRect] = []
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.25)
            let frames = app.buttons.matching(identifier: "Dismiss").allElementsBoundByIndex.map(\.frame)
            if frames.count == 3, frames == last { break }
            last = frames
        }
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(shownDismissButtons(app), 3, "a tap opens the stack")
    }

    /// Toasts' close buttons a finger can reach: the shown toasts' (a tucked one draws no buttons).
    @MainActor static func shownDismissButtons(_ app: XCUIApplication) -> Int {
        app.buttons.matching(identifier: "Dismiss").allElementsBoundByIndex.filter(\.isHittable).count
    }
}
