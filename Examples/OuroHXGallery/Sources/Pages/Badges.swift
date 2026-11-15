import OuroHX
import SwiftUI

final class BadgesGalleryPage: GalleryComponentPage {
    override class var page: String { "badges" }
    override class var title: String { "Badges" }
    override class var aliases: [String] { ["badge"] }
    @MainActor override class var content: AnyView { AnyView(BadgesPage()) }
}

/// Every tone in every variant, then badges where an app puts them: beside a recipe's title and time, as Spoonjoy's
/// and Gatefold's hand-drawn chips do.
struct BadgesPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(OuroBadgeVariant.allCases, id: \.self) { variant in
                OuroBadgeFlow {
                    ForEach(OuroTone.allCases, id: \.self) { tone in
                        OuroBadge(tone.rawValue.capitalized, tone: tone, variant: variant)
                    }
                }
                .accessibilityIdentifier("badges.\(variant.rawValue)")
            }
            VStack(alignment: .leading, spacing: 14) {
                recipe("Lemon orzo with peas", minutes: 25) {
                    OuroBadge("Vegan", systemImage: "leaf", tone: .success, variant: .soft)
                    OuroBadge("New", tone: .primary)
                }
                Divider()
                recipe("Braised short ribs", minutes: 240) {
                    OuroBadge("Weekend", variant: .outline)
                    OuroBadge("Oven runs hot", systemImage: "flame", tone: .warning, variant: .soft)
                }
                Divider()
                recipe("Saffron buns", minutes: 90) {
                    OuroBadge("3 unread", tone: .destructive)
                }
            }
        }
    }

    private func recipe(_ title: String, minutes: Int, @ViewBuilder badges: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            OuroBadgeFlow {
                OuroBadge("\(minutes) min", systemImage: "timer")
                badges()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
