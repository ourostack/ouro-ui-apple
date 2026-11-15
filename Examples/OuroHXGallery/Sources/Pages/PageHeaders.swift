import OuroHX
import SwiftUI

final class PageHeadersGalleryPage: GalleryComponentPage {
    override class var page: String { "pageheaders" }
    override class var title: String { "Page headers" }
    override class var aliases: [String] { ["pageheader", "page-header"] }
    @MainActor override class var content: AnyView { AnyView(PageHeadersPage()) }
}

/// Page headers as an app uses them: a recipe page with an eyebrow, a description, badges and actions; a large
/// profile header with a picture; and a section header with a divider.
struct PageHeadersPage: View {
    @Environment(\.ouroToast) private var toast

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            OuroPageHeader("Lemon orzo with peas", eyebrow: "Weeknight", description: "Bright, quick and made in one pot.") {
                OuroButton("Cook", systemImage: "flame") { toast("Cooking lemon orzo", tone: .success) }
                OuroButton("Share", systemImage: "square.and.arrow.up", variant: .outline) { toast("Shared") }
            } content: {
                HStack(spacing: 6) {
                    OuroBadge("25 min", systemImage: "timer")
                    OuroBadge("Vegan", systemImage: "leaf", tone: .success, variant: .soft)
                }
            }
            OuroPageHeader("Ana Lind", eyebrow: "Chef", description: "Bakes on Sundays. 48 recipes.", size: .lg, actions: {
                OuroButton("Follow", variant: .soft) { toast("Following Ana Lind") }
            }, media: {
                LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 120)
                    .accessibilityHidden(true)
            }, content: { EmptyView() })
            OuroPageHeader("Shopping list", description: "Four items for Sunday.", level: 2, divider: true)
        }
    }
}
