import CoreGraphics
import OuroHXTesting
import Testing

/// What `ouroAccessibilityAudit` excuses: "Text clipped" wholly inside a sheet drawn at 96%, and nothing else.
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
}
