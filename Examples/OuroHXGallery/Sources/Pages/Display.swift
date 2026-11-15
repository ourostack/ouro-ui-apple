import OuroHX
import SwiftUI

final class DisplayGalleryPage: GalleryComponentPage {
    override class var page: String { "display" }
    override class var title: String { "Display" }
    override class var aliases: [String] { ["separator", "separators", "descriptionlist"] }
    @MainActor override class var content: AnyView { AnyView(DisplayPage()) }
}

/// Description lists and separators: a recipe's facts, and the lines between choices.
struct DisplayPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OuroDescriptionList([
                OuroDescriptionItem("Prep time", "20 minutes"),
                OuroDescriptionItem("Cook time", "4 hours"),
                OuroDescriptionItem("Serves", "6"),
                OuroDescriptionItem("Diet") { OuroBadge("Vegan", systemImage: "leaf", tone: .success, variant: .soft) },
            ])
            .accessibilityIdentifier("display.list")
            OuroSeparator()
            OuroButton("Continue with Apple", systemImage: "apple.logo", variant: .outline) {}
            OuroSeparator(label: "or")
            OuroButton("Continue with email", variant: .outline) {}
            HStack(spacing: 12) {
                OuroButton("Edit", variant: .plain) {}
                OuroSeparator(.vertical)
                OuroButton("Share", variant: .plain) {}
            }
            .fixedSize(horizontal: false, vertical: true)
            OuroSeparator(label: "New since you left · 2 messages", tone: .primary)
        }
    }
}
