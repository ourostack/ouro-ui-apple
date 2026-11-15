import OuroHX
import SwiftUI

final class BannersGalleryPage: GalleryComponentPage {
    override class var page: String { "banners" }
    override class var title: String { "Banners" }
    override class var aliases: [String] { ["banner"] }
    @MainActor override class var content: AnyView { AnyView(BannersPage()) }
}

struct BannersPage: View {
    @State private var showError = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            OuroBanner("Couldn\u{2019}t save", description: "Check your connection and try again.", tone: .destructive, onDismiss: {
                withOuroAnimation(.layout, reduceMotion: reduceMotion) { showError = false }
            }, isPresented: showError) {
                OuroButton("Try again", tone: .destructive, variant: .soft, size: .sm) {}
            }
            .accessibilityIdentifier("banner.destructive")
            OuroBanner("Recipe saved", tone: .success)
            OuroBanner("Your oven runs hot", description: "Recipes here assume a fan oven; take 20 degrees off.", tone: .warning)
            OuroBanner("New: cook along with Siri", description: "Ask Siri for the next step while your hands are floury.", tone: .primary)
            OuroBanner("Shared with the household", tone: .secondary)
            OuroButton("Show the error again", variant: .outline) {
                withOuroAnimation(.layout, reduceMotion: reduceMotion) { showError = true }
            }
            .disabled(showError)
        }
        .task {
            await play("banner-interrupt", hold: 0.12, forth: { withOuroAnimation(.layout, reduceMotion: reduceMotion) { showError = false } }, back: { withOuroAnimation(.layout, reduceMotion: reduceMotion) { showError = true } })
        }
        .task {
            await play("banner", forth: { withOuroAnimation(.layout, reduceMotion: reduceMotion) { showError = false } }, back: { withOuroAnimation(.layout, reduceMotion: reduceMotion) { showError = true } })
        }
    }
}
