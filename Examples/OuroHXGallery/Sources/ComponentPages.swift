import OuroHX
import SwiftUI

private var opensAtLaunch: Bool { UserDefaults.standard.integer(forKey: "open") > 0 }

/// `-demo <name>` plays one transition by itself, for frame captures: it waits `lead` seconds, does `forth`, waits
/// `hold`, then does `back`.
private var demo: String? { UserDefaults.standard.string(forKey: "demo") }

@MainActor private func play(_ name: String, lead: Double = 1.5, hold: Double = 2.5, forth: @escaping @MainActor () -> Void, back: @escaping @MainActor () -> Void) async {
    guard demo == name else { return }
    // `-repeat n` plays it n times, to tell a first-time cost from one paid every time.
    for _ in 0..<max(1, UserDefaults.standard.integer(forKey: "repeat")) {
        try? await Task.sleep(for: .seconds(lead))
        forth()
        try? await Task.sleep(for: .seconds(hold))
        back()
    }
}

/// Every tone in every variant, the sizes, the pill, glass, loading and disabled.
struct ButtonsPage: View {
    @State private var saving = false
    @State private var presses = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OuroButton("Save recipe", systemImage: "checkmark", fullWidth: true, haptic: .finished) { presses += 1 }
                .accessibilityIdentifier("button.primary")
            ForEach(OuroButtonVariant.allCases, id: \.self) { variant in
                VStack(alignment: .leading, spacing: 8) {
                    Text(variant.rawValue.capitalized).font(.headline).accessibilityAddTraits(.isHeader)
                    FlowRow {
                        ForEach(OuroTone.allCases, id: \.self) { tone in
                            OuroButton(tone.rawValue.capitalized, tone: tone, variant: variant) {}
                        }
                    }
                }
            }
            Text("Sizes and shapes").font(.headline).accessibilityAddTraits(.isHeader)
            FlowRow {
                OuroButton("Small", size: .sm) {}
                OuroButton("Medium") {}
                OuroButton("Large", size: .lg) {}
                OuroButton("Pill", variant: .soft, shape: .pill) {}
                OuroButton("Glass pill", systemImage: "sparkles", variant: .glass, shape: .pill) {}
            }
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
    }
}

/// Wraps buttons onto as many lines as the width and text size need.
struct FlowRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
            VStack(alignment: .leading, spacing: 8) { content }
        }
    }
}

struct EmptyStatesPage: View {
    @Environment(\.ouroToast) private var toast
    @State private var shown = demo != "empty"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            if shown { firstEmpty.transition(.opacity.combined(with: .scale(scale: 0.97))) }
            OuroEmptyState("Nothing matches \u{201C}saffron\u{201D}", systemImage: "magnifyingglass", description: "Try fewer words, or check the spelling.", alignment: .leading, variant: .plain)
        }
        .frame(minHeight: 300, alignment: .top)
        .task {
            await play("empty", forth: { withOuroAnimation(.layout, reduceMotion: reduceMotion) { shown = true } }, back: { withOuroAnimation(.exit, reduceMotion: reduceMotion) { shown = false } })
        }
    }

    private var firstEmpty: some View {
            OuroEmptyState("No recipes yet", systemImage: "book.closed", description: "Start by creating your first recipe, or import one from the web.") {
                OuroButton("Create recipe", systemImage: "plus") { toast("A fresh page, ready for a recipe", tone: .success) }
            }
    }
}

struct BannersPage: View {
    @State private var showError = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            OuroBanner("Couldn't save", description: "Check your connection and try again.", tone: .destructive, onDismiss: {
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

struct SheetsPage: View {
    @State private var open = opensAtLaunch
    @State private var filters = false
    @State private var picked = "Weeknights"
    @Environment(\.ouroToast) private var toast

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OuroButton("Save to cookbook", systemImage: "book") { open = true }
                .accessibilityIdentifier("sheet.open")
            OuroButton("Filters", variant: .soft) { filters = true }
        }
        // `-sheetDetent large` shows it at full height, where iOS draws it unscaled, for the audit's clipped-text check.
        .ouroSheet(isPresented: $open, title: "Save to cookbook", description: "Pick where this recipe lives.",
                   detents: UserDefaults.standard.string(forKey: "sheetDetent") == "large" ? [.large] : nil) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(["Weeknights", "Sunday bakes", "Party food"], id: \.self) { name in
                    CookbookRow(name: name, picked: $picked)
                }
            }
        } footer: {
            OuroButton("Save", fullWidth: true) {
                open = false
                toast("Saved to \(picked)", tone: .success)
            }
        }
        .task { await play("sheet", hold: 3, forth: { open = true }, back: { open = false }) }
        .ouroSheet(isPresented: $filters, title: "Filters", detents: [.medium, .large]) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick, vegetarian, one pot.")
                // A toast sent with the sheet open shows above it.
                OuroButton("Remember these", variant: .soft) { toast("Filters remembered", tone: .success) }
            }
        }
    }
}

/// A row sized by `ouroTouchTarget`, so it is 44 points as drawn inside the sheet.
private struct CookbookRow: View {
    let name: String
    @Binding var picked: String
    @Environment(\.ouroTouchTarget) private var target

    var body: some View {
        Button {
            picked = name
        } label: {
            Label(name, systemImage: picked == name ? "checkmark.circle.fill" : "circle")
                .frame(maxWidth: .infinity, minHeight: target, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked == name ? .isSelected : [])
    }
}

struct ToastsPage: View {
    @Environment(\.ouroToast) private var toast

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OuroButton("Save", systemImage: "checkmark") { toast("Recipe saved", tone: .success) }
                .accessibilityIdentifier("toast.save")
            OuroButton("Delete", systemImage: "trash", tone: .destructive, variant: .soft) {
                toast("Recipe deleted", action: OuroToastAction("Undo") {})
            }
            OuroButton("Fail", variant: .outline) {
                toast("Couldn't save", description: "Check your connection.", tone: .destructive)
            }
        }
        .task {
            await play("toast", forth: { toast("Recipe saved", tone: .success, duration: .untilDismissed, id: "demo") }, back: { toast.dismiss("demo") })
        }
        .task {
            await play("stack", hold: 3, forth: {
                Task { @MainActor in
                    toast("Recipe saved", tone: .success, duration: .untilDismissed, id: "a")
                    try? await Task.sleep(for: .seconds(0.6))
                    toast("Added to Weeknights", duration: .untilDismissed, id: "b")
                    try? await Task.sleep(for: .seconds(0.6))
                    toast("Recipe deleted", action: OuroToastAction("Undo") {}, id: "c")
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
            toast("Couldn't save", description: "Check your connection.", tone: .destructive, duration: .untilDismissed, id: "failed")
        }
    }
}
