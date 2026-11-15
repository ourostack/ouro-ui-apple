@testable import OuroHX
@testable import OuroHXTesting
import SwiftUI
import Testing

/// A still render (snapshot, `ImageRenderer`, headless screenshot) of a component with an arrival draws it settled
/// once arrivals are off, not as the arrival's clear first frame.
@Suite @MainActor struct ArrivalTests {
    /// How many pixels of a render have any ink.
    private func inked(_ view: some View) throws -> Int {
        let image = try #require(OuroSnapshot.render(view.frame(width: 390, height: 320).ouroTheme(.pearl)))
        let bytes = try #require(OuroSnapshot.rgba(image))
        return stride(from: 3, to: bytes.count, by: 4).reduce(0) { $0 + (bytes[$1] > 0 ? 1 : 0) }
    }

    @Test func emptyStateWithArrivalsOffRendersSettled() throws {
        let still = try inked(
            OuroEmptyState("No recipes yet", systemImage: "book.closed", description: "Start by creating your first recipe.") {
                OuroButton("Create recipe", systemImage: "plus") {}
            }
            .ouroArrivals(false)
        )
        let settled = try inked(
            OuroEmptyState("No recipes yet", systemImage: "book.closed", description: "Start by creating your first recipe.") {
                OuroButton("Create recipe", systemImage: "plus") {}
            }
            .still()
        )
        #expect(still > 1_000, "the empty state is drawn, not its clear first frame")
        #expect(still == settled, "arrivals off draws exactly what the settled snapshot draws")
    }

    @Test func arrivalsAreOnByDefault() {
        #expect(EnvironmentValues().ouroArrivals)
    }
}
