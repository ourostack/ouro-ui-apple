#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
public import XCTest
import OuroHX

extension XCUIApplication {
    /// Runs Xcode's accessibility audit (`performAccessibilityAudit`, iOS 17 and macOS 14) and fails on every issue
    /// except those whose description contains one of `knownIssues`, each of which should carry a reason in the test.
    ///
    /// It also excuses "Contrast failed" on page content a toast covers, partly or wholly, and on an element mostly off the
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
        func scaledSheetFrames() -> [CGRect] {
            descendants(matching: .any)
                .matching(identifier: OuroSheetMetrics.accessibilityIdentifier)
                .allElementsBoundByIndex
                .filter { sheet in
                    let close = sheet.buttons.matching(identifier: OuroSheetMetrics.closeIdentifier).firstMatch
                    return close.exists && OuroSheetMetrics.isDrawnScaled(closeButtonHeight: close.frame.height)
                }
                .map(\.frame)
        }
        let scaledSheets = scaledSheetFrames()
        func toastFrames() -> (regions: [CGRect], contents: [CGRect]) {
            let toasts = [OuroToastMetrics.regionIdentifier, OuroToastMetrics.toastIdentifier].flatMap { id in
                descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex
            }
            // The toasts' own elements, so page content a toast covers wholly is told from the toast's words.
            return (toasts.map(\.frame), toasts.flatMap { $0.descendants(matching: .any).allElementsBoundByIndex.map(\.frame) })
        }
        let (toasts, toastContents) = toastFrames()
        let screen = windows.firstMatch.exists ? windows.firstMatch.frame : frame
        let handler: (XCUIAccessibilityAuditIssue) -> Bool = { issue in
            if knownIssues.contains(where: { issue.compactDescription.contains($0) || issue.detailedDescription.contains($0) }) {
                return true
            }
            if excuse?(issue) == true { return true }
            // A sheet can move while the audit runs (iOS 27: a medium-detent sheet with the keyboard up rose 33 points
            // during its text-size check), so clipped text is also judged against where the sheets are now.
            let sheetsNow = issue.compactDescription.contains("Text clipped") ? scaledSheets + scaledSheetFrames() : scaledSheets
            // Toasts move too (one times out, a stack expands), so contrast is also judged against where they are now:
            // a toast's own words match its elements before or now, and still fail.
            var toastsNow = toasts, contentsNow = toastContents
            if issue.auditType == .contrast {
                let now = toastFrames()
                toastsNow += now.regions
                contentsNow += now.contents
            }
            let excused = OuroAuditExcuse.excuses(issue.compactDescription, element: issue.element?.frame, scaledSheets: sheetsNow, toasts: toastsNow, toastContents: contentsNow, screen: screen)
            if !excused {
                // XCTest reports only "Contrast failed" for the issue; this names what it failed on, so a run on a
                // runtime you cannot run locally says which element (and where) the audit objected to.
                let element = issue.element
                print("audit issue failed: \(issue.compactDescription) | \(issue.detailedDescription) | type=\(issue.auditType.rawValue) | \(String(reflecting: issue)); element label=\"\(element?.label ?? "none")\" id=\"\(element?.identifier ?? "none")\" frame=\(element.map { "\($0.frame)" } ?? "none"); toasts=\(toastsNow); scaledSheets=\(sheetsNow); screen=\(screen)")
            }
            return excused
        }
        func audit(_ types: XCUIAccessibilityAuditType) throws {
            do {
                try performAccessibilityAudit(for: types, handler)
            } catch let error as NSError where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == Self.auditTimedOut {
                // A long page on a slow CI runner can outrun the audit's own time limit; one more try, then the error.
                try performAccessibilityAudit(for: types, handler)
            }
        }
        // iOS 26's combined audit can report a contrast issue without its element (CI, iOS 26.5: the expanded toast stack's
        // Undo), so no excuse can tell what it is about; the same issue in a contrast-only pass names it. Contrast is
        // audited on its own, and everything else together, so every type is still checked and every excuse still applies.
        let others = types.subtracting(.contrast)
        if types.contains(.contrast), !others.isEmpty {
            try audit(others)
            try audit(.contrast)
        } else {
            try audit(types)
        }
    }

    /// The audit's "Audit failed to complete in time" error code.
    static let auditTimedOut = -56
}
#endif
