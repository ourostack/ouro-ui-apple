public import CoreGraphics
import OuroHX

/// What `ouroAccessibilityAudit` excuses beyond the known issues a test names, and nothing else:
///
/// - "Text clipped" on an element wholly inside an `.ouroSheet` drawn at 96% (see
///   `OuroSheetMetrics.isDrawnScaled(closeButtonHeight:)`), which Xcode's audit reads as clipped because of the scale.
/// - "Contrast failed" on page content that an Ouro toast, or its shadow (`OuroToastMetrics.shadowReach`), partly
///   covers: the audit measures the page's words with the toast over them. `toasts` are each toast's own frame (and
///   the region's); words wholly inside any of them are a toast's own, and still fail, unless `toastContents` names
///   the toasts' own elements: then only those are, and page content a toast covers wholly is excused too.
/// - "Contrast failed" on an element mostly off the screen (under the home indicator, barely scrolled into view),
///   whose words the audit cannot see to measure. One more than half on screen still fails.
///
/// An issue of another kind, or one with no element, still fails.
public enum OuroAuditExcuse {
    /// `toastContents`, the frames of the toasts' own elements, when known, lets page content a toast covers wholly
    /// (its title, at the largest sizes) be told from the toast's own words; without them, anything wholly inside a
    /// toast counts as the toast's.
    public static func excuses(_ issue: String, element: CGRect?, scaledSheets: [CGRect], toasts: [CGRect] = [],
                               toastContents: [CGRect]? = nil, screen: CGRect? = nil) -> Bool {
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
            } && !isToastsOwn(element, toasts: toasts, contents: toastContents)
            let offScreen = screen.map { screen in
                let shown = screen.intersection(element)
                return shown.isNull || shown.width * shown.height < element.width * element.height / 2
            } ?? false
            return underToast || offScreen
        }
        return false
    }

    private static func isToastsOwn(_ element: CGRect, toasts: [CGRect], contents: [CGRect]?) -> Bool {
        guard let contents else { return toasts.contains { $0.insetBy(dx: -1, dy: -1).contains(element) } }
        return contents.contains { abs($0.minX - element.minX) < 1 && abs($0.minY - element.minY) < 1
            && abs($0.width - element.width) < 1 && abs($0.height - element.height) < 1 }
    }
}
