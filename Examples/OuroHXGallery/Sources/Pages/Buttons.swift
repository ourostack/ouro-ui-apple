@_spi(OuroMotionClock) import OuroHX
import SwiftUI

final class ButtonsGalleryPage: GalleryComponentPage {
    override class var page: String { "buttons" }
    override class var title: String { "Buttons" }
    override class var aliases: [String] { ["button"] }
    @MainActor override class var content: AnyView { AnyView(ButtonsPage()) }
}

/// Every tone in every variant, the sizes, the pill, glass, loading and disabled.
struct ButtonsPage: View {
    @State private var saving = false
    @State private var presses = 0
    /// `-demo press`: the primary button held pressed, then let go, on the gallery's clock.
    @State private var held: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // `-demo shape`: a plain md button, as web's docs draw one, for ButtonShapeShotsTests' side-by-side of the
            // themes' corners: Pearl's 18pt squircle and Cookbook's squircle capsule.
            if demo == "shape" {
                OuroButton("Save recipe") {}.accessibilityIdentifier("button.shape")
            }
            OuroButton("Save recipe", systemImage: "checkmark", fullWidth: true, haptic: .finished) { presses += 1 }
                .accessibilityIdentifier("button.primary")
                .environment(\.ouroHeldPress, held)
            // Glass first, over a field of colour as it would float over a photo; glass over a white page shows nothing.
            ForEach([OuroButtonVariant.glass] + OuroButtonVariant.allCases.filter { $0 != .glass }, id: \.self) { variant in
                VStack(alignment: .leading, spacing: 8) {
                    Text(variant.rawValue.capitalized).font(.headline).accessibilityAddTraits(.isHeader)
                    // Plain buttons are words on the margin, so they sit further apart and their rows closer.
                    FlowRow(spacing: variant == .plain ? 24 : 8, rowSpacing: variant == .plain ? 0 : 8) {
                        ForEach(OuroTone.allCases, id: \.self) { tone in
                            OuroButton(tone.rawValue.capitalized, tone: tone, variant: variant) {}
                                .accessibilityIdentifier("button.\(variant.rawValue).\(tone.rawValue)")
                        }
                    }
                    .padding(variant == .glass ? 16 : 0)
                    .background {
                        if variant == .glass { GlassField() }
                    }
                }
            }
            Text("Sizes and shapes").font(.headline).accessibilityAddTraits(.isHeader)
            FlowRow {
                OuroButton("Small", size: .sm) {}
                OuroButton("Medium") {}
                OuroButton("Large", size: .lg) {}
                OuroButton("Pill", variant: .soft, shape: .pill) {}
            }
            // The glass pill on a row of its own: on iPad's wide row it sat beside the soft pill, and its shadow
            // darkened the soft pill's fill just enough for the audit to fail that label's contrast.
            OuroButton("Glass pill", systemImage: "sparkles", variant: .glass, shape: .pill) {}
            FlowRow {
                OuroButton("Save", loading: saving, loadingLabel: "Saving recipe") {
                    saving = true
                    Task { try? await Task.sleep(for: .seconds(2)); saving = false }
                }
                .accessibilityIdentifier("button.loading")
                OuroButton("Unavailable", variant: .outline) {}.disabled(true)
                OuroButton("Publish") {}.disabled(true)
            }
        }
        .task {
            // `-demo press` on the gallery's clock (`-clock 1`): ButtonFramesTests films the primary button one 0.05 s
            // tick at a time as it is pressed at tick 1 and let go at tick 9, 400 ms later. A real finger cannot be
            // held while XCUITest takes screenshots, so the press is held for it (`ouroHeldPress`).
            guard demo == "press", let clock = GalleryClock.shared else { return }
            held = false
            clock.after(0.05) { held = true }
            clock.after(0.45) { held = false }
        }
    }
}

/// A faint field of colour, a few percent off the page, for glass buttons to float over so their edge light shows.
/// A glass button's words are made readable against the page (its contract), so the field stays near the page.
private struct GlassField: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // Warm to cool, as a food photo runs, with enough colour in dark for the glass to bend (taste round 6: over a
        // near-black field dark glass read as flat grey). Light stays pale: over a saturated warm field the glass
        // Success and Warning labels measured 4.8:1, under the 5:1 the claims test holds them to.
        LinearGradient(colors: scheme == .dark
                       ? [Color(red: 0.34, green: 0.19, blue: 0.09), Color(red: 0.11, green: 0.14, blue: 0.33)]
                       : [Color(red: 0.98, green: 0.95, blue: 0.92), Color(red: 0.94, green: 0.95, blue: 0.99)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .accessibilityHidden(true)
    }
}
