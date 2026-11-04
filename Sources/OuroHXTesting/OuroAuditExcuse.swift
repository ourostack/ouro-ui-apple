public import CoreGraphics

/// What `ouroAccessibilityAudit` excuses beyond the known issues a test names: "Text clipped" on an element wholly
/// inside an `.ouroSheet` drawn at 96% (see `OuroSheetMetrics.isDrawnScaled(closeButtonHeight:)`), which Xcode's
/// audit reads as clipped because of the scale. Nothing else: an issue of another kind, one with no element, or one
/// whose element reaches outside the sheet still fails.
public enum OuroAuditExcuse {
    public static func excuses(_ issue: String, element: CGRect?, scaledSheets: [CGRect]) -> Bool {
        guard issue.contains("Text clipped"), let element, !element.isEmpty else { return false }
        return scaledSheets.contains { $0.insetBy(dx: -1, dy: -1).contains(element) }
    }
}
