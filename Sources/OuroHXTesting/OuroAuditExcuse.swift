public import CoreGraphics
import OuroHX

/// What `ouroAccessibilityAudit` excuses beyond the known issues a test names, and nothing else:
///
/// - "Text clipped" on an element wholly inside an `.ouroSheet` drawn at 96% (see
///   `OuroSheetMetrics.isDrawnScaled(closeButtonHeight:)`), which Xcode's audit reads as clipped because of the scale.
/// - "Contrast failed" on page content that an Ouro toast, or its shadow (`OuroToastMetrics.shadowReach`), partly
///   covers: the audit measures the page's words with the toast over them. `toasts` are each toast's own frame (and
///   the region's); words wholly inside any of them are a toast's own, and still fail.
/// - "Contrast failed" on an element mostly off the screen (under the home indicator, barely scrolled into view),
///   whose words the audit cannot see to measure. One more than half on screen still fails.
///
/// An issue of another kind, or one with no element, still fails.
public enum OuroAuditExcuse {
    public static func excuses(_ issue: String, element: CGRect?, scaledSheets: [CGRect], toasts: [CGRect] = [], screen: CGRect? = nil) -> Bool {
        guard let element, !element.isEmpty else { return false }
        if issue.contains("Text clipped") {
            return scaledSheets.contains { $0.insetBy(dx: -1, dy: -1).contains(element) }
        }
        if issue.contains("Contrast failed") {
            let reach = OuroToastMetrics.shadowReach
            // The region and its shadow, which falls to the sides and below it.
            let underToast = toasts.contains { (region: CGRect) -> Bool in
                let footprint = CGRect(x: region.minX - reach, y: region.minY, width: region.width + 2 * reach, height: region.height + reach)
                return footprint.intersects(element)
            } && !toasts.contains { $0.insetBy(dx: -1, dy: -1).contains(element) }
            let offScreen = screen.map { screen in
                let shown = screen.intersection(element)
                return shown.isNull || shown.width * shown.height < element.width * element.height / 2
            } ?? false
            return underToast || offScreen
        }
        return false
    }
}

