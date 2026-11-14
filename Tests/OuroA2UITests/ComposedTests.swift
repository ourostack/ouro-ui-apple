import Foundation
@testable import OuroA2UI
@testable import OuroHX
import OuroHXTesting
import SwiftUI
import Testing

/// Ouro's composed tree is drawn by ``ComposedSurface``, which knows no format; A2UI is its entry point
/// (ouro-ui-core docs/decisions/2026-11-14-composed-ui-own-tree.md). These check that a press is core's `PersonPress`,
/// and that A2UI's action message is that press wrapped, byte for byte what it was before the split.
@Suite @MainActor struct ComposedTests {
    static func buttons() throws -> ComposedNode {
        let c = try ConformanceTests.load("cases/action-buttons.json")
        let catalog = try A2UICatalog(json: ConformanceTests.load("recipe.catalog.json"))
        guard case .success(let surfaces) = A2UI.resolve(c["messages"]!, catalog: catalog), let root = surfaces.first?.1 else {
            throw A2UIProblems(problems: [])
        }
        return root
    }

    @Test func aPressIsTheActionThePreparedInputAndThePerson() throws {
        let root = try Self.buttons()
        let shop = try #require(root.children.first { $0.text("action") == "add_recipe_to_shopping_list" })
        let press = try #require(PersonPress.of(shop))
        #expect(press == PersonPress(action: "add_recipe_to_shopping_list", input: ["recipe": .string("rcp_123"), "servings": .number(4)], consent: "write",
                                     label: "Add ingredients to list", sourceComponentId: "shop", confirmed: false))
        let share = try #require(root.children.first { $0.text("press") == "confirm" })
        #expect(PersonPress.of(share) == nil, "a consequential button presses only after the person confirms")
        #expect(PersonPress.of(share, confirmed: true)?.confirmed == true)
        let order = try #require(root.children.first { $0.text("press") == "handoff" })
        #expect(PersonPress.of(order, confirmed: true) == nil, "a person-only button never presses")
    }

    @Test func a2uisActionMessageIsThePressWrapped() throws {
        let root = try Self.buttons()
        for button in root.children {
            for confirmed in [false, true] {
                let viaPress = PersonPress.of(button, confirmed: confirmed).map { A2UI.actionMessage(surfaceId: "buttons", press: $0, timestamp: "t") }
                #expect(viaPress == A2UI.actionMessage(surfaceId: "buttons", button: button, timestamp: "t", confirmed: confirmed))
            }
        }
    }

    @Test func theTreeDrawsWithNoFormat() throws {
        let view = ComposedSurface(try RenderTests.card(), onPress: { _ in }, onHandoff: { _, _ in })
            .padding(16)
            .frame(width: RenderTests.width, alignment: .top)
            .ouroTheme(.pearl)
        let image = try #require(OuroSnapshot.render(view, size: nil, appearance: .light))
        #expect(image.width > 0 && image.height > 0)
        if let dir = ProcessInfo.processInfo.environment["OURO_A2UI_CAPTURE"] {
            try OuroSnapshot.png(image)!.write(to: URL(filePath: dir).appending(path: "composed-surface-light.png"))
        }
    }
}
