#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
public import XCTest
import OuroHX

extension XCUIApplication {
    /// Runs Xcode's accessibility audit (`performAccessibilityAudit`, iOS 17 and macOS 14) and fails on every issue
    /// except those whose description contains one of `knownIssues`, each of which should carry a reason in the test.
    ///
    /// It also excuses "Text clipped" inside an `.ouroSheet` that iOS draws at 96%, a sheet below full height on
    /// iOS 26 and later (see ``OuroAuditExcuse``), because the audit reads the scaled text as clipped. That leaves real
    /// clipping in such a sheet unchecked, so audit it once more at full height: present it with `detents: [.large]`
    /// from a launch argument your app reads, as the gallery's `-sheetDetent large` does.
    @MainActor
    public func ouroAccessibilityAudit(
        for types: XCUIAccessibilityAuditType = .all,
        knownIssues: [String] = []
    ) throws {
        let scaledSheets = descendants(matching: .any)
            .matching(identifier: OuroSheetMetrics.accessibilityIdentifier)
            .allElementsBoundByIndex
            .filter { sheet in
                let close = sheet.buttons.matching(identifier: OuroSheetMetrics.closeIdentifier).firstMatch
                return close.exists && OuroSheetMetrics.isDrawnScaled(closeButtonHeight: close.frame.height)
            }
            .map(\.frame)
        let handler: (XCUIAccessibilityAuditIssue) -> Bool = { issue in
            if knownIssues.contains(where: { issue.compactDescription.contains($0) || issue.detailedDescription.contains($0) }) {
                return true
            }
            return OuroAuditExcuse.excuses(issue.compactDescription, element: issue.element?.frame, scaledSheets: scaledSheets)
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
