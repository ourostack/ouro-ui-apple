import Foundation
@testable import OuroA2UI
import Testing

/// ouro-ui-core#91 (v0.18.2): a name a sender chooses is the catalog's only when the catalog itself has it, and a JSON
/// pointer never names `__proto__`, `constructor` or `prototype`. Swift's dictionaries have no prototype, but every kit
/// refuses the same trees and streams core refuses. Ported from core's `test/a2ui.test.mts` and `test/composed.test.mts`.
@Suite struct PointerSafetyTests {
    static var app: A2UICatalog { get throws { try A2UICatalog(json: ConformanceTests.load("recipe.catalog.json")) } }
    static var hx: A2UICatalog { get throws { try A2UICatalog(json: ConformanceTests.load("catalog.json")) } }

    /// A stream that creates surface `s` in the recipe catalog with these components (JSON text).
    static func create(_ components: String) throws -> A2UIJSON {
        let id = try app.catalogID
        return try A2UIJSON.parse(#"[{"version":"1.0","createSurface":{"surfaceId":"s","catalogId":"\#(id)","components":\#(components)}}]"#)
    }

    static func messages(_ stream: A2UIJSON) throws -> [String] { A2UI.validate(stream, catalog: try app).map(\.message) }

    // MARK: Names

    @Test(arguments: ["constructor", "toString"])
    func theStreamValidatorTakesOnlyTheCatalogsOwnNames(_ name: String) throws {
        #expect(try Self.messages(Self.create(#"[{"id":"root","component":"\#(name)"}]"#)).contains { $0.contains("is not in this catalog") }, "component \(name)")
        #expect(try Self.messages(Self.create(#"[{"id":"root","component":"ActionButton","action":"\#(name)"}]"#)).contains { $0.contains("not one of the app's actions") }, "action \(name)")
        let input = try Self.create(#"[{"id":"root","component":"ActionButton","action":"share_recipe","input":{"recipe":"r","with":"s@e.com","\#(name)":true}}]"#)
        #expect(try Self.messages(input).contains { $0.contains("share_recipe has no input \(name)") }, "input \(name)")
    }

    @Test(arguments: ["constructor", "toString", "__proto__", "hasOwnProperty"])
    func theTreeValidatorTakesOnlyTheCatalogsOwnNames(_ name: String) throws {
        let app = try Self.app
        let extra = try ComposedTreeTests.forged(2) { props in
            props["input"] = .object(["recipe": .string("rcp_123"), "with": .string("sam@example.com"), name: .bool(true)])
        }
        #expect(ComposedTree.validate(extra, catalog: app).contains { $0.message.contains("share_recipe has no input \(name)") }, "input \(name)")
        let component = ComposedNode(id: "root", component: "Card", props: [:], children: [ComposedNode(id: "x", component: name, props: [:])]).json
        #expect(ComposedTree.validate(component, catalog: app).first?.message.contains("is not in this catalog") == true, "component \(name)")
        let action = try ComposedTreeTests.forged(0) { $0["action"] = .string(name) }
        #expect(ComposedTree.validate(action, catalog: app).first?.message.contains("not one of the app's actions") == true, "action \(name)")
    }

    @Test func aCatalogNamesOnlyOuroHXsComponents() throws {
        let catalog = try A2UIJSON.parse(#"{"catalogId":"x","components":{"Text":{},"toString":{}}}"#)
        #expect(throws: A2UICatalogError.self) { try A2UICatalog(json: catalog) }
        do { _ = try A2UICatalog(json: catalog) } catch {
            #expect((error as? A2UICatalogError)?.description.contains("component toString is not Ouro HX's") == true)
        }
    }

    // MARK: Pointers

    @Test(arguments: ["/__proto__/polluted", "/constructor/prototype/polluted", "/a/__proto__/toString"])
    func aPointerThroughAPrototypeWritesNothing(_ pointer: String) {
        let data: A2UIJSON = .object(["a": .object([:])])
        #expect(A2UI.set(data, pointer, .string("yes")) == data)
        #expect(A2UI.set(data, pointer, .null) == data)
        #expect(!A2UI.isDataPointer(pointer))
    }

    @Test func aPointerReadsOnlyWhatTheDataHolds() {
        #expect(A2UI.get(.object(["a": .number(1)]), "/toString") == nil)
        #expect(A2UI.get(.object(["a": .number(1)]), "/__proto__") == nil)
        #expect(A2UI.isDataPointer("/servings") && A2UI.isSafePointer("items/0") && !A2UI.isSafePointer("items/__proto__"))
    }

    @Test func updateDataModelCantWriteThroughAPrototype() throws {
        var stream = try Self.create(#"[{"id":"root","component":"Text","text":"hi"}]"#).array!
        stream.append(try A2UIJSON.parse(#"{"version":"1.0","updateDataModel":{"surfaceId":"s","path":"/__proto__/polluted","value":"yes"}}"#))
        #expect(A2UI.validate(.array(stream), catalog: try Self.app).contains { $0.path == "/1/updateDataModel/path" })
    }

    @Test(arguments: ["/__proto__/x", "constructor", "items/__proto__"])
    func aBindingThroughAPrototypeIsRefused(_ pointer: String) throws {
        let stream = try Self.create(#"[{"id":"root","component":"Card","children":["f","b"]},{"id":"f","component":"Text","text":{"@path":"\#(pointer)"}},{"id":"b","component":"ActionButton","action":"share_recipe","input":{"recipe":{"@path":"\#(pointer)"},"with":"s@e.com"}}]"#)
        let problems = A2UI.validate(stream, catalog: try Self.app).filter { $0.message.contains("never through __proto__") }
        #expect(problems.map(\.path) == ["/0/createSurface/components/1/text", "/0/createSurface/components/2/input/recipe"])
        #expect(problems.first?.message == "\(A2UIJSON.string(pointer).serialized) points into the data model, never through __proto__, constructor or prototype.")
    }

    @Test func aTemplateThroughAPrototypeIsRefused() throws {
        let stream = try Self.create(#"[{"id":"root","component":"Stack","children":{"componentId":"t","path":"/__proto__"}},{"id":"t","component":"Text","text":"x"}]"#)
        #expect(A2UI.validate(stream, catalog: try Self.app).contains { $0.path == "/0/createSurface/components/0/children" && $0.message.contains("never through __proto__") })
    }

    @Test func aTreesFieldOrBoundInputThroughAPrototypeIsRefused() throws {
        let field = ComposedNode(id: "root", component: "Card", props: [:], children: [
            ComposedNode(id: "f", component: "TextField", props: ["label": .string("X"), "value": .string("/__proto__/x"), "type": .string("text"), "multiline": .bool(false)]),
        ]).json
        #expect(ComposedTree.validate(field, catalog: try Self.hx).first?.message.contains("JSON pointer into the data model") == true)
        let bound = try ComposedTreeTests.forged(1) { $0["input"] = .object(["recipe": .string("rcp_123"), "servings": .object(["@path": .string("/__proto__/servings")])]) }
        #expect(ComposedTree.validate(bound, catalog: try Self.app).contains { $0.path == "/children/0/props/input/servings" })
    }
}
