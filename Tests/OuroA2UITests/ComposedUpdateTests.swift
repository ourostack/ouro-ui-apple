import Foundation
@testable import OuroA2UI
@testable import OuroHX
import OuroHXTesting
import SwiftUI
import Testing

/// An agent changes a card it already showed by sending only what changed (ouro-ui-core v0.19.0,
/// docs/decisions/2026-11-18-composed-tree-updates.md): `{ nodes?, data? }`, applied all or nothing. Core's update cases
/// (`standard/hx/composed/updates`, vendored in `Conformance/updates`) must give core's `expect` byte for byte.
@Suite struct ComposedUpdateTests {
    static var updates: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: ConformanceTests.root.appending(path: "updates").path))?.filter { $0.hasSuffix(".json") }.sorted() ?? []
    }

    static var app: A2UICatalog { get throws { try A2UICatalog(json: ConformanceTests.load("recipe.catalog.json")) } }

    @Test func everyUpdateCaseIsHere() {
        #expect(Self.updates.count == 5)
    }

    @Test(arguments: updates)
    func appliesToExpect(_ name: String) throws {
        let c = try ConformanceTests.load("updates/\(name)")
        let catalog = try A2UICatalog(json: ConformanceTests.load(c["catalog"]!.string!))
        let got: A2UIJSON
        switch ComposedTree.applyTreeUpdate(c["update"]!, to: try ComposedNode(json: c["tree"]!), data: c["data"], catalog: catalog) {
        case .success(let next):
            var o: A2UIObject = ["tree": next.tree.json]
            if let data = next.data { o["data"] = data }
            got = .object(o)
        case .failure(let p):
            got = .object(["problems": .array(p.problems.map(\.json))])
        }
        #expect(got.serialized == c["expect"]!.serialized, "\(name)")
        #expect(name.hasPrefix("invalid-") == (got["problems"] != nil))
    }

    /// core's `replace-and-set.json`: its tree with its data, and its update.
    static func replaceAndSet() throws -> (tree: ComposedTree, update: A2UIJSON, expect: A2UIJSON) {
        let c = try ConformanceTests.load("updates/replace-and-set.json")
        return (try ComposedTree(tree: c["tree"]!, data: c["data"]!, catalog: app), c["update"]!, c["expect"]!)
    }

    static func ouro(_ key: String, _ value: A2UIJSON, data: A2UIJSON? = nil) throws -> A2UIJSON {
        let id = try app.catalogID
        var o: A2UIObject = ["version": .string("1"), "catalogId": .string(id), key: value]
        if let data { o["data"] = data }
        return .object(o)
    }

    @Test func aTreeTakesAnUpdateAllOrNothing() throws {
        let (tree, update, expect) = try Self.replaceAndSet()
        let next = try tree.applying(update, catalog: Self.app)
        #expect(next.root.json.serialized == expect["tree"]?.serialized)
        #expect(next.data == expect["data"])
        let missing = try A2UIJSON.parse(#"{"nodes":[{"id":"subtitle","component":"Text","props":{"text":"x","tone":"default"},"children":[]}],"data":[{"path":"/servings","value":8}]}"#)
        let app = try Self.app
        #expect(throws: ComposedTreeProblems(problems: [ComposedTreeProblem(path: "/nodes/0/id", message: #""subtitle" is not in the tree; replace a node it has, or the node that should hold this one."#)])) {
            try tree.applying(missing, catalog: app)
        }
    }

    @Test func aDataEntryWritesAListOnlyAtAnIndexUpToItsLengthAndKeepsTheModelAnObject() throws {
        let tree = ComposedTree(root: ComposedNode(id: "root", component: "Card", props: [:]), data: .object(["items": .array([.string("a")])]))
        let app = try Self.app
        func problems(_ update: String) throws -> [ComposedTreeProblem] {
            do { _ = try tree.applying(try A2UIJSON.parse(update), catalog: app); return [] } catch let e as ComposedTreeProblems { return e.problems }
        }
        #expect(try problems(#"{"data":[{"path":"/items/1","value":"b"}]}"#) == [])
        #expect(try problems(#"{"data":[{"path":"/items/2","value":"c"}]}"#).first?.message == #"/items/2 names "2" in a list of 1; in a list, a segment is an index from 0 to 1."#)
        #expect(try problems(#"{"data":[{"path":"/items/x","value":"c"}]}"#).first?.path == "/data/0/path")
        #expect(try problems(#"{"data":[{"path":"/","value":[1]}]}"#) == [ComposedTreeProblem(path: "/data/0/value", message: "The data model is an object; set / only to an object.")])
        #expect(try problems(#"{"nodes":{},"data":[{"path":"servings","value":1},{"value":1,"extra":2}],"other":1}"#).map(\.path) == ["/other", "/nodes", "/data/0/path", "/data/1"])
        #expect(try problems(#"{"data":[{"path":"/n","value":1e999}]}"#) == [ComposedTreeProblem(path: "/data/0/value", message: "An update is JSON: text, finite numbers, true, false, null, lists and objects.")])
    }

    @Test func anMCPResultsUpdateAppliesToTheTreeItChanges() throws {
        let (tree, update, expect) = try Self.replaceAndSet()
        let app = try Self.app
        #expect(try tree.applying(ouro: Self.ouro("update", update), catalog: app).data == expect["data"])
        var wrong = try Self.ouro("update", try A2UIJSON.parse(#"{"data":[{"path":"/__proto__/x","value":1}]}"#)).object!
        #expect(throws: ComposedTreeProblems(problems: [ComposedTreeProblem(path: "/update/data/0/path", message: "path is a JSON pointer into the data model, such as /servings, and never names __proto__, constructor or prototype.")])) {
            try tree.applying(ouro: .object(wrong), catalog: app)
        }
        wrong["version"] = .string("2")
        #expect(throws: ComposedTreeProblems.self) { try tree.applying(ouro: .object(wrong), catalog: app) }
    }

    @Test func aSurfacesResultsLeaveTheLastTreeThatPassedAndTheNewestProblems() throws {
        let c = try ConformanceTests.load("updates/replace-and-set.json")
        let app = try Self.app
        let tree = try Self.ouro("tree", c["tree"]!, data: c["data"]!)
        let update = try Self.ouro("update", c["update"]!)
        let bad = try Self.ouro("update", try A2UIJSON.parse(#"{"nodes":[{"id":"subtitle","component":"Text","props":{"text":"x","tone":"default"},"children":[]}]}"#))
        let more = try Self.ouro("update", try A2UIJSON.parse(#"{"data":[{"path":"/servings","value":8}]}"#))

        let updated = ComposedSurface.shown([tree, update], catalog: app)
        #expect(updated.problems == nil && updated.tree?.root.json.serialized == c["expect"]?["tree"]?.serialized)
        let failed = ComposedSurface.shown([tree, update, bad], catalog: app)
        #expect(failed.problems?.problems.map(\.path) == ["/update/nodes/0/id"], "the newest result's problems show")
        #expect(failed.tree == updated.tree, "the last tree that passed is kept")
        let corrected = ComposedSurface.shown([tree, update, bad, more], catalog: app)
        #expect(corrected.problems == nil && corrected.tree?.data["servings"] == .number(8), "a corrected update applies to the last tree that passed")
        #expect(ComposedSurface.shown([update], catalog: app).problems?.problems.first?.path == "/update", "an update with no tree before it")
    }

    /// The data model a person filled in: four servings, and two shopping items.
    static let before: A2UIJSON = .object([
        "servings": .number(4),
        "items": .array([.object(["name": .string("orzo"), "qty": .number(1)]), .object(["name": .string("lemon"), "qty": .number(2)])]),
    ])

    @Test func anUpdateKeepsWhatThePersonEnteredExceptWhereTheAgentChangedItOrItsListItem() {
        let answers: A2UIObject = ["/servings": .number(6), "/items/1/qty": .number(5)]
        let renamed = A2UI.set(Self.before, "/items/0/name", .string("pasta"))
        #expect(ComposedSurface.kept(answers, from: Self.before, to: renamed) == answers, "another item changing keeps both answers")
        let lemon = A2UI.set(Self.before, "/items/1/name", .string("lime"))
        #expect(ComposedSurface.kept(answers, from: Self.before, to: lemon) == ["/servings": .number(6)], "the item the answer is in changed")
        let removed = A2UI.set(Self.before, "/items/0", .null)
        #expect(ComposedSurface.kept(answers, from: Self.before, to: removed) == ["/servings": .number(6)], "a removed item moves the next into its place")
        let servings = A2UI.set(Self.before, "/servings", .number(8))
        #expect(ComposedSurface.kept(answers, from: Self.before, to: servings) == ["/items/1/qty": .number(5)], "the agent's value wins where it set one")
        #expect(ComposedSurface.anchors(Self.before, "/items/1/qty") == ["/items/1", "/items/1/qty"])
        #expect(ComposedSurface.anchors(Self.before, "/servings") == ["/servings"])
    }

    @Test @MainActor func anUpdateThatDoesntApplyShowsTheShortAlert() throws {
        let c = try ConformanceTests.load("updates/replace-and-set.json")
        let bad = try Self.ouro("update", try A2UIJSON.parse(#"{"nodes":[{"id":"subtitle","component":"Text","props":{"text":"x","tone":"default"},"children":[]}]}"#))
        let results = [try Self.ouro("tree", c["tree"]!, data: c["data"]!), bad]
        func image(_ view: some View) throws -> Data {
            try #require(OuroSnapshot.render(view.padding(16).frame(width: 390, alignment: .top).ouroTheme(.pearl), size: nil).flatMap(OuroSnapshot.png))
        }
        let drawn = try image(ComposedSurface(results: results, catalog: Self.app, onPress: { _ in }, onHandoff: { _, _ in }))
        #expect(drawn == (try image(OuroBanner("This card can't be shown", description: "It didn't pass the checks for composed UI.", tone: .destructive))))
        let good = try image(ComposedSurface(results: Array(results.prefix(1)), catalog: Self.app, onPress: { _ in }, onHandoff: { _, _ in }))
        #expect(good != drawn, "a tree that passes draws itself")
    }
}
