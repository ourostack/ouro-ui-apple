import OuroHX
import SwiftUI

private var opensAtLaunch: Bool { UserDefaults.standard.integer(forKey: "open") > 0 }

/// `-demo <name>` plays one transition by itself, for frame captures: it waits `lead` seconds, does `forth`, waits
/// `hold`, then does `back`.
private var demo: String? { UserDefaults.standard.string(forKey: "demo") }

/// `-warm 1` plays a demo once before the probe starts, so the probe times what every play costs, not what only the
/// first one in a process does. On CI's GPU-less VM the first glass a process draws stalled 180 to 415 ms, every
/// launch; on a Mac's simulator it did not, and the host-video captures time that first play (W8 round 6).
@MainActor enum DemoWarmup {
    static var done = !UserDefaults.standard.bool(forKey: "warm")
}

@MainActor private func play(_ name: String, lead: Double = 1.5, hold: Double = 2.5, forth: @escaping @MainActor () -> Void, back: @escaping @MainActor () -> Void) async {
    guard demo == name else { return }
    if !DemoWarmup.done {
        try? await Task.sleep(for: .seconds(lead))
        forth()
        try? await Task.sleep(for: .seconds(hold))
        back()
        try? await Task.sleep(for: .seconds(1.5))
        DemoWarmup.done = true
    }
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

/// Wraps buttons onto as many lines as the width and text size need, 8 points apart, as a row of chips does.
struct FlowRow<Content: View>: View {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8
    @ViewBuilder var content: Content
    var body: some View { Flow(spacing: spacing, rowSpacing: rowSpacing) { content } }
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

private struct Flow: Layout {
    let spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews)
        let height = rows.map(\.height).reduce(0, +) + rowSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(width: CGFloat, _ subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            if var last = rows.last, last.width + spacing + size.width <= width {
                last.indices.append(index)
                last.width += spacing + size.width
                last.height = max(last.height, size.height)
                rows[rows.count - 1] = last
            } else {
                rows.append(([index], min(size.width, width), size.height))
            }
        }
        return rows
    }
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

struct SheetsPage: View {
    @State private var open = opensAtLaunch
    @State private var filters = false
    // `-sheetKeyboard 1` opens the naming sheet at launch, its field focused, so the keyboard is up.
    @State private var naming = UserDefaults.standard.bool(forKey: "sheetKeyboard")
    @State private var name = ""
    @State private var picked = "Weeknights"
    @Environment(\.ouroToast) private var toast

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OuroButton("Save to cookbook", systemImage: "book") { open = true }
                .accessibilityIdentifier("sheet.open")
            OuroButton("Filters", variant: .soft) { filters = true }
            OuroButton("New cookbook", variant: .soft) { naming = true }
            RecipeFeed()
        }
        // `-sheetDetent large` shows it at full height, where iOS draws it unscaled, for the audit's clipped-text check.
        .ouroSheet(isPresented: $open, title: "Save to cookbook", description: "Pick where this recipe lives.",
                   detents: UserDefaults.standard.string(forKey: "sheetDetent") == "large" ? [.large] : nil) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(["Weeknights", "Sunday bakes", "Party food"], id: \.self) { name in
                    CookbookRow(name: name, picked: $picked)
                    // Settings' hairline between rows, not after the last.
                    if name != "Party food" { Divider() }
                }
            }
        } footer: {
            OuroButton("Save", fullWidth: true) {
                open = false
                toast("Saved to \(picked)", tone: .success)
            }
        }
        .task { await play("sheet", hold: 3, forth: { open = true }, back: { open = false }) }
        // A sheet with a field that takes focus, the keyboard up: with it, at the largest sizes, the words above scroll
        // and the action keeps its height.
        .ouroSheet(isPresented: $naming, title: "New cookbook", description: "Name it after what goes inside.", onDismiss: { name = "" }) {
            NameField(text: $name)
        } footer: {
            OuroButton("Create cookbook", fullWidth: true) { naming = false }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .ouroSheet(isPresented: $filters, title: "Filters", detents: [.medium, .large]) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick, vegetarian, one pot.")
                // A toast sent with the sheet open shows above it.
                OuroButton("Remember these", variant: .soft) {
                    // `-toastSeconds 0` keeps it until dismissed, for a UI test on a runner slower than five seconds.
                    let seconds = UserDefaults.standard.object(forKey: "toastSeconds").map { _ in UserDefaults.standard.double(forKey: "toastSeconds") }
                    toast("Filters remembered", tone: .success, duration: seconds.map { OuroToastDuration.seconds($0) } ?? .automatic)
                }
            }
        }
    }
}

/// A row sized by `ouroTouchTarget`, so it is 44 points as drawn inside the sheet.
/// A sheet's text field, focused as it appears, as a naming sheet's usually is.
private struct NameField: View {
    @Binding var text: String
    @Environment(\.ouroTouchTarget) private var target
    @Environment(\.ouroColors) private var colors
    @FocusState private var focused: Bool

    var body: some View {
        // Vertical, so at the largest sizes the words wrap rather than run out of the field.
        TextField("Name", text: $text, prompt: Text("Suppers"), axis: .vertical)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: target)
            .background(colors.card, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(colors.border))
            .accessibilityIdentifier("sheet.name")
            .focused($focused)
            .onAppear { focused = true }
    }
}

private struct CookbookRow: View {
    let name: String
    @Binding var picked: String
    @Environment(\.ouroTouchTarget) private var target
    @Environment(\.ouroColors) private var colors

    var body: some View {
        Button {
            picked = name
        } label: {
            // Settings' pattern: the name, and a checkmark at the trailing edge on the one chosen.
            HStack {
                Text(name)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.primary)
                    .opacity(picked == name ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
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
private struct RecipeFeed: View {
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
                        .background(colors.primary.gradient, in: .rect(cornerRadius: 12))
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
