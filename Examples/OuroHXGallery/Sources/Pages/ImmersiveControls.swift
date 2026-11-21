import OuroHX
import SwiftUI

final class ImmersiveControlsGalleryPage: GalleryComponentPage {
    override class var page: String { "immersive" }
    override class var title: String { "Immersive Controls" }
    override class var aliases: [String] { ["immersivecontrols", "controls"] }
    @MainActor override class var content: AnyView { AnyView(ImmersiveControlsPage()) }
}

/// A picture that fills its frame, and controls over it: a tap shows or hides them, and the picture never moves.
struct ImmersiveControlsPage: View {
    @State private var shown = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tap the picture to show or hide its controls. The picture never moves.")
                .font(.subheadline)
            LinearGradient(colors: [.gray.opacity(0.12), .gray.opacity(0.28)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 420)
                .clipShape(.rect(cornerRadius: 20, style: .continuous))
                .contentShape(.rect)
                .onTapGesture { shown.toggle() }
                .accessibilityElement()
                .accessibilityLabel("Picture")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Shows or hides its controls")
                .accessibilityIdentifier("immersive.content")
                .ouroImmersiveControls(isPresented: shown) {
                    HStack {
                        OuroButton("Close", systemImage: "xmark", variant: .glass, size: .sm) { shown = false }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("immersive.glass.close")
                        Spacer(minLength: 0)
                        OuroButton("Share", systemImage: "square.and.arrow.up", variant: .glass, size: .sm) {}
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("immersive.glass.share")
                    }
                } bottom: {
                    HStack {
                        Spacer(minLength: 0)
                        OuroButton("Edit", systemImage: "slider.horizontal.3", variant: .glass, size: .sm) {}
                        .accessibilityIdentifier("immersive.glass.edit")
                        OuroButton("Favourite", systemImage: "heart", variant: .glass, size: .sm) {}
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("immersive.glass.favourite")
                        Spacer(minLength: 0)
                    }
                }
        }
    }
}
