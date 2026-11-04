#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
public import XCTest
import OuroHX

extension XCUIApplication {
    /// Runs Xcode's accessibility audit (`performAccessibilityAudit`, iOS 17 and macOS 14) and fails on every issue
    /// except those whose description contains one of `knownIssues`, each of which should carry a reason in the test.
    ///
    /// It also excuses "Text clipped" inside an `.ouroSheet` below full height: iOS 26 and later draw such a sheet at
    /// 96% (``OuroSheetMetrics/drawnScale``), and the audit reads the scaled text as clipped. To check that sheet's
    /// text for real clipping, audit it again at full height (`detents: [.large]`), where it is drawn unscaled.
    @MainActor
    public func ouroAccessibilityAudit(
        for types: XCUIAccessibilityAuditType = .all,
        knownIssues: [String] = []
    ) throws {
        let window = windows.firstMatch.frame
        let scaledSheets = descendants(matching: .any)
            .matching(identifier: OuroSheetMetrics.accessibilityIdentifier)
            .allElementsBoundByIndex
            .map(\.frame)
            .filter { OuroSheetMetrics.isDrawnScaled(sheet: $0, in: window) }
        try performAccessibilityAudit(for: types) { issue in
            if knownIssues.contains(where: { issue.compactDescription.contains($0) || issue.detailedDescription.contains($0) }) {
                return true
            }
            if issue.compactDescription.contains("Text clipped"), let frame = issue.element?.frame {
                return scaledSheets.contains { $0.insetBy(dx: -1, dy: -1).contains(frame) }
            }
            return false
        }
    }
}
#endif
