import OuroHX
import SwiftUI

final class EmptyStatesGalleryPage: GalleryComponentPage {
    override class var page: String { "empty" }
    override class var title: String { "Empty states" }
    override class var aliases: [String] { ["emptystate"] }
    @MainActor override class var content: AnyView { AnyView(EmptyStatesPage()) }
}

struct EmptyStatesPage: View {
    @Environment(\.ouroToast) private var toast
    @State private var shown = demo != "empty"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            // It arrives (and cascades in) and leaves where it stands: a hidden copy holds its place, so nothing else on
            // the page moves under it.
            ZStack {
                firstEmpty.hidden().accessibilityHidden(true)
                if shown {
                    firstEmpty.transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.97)))
                }
            }
            OuroEmptyState("Nothing matches \u{201C}saffron\u{201D}", systemImage: "text.magnifyingglass", description: "Try fewer words, or check the spelling.")
        }
        .frame(minHeight: 300, alignment: .top)
        .task {
            await play("empty", forth: { withOuroAnimation(.layout, reduceMotion: reduceMotion) { shown = true } }, back: { withOuroAnimation(.exit, reduceMotion: reduceMotion) { shown = false } })
        }
    }

    private var firstEmpty: some View {
            OuroEmptyState("No recipes yet", systemImage: "books.vertical", description: "Start by creating your first recipe, or import one from the web.") {
                OuroButton("Create recipe", systemImage: "plus") { toast("A fresh page, ready for a recipe", tone: .success) }
            }
    }
}
