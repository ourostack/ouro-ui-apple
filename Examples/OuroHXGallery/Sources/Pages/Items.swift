import OuroHX
import SwiftUI

final class ItemsGalleryPage: GalleryComponentPage {
    override class var page: String { "items" }
    override class var title: String { "Items" }
    override class var aliases: [String] { ["item"] }
    @MainActor override class var content: AnyView { AnyView(ItemsPage()) }
}

/// Rows as an app uses them: a divided group with an icon tile, a picture, actions and a pressable row, an
/// outlined row on its own, an ordered group and an empty one.
struct ItemsPage: View {
    @Environment(\.ouroToast) private var toast

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OuroItemGroup("Recipes") {
                OuroItem("Braised short ribs", description: "3 hours, serves six", systemImage: "flame") {
                    OuroBadge("New", tone: .primary, variant: .soft)
                }
                OuroItem("Lemon orzo", description: "25 minutes", mediaSize: .md) {
                    LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                } actions: {
                    OuroButton("Cook", variant: .outline, size: .sm) { toast("Cooking lemon orzo", tone: .success) }
                }
                OuroItem("Black bean soup", description: "40 minutes", onPress: { toast("Opening black bean soup") })
            }
            OuroItemGroup("Shopping list", variant: .outline) {
                OuroItem("Flour", description: "1 kg", size: .sm)
                OuroItem("Lemons", description: "4", size: .sm)
            }
            OuroItem("Pantry", description: "12 items", systemImage: "basket", variant: .outline, onPress: { toast("Opening the pantry") })
            OuroItemGroup("Steps", ordered: true) {
                OuroItem("Toast the orzo in butter", size: .sm)
                OuroItem("Add the stock and simmer", size: .sm)
            }
            OuroItemGroup("Cookbooks", empty: "No cookbooks yet.") {}
        }
    }
}
