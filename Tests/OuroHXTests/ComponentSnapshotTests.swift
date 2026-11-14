import Foundation
@testable import OuroHX
import OuroHXTesting
import SwiftUI
import Testing

/// Snapshot references for every component in light, dark and increased contrast. (macOS has no Dynamic Type, so
/// these renders cannot show the largest text size; the gallery UI tests audit that on iOS, at
/// AccessibilityXXXL.) Text renders differently on each macOS major, so each keeps its own references in
/// `__Snapshots__/macOS-<major>`; CI on a pull request sets `OURO_SNAPSHOT_RECORD=never`, so a missing or changed
/// reference fails there and its `.actual.png` is uploaded to record from.
@Suite @MainActor struct ComponentSnapshotTests {
    enum Mode: String, CaseIterable, Sendable {
        case light, dark, increasedContrast

        var appearance: OuroSnapshot.Appearance { OuroSnapshot.Appearance(rawValue: rawValue)! }
    }

    static var directory: URL {
        URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "__Snapshots__/macOS-\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)")
    }

    static let width: CGFloat = 390

    private func check(_ name: String, _ mode: Mode, height: CGFloat? = nil, @ViewBuilder _ view: () -> some View) throws {
        let framed = view()
            .padding(16)
            .frame(width: Self.width, height: height, alignment: .top)
            .background(Color(OuroInk.r(OuroHXStyle(theme: OuroTokens.pearl, scheme: mode.appearance.scheme, contrast: mode.appearance.contrast).colors.background)))
            .ouroTheme(.pearl)
        let result = try OuroSnapshot.verify(framed, named: "\(name)-\(mode.rawValue)", in: Self.directory, appearance: mode.appearance, tolerance: 0.002)
        #expect(result == .matched || result == .recorded, "\(name) \(mode): \(result); see \(Self.directory.path)")
    }

    /// Disabled buttons: muted, with labels that still read. (Glass is drawn by the gallery; ImageRenderer has none.)
    @Test(arguments: Mode.allCases) func buttonDisabled(_ mode: Mode) throws {
        try check("button-disabled", mode) {
            VStack(alignment: .leading, spacing: 10) {
                OuroButton("Publish recipe", systemImage: "paperplane", fullWidth: true) {}
                HStack(spacing: 8) {
                    OuroButton("Soft", variant: .soft) {}
                    OuroButton("Outline", variant: .outline) {}
                    OuroButton("Secondary", tone: .secondary) {}
                }
            }
            .disabled(true)
        }
    }

    @Test(arguments: Mode.allCases) func button(_ mode: Mode) throws {
        try check("button", mode) {
            VStack(alignment: .leading, spacing: 10) {
                OuroButton("Save recipe", systemImage: "checkmark", fullWidth: true) {}
                HStack(spacing: 8) {
                    OuroButton("Soft", variant: .soft) {}
                    OuroButton("Outline", variant: .outline) {}
                }
                HStack(spacing: 8) {
                    OuroButton("Delete", tone: .destructive) {}
                    // ImageRenderer draws no Liquid Glass (nor what is on it), so the glass variant is proven in the
                    // gallery captures and UI tests instead.
                    OuroButton("Pill", variant: .outline, shape: .pill) {}
                }
            }
        }
    }

    /// Every tone in each variant, with and without an icon.
    @Test(arguments: Mode.allCases) func badge(_ mode: Mode) throws {
        try check("badge", mode) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(OuroBadgeVariant.allCases, id: \.self) { variant in
                    HStack(spacing: 6) {
                        ForEach(OuroTone.allCases, id: \.self) { tone in
                            OuroBadge(tone.rawValue.capitalized, tone: tone, variant: variant)
                        }
                    }
                }
                HStack(spacing: 6) {
                    OuroBadge("Vegan", systemImage: "leaf", tone: .success, variant: .soft)
                    OuroBadge("25 min", systemImage: "timer")
                    OuroBadge("3", tone: .destructive)
                }
            }
        }
    }

    /// A card with a title, a description, an action, a body and a footer, and a small one with a body only, as
    /// A2UI's `Card` draws.
    @Test(arguments: Mode.allCases) func card(_ mode: Mode) throws {
        try check("card", mode) {
            VStack(spacing: 12) {
                OuroCard("Pantry", description: "What you have on hand") {
                    Text("Flour, rice, black beans, two lemons.")
                } action: {
                    OuroButton("Edit", variant: .plain, size: .sm) {}
                } footer: {
                    OuroBadge("4 items", systemImage: "basket")
                }
                OuroCard(size: .sm) {
                    Text("Lemon orzo with peas").font(.headline)
                    Text("25 minutes, serves four.")
                }
            }
        }
    }

    /// A divided group of rows (an icon tile with a badge, a picture, a pressable row, actions) and an outlined row.
    @Test(arguments: Mode.allCases) func item(_ mode: Mode) throws {
        try check("item", mode) {
            VStack(spacing: 12) {
                OuroItemGroup("Recipes") {
                    OuroItem("Braised short ribs", description: "3 hours, serves six", systemImage: "flame") {
                        OuroBadge("New", tone: .primary, variant: .soft)
                    }
                    OuroItem("Lemon orzo", description: "25 minutes", mediaSize: .sm) {
                        RoundedRectangle(cornerRadius: 0).fill(Color.orange)
                    } actions: {
                        OuroButton("Cook", variant: .outline, size: .sm) {}
                    }
                    OuroItem("Black bean soup", onPress: {})
                }
                OuroItem("Pantry", description: "12 items", systemImage: "basket", variant: .outline)
            }
        }
    }

    @Test(arguments: Mode.allCases) func emptyState(_ mode: Mode) throws {
        try check("empty-state", mode) {
            OuroEmptyState("No recipes yet", systemImage: "book.closed", description: "Start by creating your first recipe.") {
                OuroButton("Create recipe", systemImage: "plus") {}
            }
            .still()
        }
    }

    @Test(arguments: Mode.allCases) func banner(_ mode: Mode) throws {
        try check("banner", mode) {
            VStack(spacing: 10) {
                OuroBanner("Couldn't save", description: "Check your connection and try again.", tone: .destructive, onDismiss: {}) {
                    OuroButton("Try again", tone: .destructive, variant: .soft, size: .sm) {}
                }
                OuroBanner("Recipe saved", tone: .success)
            }
        }
    }

    @Test(arguments: Mode.allCases) func sheet(_ mode: Mode) throws {
        try check("sheet", mode, height: 300) {
            // ImageRenderer leaves a ScrollView's content out, so the body here is the header and the actions row.
            OuroSheetBody(title: "Save to cookbook", description: "Pick where this recipe lives.", hideTitle: false, detents: nil, closeLabel: "Close", close: {}) {
                Text("Weeknights")
            } footer: {
                OuroButton("Save", fullWidth: true) {}
            }
            .background(Color(OuroSheetPalette(style: OuroHXStyle(theme: OuroTokens.pearl, scheme: mode.appearance.scheme, contrast: mode.appearance.contrast)).surface))
        }
    }

    /// Toasts on their solid surface: ImageRenderer draws no glass, so the gallery's captures show the glass.
    @Test(arguments: Mode.allCases) func toast(_ mode: Mode) throws {
        try check("toast", mode) {
            VStack(spacing: 8) {
                OuroToastView(toast: OuroToast("Recipe saved", tone: .success), closeLabel: "Dismiss", tracksFocus: false, rendersGlass: false) {}
                OuroToastView(toast: OuroToast("Recipe deleted", action: OuroToastAction("Undo") {}), closeLabel: "Dismiss", tracksFocus: false, rendersGlass: false) {}
            }
        }
    }
}
