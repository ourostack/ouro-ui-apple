import OuroHX
import SwiftUI

final class ToastsGalleryPage: GalleryComponentPage {
    override class var page: String { "toasts" }
    override class var title: String { "Toasts" }
    override class var aliases: [String] { ["toast"] }
    @MainActor override class var content: AnyView { AnyView(ToastsPage()) }
}

struct ToastsPage: View {
    @Environment(\.ouroToast) private var toast

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OuroButton("Save", systemImage: "checkmark") { toast("Recipe saved", tone: .success) }
                .accessibilityIdentifier("toast.save")
            OuroButton("Delete", systemImage: "trash", tone: .destructive, variant: .soft) {
                toast("Recipe deleted", systemImage: "trash", action: OuroToastAction("Undo") {})
            }
            OuroButton("Fail", variant: .outline) {
                toast("Couldn\u{2019}t save", description: "Check your connection.", tone: .destructive)
            }
            RecipeFeed()
        }
        .task {
            await play("toast", forth: { toast("Recipe saved", tone: .success, duration: .untilDismissed, id: "demo") }, back: { toast.dismiss("demo") })
        }
        .task {
            // On the gallery's clock (`-clock 1`), for the Feel film: half a second in, the same three toasts 0.6 s
            // apart, and the stack empties 3 s after the first. They stay until then, as no wall-clock countdown fits
            // a clock that only the test moves.
            guard demo == "stack", let clock = GalleryClock.shared else { return }
            clock.after(0.5) { toast("Recipe saved", tone: .success, duration: .untilDismissed, id: "a") }
            clock.after(1.1) { toast("Added to Weeknights", systemImage: "text.badge.plus", duration: .untilDismissed, id: "b") }
            clock.after(1.7) { toast("Recipe deleted", systemImage: "trash", action: OuroToastAction("Undo") {}, duration: .untilDismissed, id: "c") }
            clock.after(3.5) { toast.dismiss() }
        }
        .task {
            guard GalleryClock.shared == nil else { return }
            await play("stack", hold: 3, forth: {
                Task { @MainActor in
                    toast("Recipe saved", tone: .success, duration: .untilDismissed, id: "a")
                    try? await Task.sleep(for: .seconds(0.6))
                    toast("Added to Weeknights", systemImage: "text.badge.plus", duration: .untilDismissed, id: "b")
                    try? await Task.sleep(for: .seconds(0.6))
                    toast("Recipe deleted", systemImage: "trash", action: OuroToastAction("Undo") {}, id: "c")
                }
            }, back: { toast.dismiss() })
        }
        .task {
            // Dismissed 0.15 s into its arrival: it must turn around where it is, not jump.
            await play("toast-interrupt", hold: 0.15, forth: { toast("Recipe saved", tone: .success, duration: .untilDismissed, id: "demo") }, back: { toast.dismiss("demo") })
        }
        .task {
            guard opensAtLaunch, demo == nil else { return }
            toast("Recipe saved", tone: .success, duration: .untilDismissed, id: "saved")
            toast("Recipe deleted", action: OuroToastAction("Undo") {}, id: "deleted")
            toast("Couldn\u{2019}t save", description: "Check your connection.", tone: .destructive, duration: .untilDismissed, id: "failed")
        }
    }
}

/// A page's own content under the toasts and the sheet, so the glass and the dimming have something real to sit over:
/// recipes with a coloured thumbnail, a title and a line of detail, laid out openly rather than in cards.
struct RecipeFeed: View {
    @Environment(\.ouroColors) private var colors
    private let recipes: [(name: String, detail: String, symbol: String)] = [
        ("Lemon ricotta pancakes", "Breakfast · 25 min", "frying.pan"),
        ("Charred corn salad", "Weeknights · 15 min", "leaf"),
        ("Brown butter cookies", "Sunday bakes · 40 min", "birthday.cake"),
        ("Miso glazed aubergine", "Weeknights · 35 min", "flame"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recently cooked").font(.headline).accessibilityAddTraits(.isHeader).padding(.top, 12)
            ForEach(recipes, id: \.name) { recipe in
                HStack(spacing: 12) {
                    Image(systemName: recipe.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(colors.primaryForeground)
                        .frame(width: 48, height: 48)
                        .background(colors.primary.gradient, in: .rect(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipe.name).font(.body.weight(.semibold))
                        Text(recipe.detail).font(.subheadline).foregroundStyle(colors.mutedForeground)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
