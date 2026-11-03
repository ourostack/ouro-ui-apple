#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
public import XCTest

extension XCUIApplication {
    /// Runs Xcode's accessibility audit (`performAccessibilityAudit`, iOS 17 and macOS 14) and fails on every issue
    /// except those whose description contains one of `knownIssues`, each of which should carry a reason in the test.
    @MainActor
    public func ouroAccessibilityAudit(
        for types: XCUIAccessibilityAuditType = .all,
        knownIssues: [String] = []
    ) throws {
        try performAccessibilityAudit(for: types) { issue in
            knownIssues.contains { issue.compactDescription.contains($0) || issue.detailedDescription.contains($0) }
        }
    }
}
#endif
