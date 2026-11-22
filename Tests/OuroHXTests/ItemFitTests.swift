@testable import OuroHX
import SwiftUI
import Testing

/// A row's actions keep their own width: squeezed beside the words, a segmented control truncated its labels
/// ("Sn…", "Cla…", "Ro…" in Gatefold's Fine-Tune on the folded Duo, review panel 2026-11-22). Where the actions
/// and a readable run of words don't fit side by side, the actions go under the words, as at the accessibility sizes.
@Suite @MainActor struct ItemFitTests {
    /// Frames seen by layout, by name, in the row's own space.
    final class Seen { var frames: [String: CGRect] = [:] }

    private func probe(_ name: String, _ seen: Seen) -> some View {
        GeometryReader { g -> Color in
            seen.frames[name] = g.frame(in: .named("row"))
            return Color.clear
        }
    }

    private func lay(width: CGFloat) -> Seen {
        let seen = Seen()
        let row = OuroItem("Line Spacing", systemImage: "arrow.up.and.down.text.horizontal", size: .sm) {
            Text("Snug  Easy  Airy  Slim  Classic  Roomy")
                .lineLimit(1)
                .background(probe("actions", seen))
        }
        .coordinateSpace(.named("row"))
        .frame(width: width)
        .ouroTheme(.pearl)
        _ = ImageRenderer(content: row).cgImage
        return seen
    }

    private var idealActionsWidth: CGFloat {
        let seen = Seen()
        let alone = Text("Snug  Easy  Airy  Slim  Classic  Roomy").lineLimit(1).fixedSize().background(probe("actions", seen))
            .coordinateSpace(.named("row"))
        _ = ImageRenderer(content: alone).cgImage
        return seen.frames["actions"]?.width ?? 0
    }

    @Test func actionsBesideTheWordsKeepTheirWidth() throws {
        let wide = lay(width: 600)
        let actions = try #require(wide.frames["actions"])
        #expect(abs(actions.width - idealActionsWidth) < 0.5, "actions \(actions.width) of \(idealActionsWidth)")
        #expect(actions.midY < 40, "beside the words, on the row's one line: \(actions)")
    }

    @Test func actionsTooWideToSitBesideTheWordsGoUnderThem() throws {
        let ideal = idealActionsWidth
        // Room for the actions and the icon, but not for the words beside them too.
        let narrow = lay(width: ideal + 40 + 16 + 40)
        let actions = try #require(narrow.frames["actions"])
        #expect(abs(actions.width - ideal) < 0.5, "actions \(actions.width) of \(ideal)")
        #expect(actions.minY > 30, "under the words: \(actions)")
    }
}
