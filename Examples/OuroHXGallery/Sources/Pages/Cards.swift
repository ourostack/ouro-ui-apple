import OuroHX
import SwiftUI

final class CardsGalleryPage: GalleryComponentPage {
    override class var page: String { "cards" }
    override class var title: String { "Cards" }
    override class var aliases: [String] { ["card"] }
    @MainActor override class var content: AnyView { AnyView(CardsPage()) }
}

/// Cards as an app uses them: one with every slot, a small one, and a plain one inside a surface of its own.
struct CardsPage: View {
    @Environment(\.ouroToast) private var toast

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OuroCard("Pantry", description: "What you have on hand") {
                Text("Flour, rice, black beans, two lemons and a jar of capers.")
            } action: {
                OuroButton("Edit", variant: .plain, size: .sm) { toast("Editing the pantry") }
            } footer: {
                OuroBadgeFlow {
                    OuroBadge("4 items", systemImage: "basket")
                    OuroBadge("Low on rice", tone: .warning, variant: .soft)
                }
            }
            OuroCard("Tonight", description: "Lemon orzo with peas, 25 minutes", size: .sm) {
                OuroButton("Start cooking", systemImage: "frying.pan", fullWidth: true) { toast("Cooking", tone: .success) }
            }
            OuroCard("Shared with the household", variant: .plain) {
                Text("Sam and Alex can see and edit this cookbook.")
            }
        }
    }
}
