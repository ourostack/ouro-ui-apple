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
        // The sheets, the toasts and the window are read from one snapshot of the app, not from element queries. A query
        // that times out on a loaded runner records a test failure that nothing can catch or retry (CI, iPhone, the
        // buttons page at the largest text size: "Failed to resolve query: Timed out while evaluating UI query", main
        // runs 43731240135 and 43732729372); a snapshot throws, so it gets two more tries before its error is thrown.
        func firstSnapshot(attempt: Int = 1) throws -> any XCUIElementSnapshot {
            do { return try snapshot() } catch {
                if attempt == Self.snapshotTries { throw error }
                Thread.sleep(forTimeInterval: 5)
                return try firstSnapshot(attempt: attempt + 1)
            }
        }
        let first = OuroAuditFrames(try firstSnapshot())
        let scaledSheets = first.scaledSheets
        let (toasts, toastContents) = (first.toasts, first.toastContents)
        let screen = first.window ?? frame
        // Read again while the audit runs, for an issue that moved; a snapshot that fails then leaves the first frames.
        func now() -> OuroAuditFrames? { (try? snapshot()).map(OuroAuditFrames.init) }
        let handler: (XCUIAccessibilityAuditIssue) -> Bool = { issue in
            if knownIssues.contains(where: { issue.compactDescription.contains($0) || issue.detailedDescription.contains($0) }) {
                return true
            }
            if excuse?(issue) == true { return true }
            // A sheet can move while the audit runs (iOS 27: a medium-detent sheet with the keyboard up rose 33 points
            // during its text-size check), so clipped text is also judged against where the sheets are now.
            let sheetsNow = issue.compactDescription.contains("Text clipped") ? scaledSheets + (now()?.scaledSheets ?? []) : scaledSheets
            // Toasts move too (one times out, a stack expands), so contrast is also judged against where they are now:
            // a toast's own words match its elements before or now, and still fail.
            var toastsNow = toasts, contentsNow = toastContents
            if issue.auditType == .contrast {
                if let now = now() {
                    toastsNow += now.toasts
                    contentsNow += now.toastContents
                }
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

    /// How many times the audit tries to snapshot the app before it gives up.
    static let snapshotTries = 3
}

/// Where the sheets, the toasts and the window are in one snapshot of the app, for the audit's excuses.
@MainActor
struct OuroAuditFrames {
    /// Each `.ouroSheet` that iOS draws scaled, judged by its close button's height.
    var scaledSheets: [CGRect] = []
    /// Each toast region and toast.
    var toasts: [CGRect] = []
    /// Every element inside a toast region or toast, so page content a toast covers wholly is told from its words.
    var toastContents: [CGRect] = []
    /// The app's first window.
    var window: CGRect?

    init(_ app: any XCUIElementSnapshot) {
        window = app.children.first { $0.elementType == .window }?.frame
        func descendants(_ e: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] { e.children.flatMap { [$0] + descendants($0) } }
        for e in descendants(app) {
            if e.identifier == OuroSheetMetrics.accessibilityIdentifier,
               let close = descendants(e).first(where: { $0.elementType == .button && $0.identifier == OuroSheetMetrics.closeIdentifier }),
               OuroSheetMetrics.isDrawnScaled(closeButtonHeight: close.frame.height) {
                scaledSheets.append(e.frame)
            }
        }
        for id in [OuroToastMetrics.regionIdentifier, OuroToastMetrics.toastIdentifier] {
            for e in descendants(app) where e.identifier == id {
                toasts.append(e.frame)
                toastContents += descendants(e).map { $0.frame }
            }
        }
    }
}
#endif
