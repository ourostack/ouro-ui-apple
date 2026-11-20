import OuroHX
import SwiftUI

final class SheetsGalleryPage: GalleryComponentPage {
    override class var page: String { "sheet" }
    override class var title: String { "Sheets" }
    override class var aliases: [String] { ["sheets"] }
    @MainActor override class var content: AnyView { AnyView(SheetsPage()) }
}

struct SheetsPage: View {
    @State private var open = opensAtLaunch
    @State private var filters = false
    private static var saveDetents: Set<PresentationDetent>? {
        switch UserDefaults.standard.string(forKey: "sheetDetent") {
        case "large": [.large]
        case "medium": [.medium]
        default: nil
        }
    }
    // `-sheetKeyboard 1` opens the naming sheet at launch, its field focused, so the keyboard is up.
    @State private var naming = UserDefaults.standard.bool(forKey: "sheetKeyboard")
    @State private var name = ""
    @State private var notes = ""
    private static var withNotes: Bool { UserDefaults.standard.bool(forKey: "sheetNotes") }
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
        // `-sheetDetent large` shows it at full height, where iOS draws it unscaled, for the audit's clipped-text check;
        // `-sheetDetent medium` at half height, shorter than its content at the largest sizes.
        .ouroSheet(isPresented: $open, title: "Save to cookbook", description: "Pick where this recipe lives.",
                   detents: Self.saveDetents) {
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
        // `-sheetDetent large` gives it a detent, so the keyboard covers its bottom rather than iOS lifting it.
        .ouroSheet(isPresented: $naming, title: "New cookbook", description: "Name it after what goes inside.",
                   detents: UserDefaults.standard.string(forKey: "sheetDetent") == "large" ? [.large] : nil, onDismiss: { name = "" }) {
            VStack(alignment: .leading, spacing: 12) {
                NameField(text: $name)
                // `-sheetNotes 1` adds a second field under the focused one: the sheet scrolls only as far toward its
                // actions as keeps the focused field in sight.
                if Self.withNotes { NotesField(text: $notes) }
            }
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
            .background(colors.card, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.border))
            .accessibilityIdentifier("sheet.name")
            .focused($focused)
            .onAppear { focused = true }
    }
}

/// A second, taller field under the name.
private struct NotesField: View {
    @Binding var text: String
    @Environment(\.ouroTouchTarget) private var target
    @Environment(\.ouroColors) private var colors

    var body: some View {
        TextField("Notes", text: $text, prompt: Text("What goes in it, and who it\u{2019}s for"), axis: .vertical)
            .lineLimit(4, reservesSpace: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: target)
            .background(colors.card, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.border))
            .accessibilityIdentifier("sheet.notes")
    }
}

/// A row sized by `ouroTouchTarget`, so it is 44 points as drawn inside the sheet.
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
