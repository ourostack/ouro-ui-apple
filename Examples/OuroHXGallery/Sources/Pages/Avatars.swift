import OuroHX
import SwiftUI

final class AvatarsGalleryPage: GalleryComponentPage {
    override class var page: String { "avatars" }
    override class var title: String { "Avatars" }
    override class var aliases: [String] { ["avatar"] }
    @MainActor override class var content: AnyView { AnyView(AvatarsPage()) }
}

/// Avatars as an app uses them: chefs in a row in every size, each presence, a team's square, an agent, the brand and
/// neutral colours, one loading, and a chef beside their name (so the avatar isn't read twice).
struct AvatarsPage: View {
    static let chefs = ["Ana Lind", "Ari Mendelow", "Rachel Okafor", "Kenji Sato", "Priya Raman", "Tomás Ruiz", "Mei Chen"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OuroBadgeFlow(spacing: 10) {
                ForEach(Array(OuroAvatarSize.allCases.enumerated()), id: \.offset) { i, size in
                    OuroAvatar(name: Self.chefs[i], size: size)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("avatars.sizes")
            OuroBadgeFlow(spacing: 12) {
                ForEach(OuroAvatarPresence.allCases, id: \.self) { presence in
                    OuroAvatar(name: "Ana Lind", size: .lg, presence: presence, presenceLabel: presence.rawValue)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("avatars.presence")
            OuroBadgeFlow(spacing: 14) {
                OuroAvatar(name: "Sunday supper club", shape: .square, size: .lg)
                OuroAvatar(name: "Sous chef", systemImage: "sparkles", shape: .agent, size: .lg, presence: .available, presenceLabel: "Ready")
                OuroAvatar(name: "Spoonjoy", systemImage: "fork.knife", shape: .square, color: .brand, size: .lg)
                OuroAvatar(name: "Guest cook", color: .neutral, size: .lg)
                OuroAvatar(name: nil, size: .lg)
            }
            HStack(spacing: 12) {
                OuroAvatar(name: "Kenji Sato", alt: "", size: .md)
                VStack(alignment: .leading) {
                    Text("Kenji Sato").font(.headline)
                    Text("12 recipes").font(.subheadline)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
