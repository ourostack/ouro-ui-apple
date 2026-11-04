import CoreGraphics
import OuroHX
import OuroHXTesting
import Testing

/// What `ouroAccessibilityAudit` excuses: "Text clipped" wholly inside a sheet drawn at 96%; "Contrast failed" on page
/// content a toast covers, or on an element only partly on screen; and nothing else.
@Suite struct AuditExcuseTests {
    let sheet = CGRect(x: 8, y: 500, width: 386, height: 374)

    @Test func clippingInsideAScaledSheetIsExcused() {
        #expect(OuroAuditExcuse.excuses("Text clipped", element: CGRect(x: 27, y: 640, width: 200, height: 20), scaledSheets: [sheet]))
    }

    @Test func clippingThatSpillsOutOfTheSheetIsNot() {
        #expect(!OuroAuditExcuse.excuses("Text clipped", element: CGRect(x: 27, y: 480, width: 200, height: 40), scaledSheets: [sheet]))
    }

    @Test func clippingOutsideEverySheetIsNot() {
        #expect(!OuroAuditExcuse.excuses("Text clipped", element: CGRect(x: 27, y: 100, width: 200, height: 20), scaledSheets: [sheet]))
        #expect(!OuroAuditExcuse.excuses("Text clipped", element: CGRect(x: 27, y: 640, width: 200, height: 20), scaledSheets: []))
    }

    @Test func anIssueWithNoElementIsNot() {
        #expect(!OuroAuditExcuse.excuses("Text clipped", element: nil, scaledSheets: [sheet]))
    }

    @Test func otherIssuesInsideTheSheetAreNot() {
        for issue in ["Contrast failed", "Hit region too small", "Dynamic Type font sizes are partially unsupported"] {
            #expect(!OuroAuditExcuse.excuses(issue, element: CGRect(x: 27, y: 640, width: 200, height: 20), scaledSheets: [sheet]), "\(issue)")
        }
    }

    let toasts = CGRect(x: 16, y: 54, width: 370, height: 80)
    let screen = CGRect(x: 0, y: 0, width: 402, height: 874)

    @Test func pageContentPartlyUnderAToastIsExcusedForContrast() {
        #expect(OuroAuditExcuse.excuses("Contrast failed", element: CGRect(x: 16, y: 120, width: 260, height: 20), scaledSheets: [], toasts: [toasts], screen: screen))
    }

    @Test func pageContentInAToastsShadowIsExcusedForContrast() {
        // Just below the region, where the toast's soft shadow falls on the page.
        let below = CGRect(x: 16, y: toasts.maxY + 8, width: 100, height: 24)
        #expect(OuroAuditExcuse.excuses("Contrast failed", element: below, scaledSheets: [], toasts: [toasts], screen: screen))
        let beyond = CGRect(x: 16, y: toasts.maxY + OuroToastMetrics.shadowReach + 4, width: 100, height: 24)
        #expect(!OuroAuditExcuse.excuses("Contrast failed", element: beyond, scaledSheets: [], toasts: [toasts], screen: screen))
    }

    @Test func aToastsOwnWordsAreNot() {
        // Wholly inside the toast region: the toast's own text must read.
        #expect(!OuroAuditExcuse.excuses("Contrast failed", element: CGRect(x: 60, y: 70, width: 200, height: 20), scaledSheets: [], toasts: [toasts], screen: screen))
    }

    @Test func contrastAwayFromToastsAndOnScreenIsNot() {
        #expect(!OuroAuditExcuse.excuses("Contrast failed", element: CGRect(x: 16, y: 300, width: 260, height: 20), scaledSheets: [], toasts: [toasts], screen: screen))
    }

    @Test func anElementPartlyOffScreenIsExcusedForContrast() {
        #expect(OuroAuditExcuse.excuses("Contrast failed", element: CGRect(x: 16, y: 850, width: 120, height: 50), scaledSheets: [], toasts: [], screen: screen))
    }

    @Test func onlyContrastIsExcusedUnderAToastOrOffScreen() {
        for issue in ["Hit area is too small", "Text clipped", "Element has no description"] {
            #expect(!OuroAuditExcuse.excuses(issue, element: CGRect(x: 16, y: 120, width: 260, height: 20), scaledSheets: [], toasts: [toasts], screen: screen), "\(issue)")
            #expect(!OuroAuditExcuse.excuses(issue, element: CGRect(x: 16, y: 850, width: 120, height: 50), scaledSheets: [], toasts: [], screen: screen), "\(issue)")
        }
    }
}
