import Foundation
import OuroHXTesting
import Testing

/// Every claim in core's vendored component claim set (`OuroHXClaims.components`) has a named Swift test here, and
/// every named test exists. A claim added to core fails this until a test proves it.
@Suite struct ClaimCoverageTests {
    /// Claim id to the tests that prove it: `File.swift: name`, paths from the repository root.
    static let proofs: [String: [String]] = [
        "target.touch": [
            "Tests/OuroHXTests/ComponentTests.swift: TouchTargetTests",
            "Examples/OuroHXGallery/UITests/ComponentClaimTests.swift: testEveryControlIs44Points",
            "Examples/OuroHXGallery/UITests/ComponentClaimTests.swift: testEveryComponentPagePassesTheAccessibilityAudit",
        ],
        "motion.reduced": ["Tests/OuroHXTests/ComponentTests.swift: ComponentMotionTests"],
        "name.spoken": [
            "Examples/OuroHXGallery/UITests/ComponentClaimTests.swift: testVoiceOverLabels",
            "Examples/OuroHXGallery/UITests/ComponentClaimTests.swift: testEveryComponentPagePassesTheAccessibilityAudit",
        ],
        "text.reflows": [
            "Examples/OuroHXGallery/UITests/ComponentClaimTests.swift: testEveryComponentPagePassesTheAccessibilityAudit",
            "Examples/OuroHXGallery/UITests/ComponentClaimTests.swift: testAnEmptyStatesActionSpansTheWidthAtAccessibilitySizes",
        ],
        "contrast.text": [
            "Tests/OuroHXTests/ComponentTests.swift: ContrastTests",
            "Tests/OuroHXTests/ComponentSnapshotTests.swift: ComponentSnapshotTests",
        ],
        "announce.urgency": ["Tests/OuroHXTests/ComponentTests.swift: AnnouncementTests"],
        "toast.action-stays": [
            "Tests/OuroHXTests/ComponentTests.swift: ToastTests",
            "Examples/OuroHXGallery/UITests/ComponentClaimTests.swift: testAToastWithAnActionWaits",
        ],
        "dismiss.reachable": [
            "Examples/OuroHXGallery/UITests/ComponentClaimTests.swift: testCloseControlsClose",
            "Examples/OuroHXGallery/UITests/ComponentClaimTests.swift: testAToastShowsAboveASheet",
        ],
    ]

    static var root: URL { URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    @Test func everyClaimHasAProofAndNoProofNamesAMissingClaim() throws {
        let ids = try OuroHXClaims.components().claims.map(\.id)
        #expect(!ids.isEmpty)
        for id in ids { #expect(!(Self.proofs[id] ?? []).isEmpty, "claim \(id) has no Swift test. Fix: write one and list it in ClaimCoverageTests.proofs.") }
        for id in Self.proofs.keys { #expect(ids.contains(id), "\(id) is not in the vendored claim set") }
    }

    @Test func everyNamedProofExists() throws {
        for (id, proofs) in Self.proofs {
            for proof in proofs {
                let parts = proof.components(separatedBy: ": ")
                let source = try String(contentsOf: Self.root.appending(path: parts[0]), encoding: .utf8)
                #expect(source.contains("func \(parts[1])") || source.contains("struct \(parts[1])") || source.contains("class \(parts[1])"), "\(id): \(proof) does not exist")
            }
        }
    }
}
