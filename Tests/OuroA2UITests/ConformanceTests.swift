import Foundation
@testable import OuroA2UI
import Testing

/// Core's conformance cases (ouro-ui-core v0.9.0, `standard/hx/a2ui/conformance`): each stream must resolve to the
/// case's `expect`, byte for byte as core's reference resolver writes it: every surface's tree, or every problem.
@Suite struct ConformanceTests {
    static let root = Bundle.module.url(forResource: "Conformance", withExtension: nil)!

    static var cases: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: "cases").path))?.filter { $0.hasSuffix(".json") }.sorted() ?? []
    }

    static func load(_ path: String) throws -> A2UIJSON { try A2UIJSON.parse(Data(contentsOf: root.appending(path: path))) }

    @Test func everyCaseIsHere() {
        #expect(Self.cases.count == 11)
    }

    @Test(arguments: cases) func resolvesToExpect(_ name: String) throws {
        let c = try Self.load("cases/\(name)")
        let catalog = try A2UICatalog(json: Self.load(c["catalog"]!.string!))
        let got: A2UIJSON
        switch A2UI.resolve(c["messages"]!, catalog: catalog) {
        case .success(let surfaces):
            var o = A2UIObject()
            for (id, node) in surfaces { o[id] = node?.json ?? .null }
            got = .object(["surfaces": .object(o)])
        case .failure(let p):
            got = .object(["problems": .array(p.problems.map(\.json))])
        }
        #expect(got.serialized == c["expect"]!.serialized, "\(name)")
        #expect(name.hasPrefix("invalid-") == (got["problems"] != nil))
    }

    @Test func numbersReadAsJavaScriptWritesThem() {
        #expect(A2UIJSON.numberText(4) == "4")
        #expect(A2UIJSON.numberText(0.5) == "0.5")
        #expect(A2UIJSON.numberText(-12.25) == "-12.25")
        #expect(A2UIJSON.numberText(1e-7) == "1e-7")
        #expect(A2UIJSON.numberText(1e21) == "1e+21")
    }

    @Test func jsonRoundTripsKeyOrder() throws {
        let text = #"{"b":1,"a":[true,null,"x\n\"y"],"c":{"z":0.5,"y":"é"}}"#
        #expect(try A2UIJSON.parse(text).serialized == text)
    }

    @Test func aPressedButtonSaysThePersonPressedIt() throws {
        let c = try Self.load("cases/action-buttons.json")
        let catalog = try A2UICatalog(json: Self.load("recipe.catalog.json"))
        guard case .success(let surfaces) = A2UI.resolve(c["messages"]!, catalog: catalog), let root = surfaces.first?.1 else {
            Issue.record("action-buttons.json didn't resolve")
            return
        }
        let byPress = Dictionary(grouping: root.children, by: { $0.text("press") })
        let shop = try #require(root.children.first { $0.text("action") == "add_recipe_to_shopping_list" })
        let msg = try #require(A2UI.actionMessage(surfaceId: "buttons", button: shop, timestamp: "2026-11-13T00:00:00Z"))
        #expect(msg.serialized == #"{"version":"1.0","action":{"name":"add_recipe_to_shopping_list","surfaceId":"buttons","sourceComponentId":"shop","timestamp":"2026-11-13T00:00:00Z","userMessage":"Add ingredients to list","context":{"recipe":"rcp_123","servings":4},"metadata":{"extensions":{"bot_ouroboros_action":{"consent":"write","by":"person"}}}}}"#)
        let share = try #require(byPress["confirm"]?.first)
        #expect(A2UI.actionMessage(surfaceId: "buttons", button: share, timestamp: "t") == nil)
        #expect(A2UI.actionMessage(surfaceId: "buttons", button: share, timestamp: "t", confirmed: true)?["action"]?["metadata"]?["extensions"]?["bot_ouroboros_action"]?["confirmed"] == .bool(true))
        let order = try #require(byPress["handoff"]?.first)
        #expect(A2UI.actionMessage(surfaceId: "buttons", button: order, timestamp: "t", confirmed: true) == nil)
    }
}
