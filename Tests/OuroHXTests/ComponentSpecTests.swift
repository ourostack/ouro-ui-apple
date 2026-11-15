@testable import OuroHX
import Foundation
import SwiftUI
import Testing

/// Core's component specs (`standard/hx/components/*.spec.json`, vendored in `Specs/` and pinned by hash in
/// `core-provenance.json`) against what this package draws: every number in a spec's `metrics` is either the same
/// number here or excused below with the reason, so a spec that changes in core fails here until Apple keeps pace.
@Suite struct ComponentSpecTests {
    static let root = Bundle.module.url(forResource: "Specs", withExtension: nil)!

    struct Spec: Decodable {
        struct Platform: Decodable { let type: String }
        let name: String
        let metrics: [String: Double]?
        let platforms: [String: Platform]
    }

    static func load(_ name: String) throws -> Spec {
        try JSONDecoder().decode(Spec.self, from: Data(contentsOf: root.appending(path: "\(name).spec.json")))
    }

    static var vendored: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return files.filter { $0.hasSuffix(".spec.json") }.map { String($0.dropLast(".spec.json".count)) }.sorted()
    }

    /// Each spec's metrics as this package has them.
    static let apple: [String: [String: Double]] = [
        "badge": ["minHeight": OuroBadgeMetrics.minimumHeight, "paddingX": OuroBadgeMetrics.horizontalPadding],
        "button": ["minTarget": OuroButtonSize.minimumTarget(on: .touch), "pressScale": OuroTokens.Press.scale],
        "card": [
            "paddingMd": OuroCardMetrics.padding(size: .md, variant: .outline),
            "paddingSm": OuroCardMetrics.padding(size: .sm, variant: .outline),
            "gapMd": OuroCardMetrics.spacing(size: .md), "gapSm": OuroCardMetrics.spacing(size: .sm),
        ],
        "checkbox": [
            "boxTouch": OuroChoiceMetrics.boxSide(.touch), "boxPointer": OuroChoiceMetrics.boxSide(.pointer),
            "rowMinHeightTouch": OuroChoiceMetrics.rowMinHeight(.touch), "gap": OuroChoiceMetrics.boxGap,
            "graphicContrast": OuroColor.increasedLineContrast,
        ],
        "item": [
            "pressableMinHeight": OuroItemMetrics.pressableMinimumHeight,
            "paddingMd": OuroItemMetrics.verticalPadding(.md), "paddingSm": OuroItemMetrics.verticalPadding(.sm),
            "gap": OuroItemMetrics.spacing, "iconTile": OuroItemMetrics.mediaSide(.icon),
            "mediaSm": OuroItemMetrics.mediaSide(.sm), "mediaMd": OuroItemMetrics.mediaSide(.md),
            "mediaLg": OuroItemMetrics.mediaSide(.lg), "outlineInset": OuroItemMetrics.outlineInset,
        ],
        "page-header": ["gap": OuroPageHeaderMetrics.spacing, "blockGap": OuroPageHeaderMetrics.blockSpacing],
        "progress": ["barHeight": OuroLoadingMetrics.barHeight, "fillContrast": OuroColor.increasedLineContrast],
        "segmented-control": [
            "heightTouch": OuroChoiceMetrics.segmentHeight(.touch), "heightPointer": OuroChoiceMetrics.segmentHeight(.pointer),
            "trackInset": OuroChoiceMetrics.trackInset, "segmentPadding": OuroChoiceMetrics.segmentPadding,
        ],
        "skeleton": [
            "breatheDelaySeconds": OuroLoadingMetrics.breatheDelay, "lastLineFraction": OuroLoadingMetrics.lastLineFraction,
            "placeholderContrast": OuroLoadingMetrics.placeholderContrast,
        ],
        "spinner": [
            "sm": OuroLoadingMetrics.spinnerSide(.sm), "md": OuroLoadingMetrics.spinnerSide(.md),
            "lg": OuroLoadingMetrics.spinnerSide(.lg),
        ],
        "sync-status": ["speakDelayMs": OuroSyncStatusMetrics.speakDelay / .milliseconds(1)],
    ]

    /// Metrics Apple draws differently on purpose, or proves elsewhere, and why.
    static let excused: [String: [String: String]] = [
        "button": ["paddingX": "A capsule needs room for its ends to round: 14, 20 and 24 points by size (OuroButtonSize.horizontalPadding), wider than web's px-4."],
        "sync-status": ["retryTarget": "Retry's frame is 44 points in OuroSyncStatus's body; the gallery's testEveryControlIs44Points measures it."],
    ]

    /// Specs vendored for components this package doesn't ship yet; each leaves this list in the pull request that
    /// adds the component and its row in `apple`.
    static let notYetBuilt: Set<String> = ["avatar", "description-list", "separator", "text-field"]

    @Test func everyVendoredSpecIsComparedOrNotYetBuilt() {
        #expect(Set(Self.vendored) == Set(Self.apple.keys).union(Self.notYetBuilt))
        #expect(Set(Self.apple.keys).isDisjoint(with: Self.notYetBuilt))
    }

    @Test(arguments: ComponentSpecTests.apple.keys.sorted()) func appleDrawsTheSpecsNumbers(_ name: String) throws {
        let spec = try Self.load(name)
        #expect(spec.name == name)
        #expect(spec.platforms["apple"] != nil, "\(name): the spec has no apple platform")
        let ours = Self.apple[name] ?? [:]
        let excused = Self.excused[name] ?? [:]
        for (key, value) in spec.metrics ?? [:] {
            if excused[key] != nil { continue }
            guard let mine = ours[key] else {
                Issue.record("\(name).\(key) = \(value) in core's spec: compare it in `apple` or excuse it with a reason")
                continue
            }
            #expect(abs(mine - value) < 1e-9, "\(name).\(key): core says \(value), Apple draws \(mine)")
        }
        for key in Set(ours.keys).union(excused.keys) where spec.metrics?[key] == nil {
            Issue.record("\(name).\(key) is compared here but core's spec has no such metric")
        }
    }
}
