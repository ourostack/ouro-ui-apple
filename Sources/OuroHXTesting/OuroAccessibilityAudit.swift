#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
public import XCTest
import OuroHX

extension XCUIApplication {
    /// Runs Xcode's accessibility audit (`performAccessibilityAudit`, iOS 17 and macOS 14) and fails on every issue
    /// except those whose description contains one of `knownIssues`, each of which should carry a reason in the test.
    ///
    /// It also excuses "Contrast failed" on page content a toast partly covers and on an element mostly off the
    /// screen (see ``OuroAuditExcuse``), and "Text clipped" inside an `.ouroSheet` that iOS draws at 96%, a sheet below full height on
    /// iOS 26 and later (see ``OuroAuditExcuse``), because the audit reads the scaled text as clipped. That leaves real
    /// clipping in such a sheet unchecked, so audit it once more at full height: present it with `detents: [.large]`
    /// from a launch argument your app reads, as the gallery's `-sheetDetent large` does.
    ///
    /// `excuse` excuses single issues the audit is known to misread, by element; say why in the test and prove what it
    /// hides another way.
    @MainActor
    public func ouroAccessibilityAudit(
        for types: XCUIAccessibilityAuditType = .all,
        knownIssues: [String] = [],
        excuse: ((XCUIAccessibilityAuditIssue) -> Bool)? = nil
    ) throws {
        let scaledSheets = descendants(matching: .any)
            .matching(identifier: OuroSheetMetrics.accessibilityIdentifier)
            .allElementsBoundByIndex
            .filter { sheet in
                let close = sheet.buttons.matching(identifier: OuroSheetMetrics.closeIdentifier).firstMatch
                return close.exists && OuroSheetMetrics.isDrawnScaled(closeButtonHeight: close.frame.height)
            }
            .map(\.frame)
        let toasts = [OuroToastMetrics.regionIdentifier, OuroToastMetrics.toastIdentifier].flatMap { id in
            descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex.map(\.frame)
        }
        let screen = windows.firstMatch.exists ? windows.firstMatch.frame : frame
        let handler: (XCUIAccessibilityAuditIssue) -> Bool = { issue in
            if knownIssues.contains(where: { issue.compactDescription.contains($0) || issue.detailedDescription.contains($0) }) {
                return true
            }
            if excuse?(issue) == true { return true }
            return OuroAuditExcuse.excuses(issue.compactDescription, element: issue.element?.frame, scaledSheets: scaledSheets, toasts: toasts, screen: screen)
        }
        do {
            try performAccessibilityAudit(for: types, handler)
        } catch let error as NSError where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == Self.auditTimedOut {
            // A long page on a slow CI runner can outrun the audit's own time limit; one more try, then the error.
            try performAccessibilityAudit(for: types, handler)
        }
    }

    /// The audit's "Audit failed to complete in time" error code.
    static let auditTimedOut = -56
}
#endif
