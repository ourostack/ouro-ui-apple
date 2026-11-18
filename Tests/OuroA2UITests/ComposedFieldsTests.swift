import Foundation
@testable import OuroA2UI
@testable import OuroHX
import OuroHXTesting
import SwiftUI
import Testing

/// The fields a person fills in (ouro-ui-core docs/decisions/2026-11-17-composed-fields.md): a `TextField`, `Checkbox`
/// or `Select` writes the person's answer into the data model at its `value`, and a button bound to that path sends
/// what they entered, in the confirm sheet and in the press. Ported from core's `test/composed.test.mts`, on core's
/// `inputs.json`.
@Suite @MainActor struct ComposedFieldsTests {
    /// core's `inputs.json`: its resolved tree, as core's `expect` writes it, and the data model it starts from.
    nonisolated static func plan() throws -> (tree: ComposedNode, data: A2UIJSON) {
        let c = try ConformanceTests.load("cases/inputs.json")
        let tree = try ComposedNode(json: #require(c["expect"]?["surfaces"]?["plan"]))
        return (tree, try #require(c["messages"]?.array?.first?["createSurface"]?["dataModel"]))
    }

    static var app: A2UICatalog { get throws { try A2UICatalog(json: ConformanceTests.load("recipe.catalog.json")) } }
    static var hx: A2UICatalog { get throws { try A2UICatalog(json: ConformanceTests.load("catalog.json")) } }

    @Test func aFieldWritesTheAnswerAndAButtonBoundToItSendsIt() throws {
        let (plan, start) = try Self.plan()
        for name in A2UI.inputComponents { #expect(plan.flattened.contains { $0.component == name }, "the case covers \(name)") }
        let shop = try #require(plan.find("shop"))
        let share = try #require(plan.find("share"))
        #expect(A2UI.get(start, try #require(plan.find("servings")).text("value")) == .number(4), "a field starts with what the data holds")
        var data = A2UI.set(start, "/servings", .number(6))
        data = A2UI.set(data, "/share/with", .string("sam@example.com"))
        #expect(PersonPress.of(shop, data: data)?.input == ["recipe": .string("rcp_lemon_orzo"), "servings": .number(6)],
                "the press sends the answer, and the unbound recipe stays as resolved")
        let rows = ComposedTree.resolveButton(share, data: data).props["confirm"]?["fields"]
        #expect(rows?.serialized == #"[{"label":"Recipe","value":"Lemon orzo","raw":"rcp_lemon_orzo"},{"label":"Send to","value":"sam@example.com"}]"#,
                "the confirm sheet shows what the person typed")
        #expect(PersonPress.of(share, confirmed: true, data: data)?.input["with"] == .string("sam@example.com"))
        #expect(PersonPress.of(share, confirmed: true, data: A2UI.set(data, "/share/with", .null))?.input["with"] == .null,
                "an empty answer is sent as null, and the app's tool refuses it")
        let title = try #require(plan.find("title"))
        #expect(ComposedTree.resolveButton(title, data: data) == title, "a node with nothing bound comes back as it is")
        #expect(PersonPress.of(shop)?.input["servings"] == .object(["@path": .string("/servings")]), "without data, a press is the tree as it is")
    }

    /// A button with an input bound to `/recipe` in a recipe-catalog surface whose data model is `dataModel`.
    static func boundToData(_ dataModel: String) throws -> ComposedNode {
        let id = try app.catalogID
        let messages = try A2UIJSON.parse(#"[{"version":"1.0","createSurface":{"surfaceId":"s","catalogId":"\#(id)","dataModel":\#(dataModel),"components":[{"id":"root","component":"Card","children":["share"]},{"id":"share","component":"ActionButton","action":"share_recipe","input":{"recipe":{"@path":"/recipe"},"with":"sam@example.com"},"@accessibility":{"label":"Share it"}}]}}]"#)
        guard case .success(let surfaces) = A2UI.resolve(messages, catalog: try app), let root = surfaces.first?.1 else { throw A2UIProblems(problems: []) }
        return try #require(root.children.first)
    }

    @Test func aButtonBoundToDataNoFieldWritesReadsItNowAndNeverFollowsAValueShapedLikeABinding() throws {
        let object = try Self.boundToData(#"{"recipe":{"id":"r1"}}"#)
        #expect(object.props["input"]?.serialized == #"{"recipe":{"id":"r1"},"with":"sam@example.com"}"#)
        #expect(ComposedTree.validate(Self.card([object]), catalog: try Self.app) == [])
        let posing = try Self.boundToData(#"{"recipe":{"@path":"/secret"},"secret":"S"}"#)
        #expect(posing.props["input"]?["recipe"] == .string(#"{"@path":"/secret"}"#))
        #expect(PersonPress.of(posing, confirmed: true, data: .object(["secret": .string("S")]))?.input["recipe"] == .string(#"{"@path":"/secret"}"#))
        #expect(object.props.keys.last == "@label", "a button's @label comes after the catalog's props, as before fields")
    }

    static func card(_ children: [ComposedNode]) -> A2UIJSON {
        ComposedNode(id: "root", component: "Card", props: [:], children: children).json
    }

    @Test func aFieldsValueIsAPointerIntoTheDataAndABoundInputIsOneToo() throws {
        func field(_ extra: A2UIObject) -> A2UIJSON {
            var props: A2UIObject = ["label": .string("Servings"), "type": .string("text"), "multiline": .bool(false)]
            for (k, v) in extra.pairs { props[k] = v }
            return Self.card([ComposedNode(id: "f", component: "TextField", props: props)])
        }
        #expect(ComposedTree.validate(field(["value": .string("/servings")]), catalog: try Self.hx) == [])
        #expect(ComposedTree.validate(field(["value": .string("servings")]), catalog: try Self.hx).first?.message
                == #"value is a JSON pointer into the data model, such as /servings, got "servings"."#)
        #expect(ComposedTree.validate(field([:]), catalog: try Self.hx).first?.message.hasPrefix("TextField needs value") == true)
        var shop = try #require(try ComposedTests.buttons().children.first { $0.id == "shop" }).props
        shop["input"] = .object(["recipe": .string("rcp_123"), "servings": .object(["@path": .string("servings")])])
        let problems = ComposedTree.validate(Self.card([ComposedNode(id: "shop", component: "ActionButton", props: shop)]), catalog: try Self.app)
        #expect(problems == [ComposedTreeProblem(path: "/children/0/props/input/servings", message: #"servings is a value, or {"@path": "/..."} bound to the data model."#)])
    }

    // MARK: The surface keeps the data model and presses with it

    /// The data model a surface keeps, outside SwiftUI: what it was given and the person's answers over it, and the
    /// context its fields and buttons share.
    final class Model: @unchecked Sendable {
        let given: A2UIJSON
        var answers = A2UIObject()
        var presses: [PersonPress] = []
        init(_ data: A2UIJSON) { given = data }

        var data: A2UIJSON { A2UIPressContext.answered(given, answers) }

        @MainActor var context: A2UIPressContext {
            A2UIPressContext(data: given, answers: Binding(get: { self.answers }, set: { self.answers = $0 }),
                             onPress: { self.presses.append($0) }, onHandoff: { _, _ in })
        }
    }

    @Test func editingAFieldChangesWhatAPressSends() throws {
        let (plan, start) = try Self.plan()
        let model = Model(start)
        let shop = try #require(plan.find("shop"))
        model.context.send(shop, confirmed: false)
        #expect(model.presses.last?.input["servings"] == .number(4), "the press sends what the data held")
        // What the TextField writes as the person types 6, as A2UITextField does.
        model.context.value(at: "/servings").wrappedValue = A2UIFields.answer("6", number: true, decimalSeparator: ".")
        model.context.send(shop, confirmed: false)
        #expect(model.presses.last?.input == ["recipe": .string("rcp_lemon_orzo"), "servings": .number(6)])
        model.context.value(at: "/servings").wrappedValue = A2UIFields.answer("", number: true, decimalSeparator: ".")
        model.context.send(shop, confirmed: false)
        #expect(model.presses.last?.input["servings"] == .null, "an emptied number field sends null")
        #expect(A2UI.get(model.data, "/servings") == nil)
    }

    @Test func theConfirmSheetShowsWhatThePersonTyped() throws {
        let (plan, start) = try Self.plan()
        let model = Model(start)
        let share = try #require(plan.find("share"))
        #expect(A2UIActionButton.confirmRows(share, data: model.data).map(A2UIConfirmFields.spoken) == ["Recipe, Lemon orzo, rcp_lemon_orzo", "Send to, "])
        model.context.value(at: "/share/with").wrappedValue = A2UIFields.answer("sam@example.com", number: false)
        #expect(A2UIActionButton.confirmRows(share, data: model.data).map(A2UIConfirmFields.spoken) == ["Recipe, Lemon orzo, rcp_lemon_orzo", "Send to, sam@example.com"])
        model.context.send(share, confirmed: false)
        #expect(model.presses.isEmpty, "a consequential button presses only after the person confirms")
        model.context.send(share, confirmed: true)
        #expect(model.presses.last?.input["with"] == .string("sam@example.com"))
        #expect(model.presses.last?.confirmed == true)
    }

    @Test func aTextFieldShowsTheDataAndWritesWhatIsTyped() throws {
        let model = Model(try Self.plan().data)
        let typed = Box<String?>(nil)
        let typedBinding = Binding(get: { typed.value }, set: { typed.value = $0 })
        let servings = A2UITextField.text(model.context.value(at: "/servings"), typed: typedBinding, number: true)
        #expect(servings.wrappedValue == "4", "a number field shows the number the data holds")
        servings.wrappedValue = "6"
        #expect(A2UI.get(model.data, "/servings") == .number(6), "and writes a number")
        servings.wrappedValue = ""
        #expect(A2UI.get(model.data, "/servings") == nil, "an emptied number field leaves the data without one")
        #expect(servings.wrappedValue == "", "and still shows what the person typed")
        let with = A2UITextField.text(model.context.value(at: "/share/with"), typed: Binding(get: { nil }, set: { _ in }), number: false)
        #expect(with.wrappedValue == "")
        with.wrappedValue = "sam@example.com"
        #expect(A2UI.get(model.data, "/share/with") == .string("sam@example.com"))
    }

    @Test func checkboxAndSelectWriteABooleanAndTheOptionsText() throws {
        let model = Model(try Self.plan().data)
        let tick = A2UIFields.bool(model.context.value(at: "/vegetarian"))
        #expect(tick.wrappedValue, "it starts with what the data holds")
        tick.wrappedValue = false
        #expect(A2UI.get(model.data, "/vegetarian") == .bool(false))
        #expect(!A2UIFields.bool(model.context.value(at: "/missing")).wrappedValue, "nothing at its path is unticked")
        model.context.value(at: "/oven").wrappedValue = .string("Grill")
        #expect(A2UI.get(model.data, "/oven") == .string("Grill"))
    }

    @Test(arguments: [("6", A2UIJSON.number(6)), (" 2.5 ", .number(2.5)), ("-1", .number(-1)), ("1e3", .number(1000)), ("", .null), ("six", .null),
                      ("0x10", .null), ("inf", .null), ("1,000", .null), ("2,5", .null)])
    func aNumberFieldWritesANumberOrNull(typed: String, written: A2UIJSON) {
        #expect(A2UIFields.answer(typed, number: true, decimalSeparator: ".") == written)
    }

    /// Where the locale's decimal mark is a comma, "2,5" is two and a half; a comma never groups thousands.
    @Test func aCommaIsADecimalMarkOnlyWhereTheLocaleSaysSo() {
        #expect(A2UIFields.answer("2,5", number: true, decimalSeparator: ",") == .number(2.5))
        #expect(A2UIFields.answer("1.000,5", number: true, decimalSeparator: ",") == .null)
        #expect(A2UIFields.answer("1,000", number: true, decimalSeparator: ".") == .null, "never read as 1")
    }

    /// An agent's update to one pointer shows in that field, and the person's other answers stay.
    @Test func anUpdateToTheDataKeepsThePersonsOtherAnswers() throws {
        let start = try Self.plan().data
        let answers: A2UIObject = ["/servings": .number(6), "/share/with": .string("sam@example.com")]
        let updated = A2UI.set(A2UI.set(start, "/servings", .number(8)), "/recipe/title", .string("Lemony orzo"))
        let kept = ComposedSurface.kept(answers, from: start, to: updated)
        #expect(kept == ["/share/with": .string("sam@example.com")])
        #expect(A2UIPressContext.answered(updated, kept)["servings"] == .number(8))
        #expect(ComposedSurface.kept(answers, from: start, to: start) == answers, "data that didn't change keeps every answer")
    }

    @Test func aTextFieldWritesTheTextAsTyped() {
        #expect(A2UIFields.answer(" 6 ", number: false) == .string(" 6 "))
        #expect(A2UIFields.answer("1,000", number: false) == .string("1,000"))
        #expect(A2UIFields.answer("", number: false) == .string(""))
    }

    @Test func a2uiSurfacesCarryTheirDataModel() throws {
        let c = try ConformanceTests.load("cases/inputs.json")
        guard case .success(let surfaces) = A2UI.resolveSurfaces(c["messages"]!, catalog: try Self.app), let plan = surfaces.first else {
            Issue.record("inputs.json didn't resolve")
            return
        }
        #expect(plan.id == "plan")
        #expect(plan.node?.json.serialized == c["expect"]?["surfaces"]?["plan"]?.serialized)
        #expect(plan.data == c["messages"]?.array?.first?["createSurface"]?["dataModel"])
        let surface = A2UISurface(plan, onAction: { _ in }, onHandoff: { _, _ in })
        #expect(surface.data == plan.data && surface.surfaceId == "plan")
        guard case .success(let pairs) = A2UI.resolve(c["messages"]!, catalog: try Self.app) else { return }
        #expect(pairs.map(\.0) == ["plan"] && pairs.first?.1 == plan.node)
    }

    @Test func theFieldsDraw() throws {
        let c = try ConformanceTests.load("cases/inputs.json")
        guard case .success(let surfaces) = A2UI.resolveSurfaces(c["messages"]!, catalog: try Self.app), let plan = surfaces.first else {
            Issue.record("inputs.json didn't resolve")
            return
        }
        let view = A2UISurface(plan, onAction: { _ in }, onHandoff: { _, _ in })
            .padding(16)
            .frame(width: RenderTests.width, alignment: .top)
            .ouroTheme(.pearl)
        let image = try #require(OuroSnapshot.render(view, size: nil, appearance: .light))
        #expect(image.width > 0 && image.height > 0)
        if let dir = ProcessInfo.processInfo.environment["OURO_A2UI_CAPTURE"] {
            try OuroSnapshot.png(image)!.write(to: URL(filePath: dir).appending(path: "composed-fields-light.png"))
        }
    }
}

/// A tree that didn't come through A2UI, such as an MCP tool result's `structuredContent.ouro` or the app's own code:
/// decoded from JSON and checked against the catalog (core's `validateTree`) before ``ComposedSurface`` draws it.
@Suite struct ComposedTreeTests {
    static var app: A2UICatalog { get throws { try A2UICatalog(json: ConformanceTests.load("recipe.catalog.json")) } }

    /// core's `action-buttons.json` tree, as core's `expect` writes it.
    static func buttons() throws -> A2UIJSON {
        try #require(ConformanceTests.load("cases/action-buttons.json")["expect"]?["surfaces"]?["buttons"])
    }

    /// `buttons()` with its `index`th button's props changed by `change`.
    static func forged(_ index: Int, _ change: (inout A2UIObject) -> Void) throws -> A2UIJSON {
        let tree = try ComposedNode(json: buttons())
        var props = tree.children[index].props
        change(&props)
        let button = ComposedNode(id: tree.children[index].id, component: "ActionButton", props: props)
        return ComposedNode(id: "root", component: "Card", props: [:], children: [button]).json
    }

    @Test func aTreeDecodesAsCoreWritesIt() throws {
        let json = try Self.buttons()
        let tree = try ComposedNode(json: json)
        #expect(tree.json.serialized == json.serialized)
        #expect(tree.children.map(\.id) == ["open", "shop", "share", "order"])
    }

    @Test func aNodeOfAnotherShapeDoesntDecode() throws {
        let bad = try A2UIJSON.parse(#"{"id":"root","component":"Card","props":{},"children":[{"id":"a","component":"Text","props":{}}]}"#)
        #expect(throws: ComposedTreeProblems(problems: [ComposedTreeProblem(path: "/children/0", message: "A node is { id, component, props, children }.")])) {
            try ComposedNode(json: bad)
        }
    }

    @Test func anMCPToolResultsTreeIsCheckedThenDrawn() throws {
        let (plan, data) = try ComposedFieldsTests.plan()
        let ouro: A2UIJSON = .object(["version": .string("1"), "catalogId": .string(try Self.app.catalogID), "tree": plan.json, "data": data])
        let tree = try ComposedTree(ouro: ouro, catalog: Self.app)
        #expect(tree.root == plan && tree.data == data)
        let withoutData: A2UIJSON = .object(["version": .string("1"), "catalogId": .string(try Self.app.catalogID), "tree": plan.json])
        #expect(try ComposedTree(ouro: withoutData, catalog: Self.app).data == .object(A2UIObject()))
    }

    @Test func anMCPToolResultOfAnotherVersionOrCatalogIsRefused() throws {
        let ouro: A2UIJSON = .object(["version": .string("2"), "catalogId": .string("https://example.com/other.json"), "tree": try Self.buttons(), "data": .array([])])
        let app = try Self.app
        do {
            _ = try ComposedTree(ouro: ouro, catalog: app)
            Issue.record("it decoded")
        } catch {
            #expect(error.problems.map(\.path) == ["/version", "/catalogId", "/data"])
        }
    }

    @Test func aForgedTreeIsRefusedWithWhereAndWhy() throws {
        let relabeled = try Self.forged(2) { $0["label"] = .string("Add to list") }
        #expect(ComposedTree.validate(relabeled, catalog: try Self.app).first?.message == #"share_recipe's label is the catalog's "Share recipe", never the sender's."#)
        let loosened = try Self.forged(2) { $0["press"] = .string("run") }
        #expect(ComposedTree.validate(loosened, catalog: try Self.app).contains { $0.path == "/children/0/props/press" })
        let unconfirmed = try Self.forged(2) { $0["confirm"] = nil }
        #expect(ComposedTree.validate(unconfirmed, catalog: try Self.app).first?.message.contains("confirms, with the catalog's title") == true)
        let confirmsWrite = try Self.forged(1) { $0["confirm"] = try? ComposedNode(json: Self.buttons()).children[2].props["confirm"] }
        #expect(ComposedTree.validate(confirmsWrite, catalog: try Self.app).first?.message.contains("doesn't confirm") == true)
        let ordered = try Self.forged(3) { $0["input"] = .object(["recipe": .string("rcp_123")]) }
        #expect(ComposedTree.validate(ordered, catalog: try Self.app).first?.refusal?["error"]?["code"] == .string("person-only"))
        let unknown = try Self.forged(0) { $0["action"] = .string("pay") }
        #expect(ComposedTree.validate(unknown, catalog: try Self.app).first?.message.contains("not one of the app's actions") == true)
        let app = try Self.app
        #expect(throws: ComposedTreeProblems.self) { try ComposedTree(tree: relabeled, catalog: app) }
    }

    /// `share`'s confirm rows changed by `change`.
    static func rows(_ change: @escaping (inout [A2UIJSON]) -> Void) throws -> A2UIJSON {
        try forged(2) { props in
            guard var confirm = props["confirm"]?.object, var fields = confirm["fields"]?.array else { return }
            change(&fields)
            confirm["fields"] = .array(fields)
            props["confirm"] = .object(confirm)
        }
    }

    /// A row as an object, changed by `change`.
    static func row(_ json: A2UIJSON, _ change: (inout A2UIObject) -> Void) -> A2UIJSON {
        var o = json.object ?? A2UIObject()
        change(&o)
        return .object(o)
    }

    static let rowMessage = #"share_recipe's confirm sheet shows a row for each prepared input, with its label and the value that will be sent; the catalog's rows are [{"label":"Recipe","value":"rcp_123"},{"label":"Send to","value":"sam@example.com"}]."#

    /// core#88: a confirm sheet can't show the person one value and send another.
    @Test func aConfirmSheetCantShowOneValueAndSendAnother() throws {
        let app = try Self.app
        let forgedValue = try Self.rows { $0[1] = Self.row($0[1]) { $0["value"] = .string("friend@example.com") } }
        #expect(ComposedTree.validate(forgedValue, catalog: app) == [ComposedTreeProblem(path: "/children/0/props/confirm/fields", message: Self.rowMessage)])
        let dropped = try Self.rows { $0.removeLast() }
        #expect(ComposedTree.validate(dropped, catalog: app).map(\.message) == [Self.rowMessage])
        let relabeled = try Self.rows { $0[0] = Self.row($0[0]) { $0["label"] = .string("Dinner") } }
        #expect(ComposedTree.validate(relabeled, catalog: app).map(\.message) == [Self.rowMessage])
        let named = try Self.rows { $0[0] = Self.row($0[0]) { $0["raw"] = $0["value"]; $0["value"] = .string("My lemon orzo") } }
        #expect(ComposedTree.validate(named, catalog: app) == [], "the app's own words for an id may differ, beside the id itself")
        let hidden = try Self.rows { $0[1] = Self.row($0[1]) { $0["raw"] = $0["value"]; $0["value"] = .string("friend@example.com") } }
        #expect(ComposedTree.validate(hidden, catalog: app).map(\.message) == [Self.rowMessage],
                "a field that is no id can't show other words with the real value small beside them")
    }

    /// Rows compare as JavaScript compares them: "é" written as one character isn't "e" and a combining accent.
    @Test func aRowMatchesTheSentValueCharacterForCharacter() throws {
        let tree = try Self.forged(2) { props in
            props["input"] = .object(["recipe": .string("rcp_123"), "with": .string("cafe\u{301}@example.com")])
            props["confirm"] = .object(["title": .string("Share recipe"), "description": .string("Send this recipe to someone."), "fields": .array([
                .object(["label": .string("Recipe"), "value": .string("rcp_123")]),
                .object(["label": .string("Send to"), "value": .string("caf\u{E9}@example.com")]),
            ])])
        }
        #expect(ComposedTree.validate(tree, catalog: try Self.app).map(\.path) == ["/children/0/props/confirm/fields"])
    }

    @Test func anInputTheCatalogDoesntCarryIsRefused() throws {
        let extra = try Self.forged(2) { props in
            var input = props["input"]?.object ?? A2UIObject()
            input["everyone"] = .bool(true)
            props["input"] = .object(input)
        }
        #expect(ComposedTree.validate(extra, catalog: try Self.app).first
                == ComposedTreeProblem(path: "/children/0/props/input/everyone", message: "share_recipe has no input everyone; its fields are recipe, recipeTitle, with."),
                "an input the catalog doesn't carry would be sent with no row")
    }

    @Test func aTreeNamesOnlyTheCatalogsComponentsAndTheirPropsResolved() throws {
        let hx = try A2UICatalog(json: ConformanceTests.load("catalog.json"))
        func first(_ text: String) throws -> String? { ComposedTree.validate(try A2UIJSON.parse(text), catalog: hx).first?.message }
        #expect(try first(#"{"id":"root","component":"Button","props":{},"children":[]}"#)?.contains("not in this catalog") == true)
        #expect(try first(#"{"id":"root","component":"Text","props":{"text":{"@path":"/x"},"tone":"default"},"children":[]}"#)?.contains("text is text") == true)
        #expect(try first(#"{"id":"root","component":"Badge","props":{"text":"Hi","tone":"loud"},"children":[]}"#)?.contains("one of neutral, info") == true)
        #expect(try first(#"{"id":"root","component":"Text","props":{"text":"Hi","tone":"default","colour":"red"},"children":[]}"#) == "Text has no colour.")
        #expect(try first(#"{"id":"root","component":"Image","props":{"url":"https://x/y.jpg","aspect":"square"},"children":[]}"#)?.contains("needs description") == true)
        #expect(try first(#"{"id":"root","component":"Separator","props":{},"children":[{"id":"a","component":"Separator","props":{},"children":[]}]}"#) == "Separator has no children.")
        #expect(try first(#"{"id":"root","component":"Card"}"#) == "A node is { id, component, props, children }.")
        #expect(try first(#"{"id":"root","component":"Card","props":{},"children":[{"id":"a","component":"ActionButton","props":{},"children":[]}]}"#)?.contains("not in this catalog") == true,
                "HX's own catalog has no actions, so no button")
    }
}

/// A value a test's binding reads and writes.
final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

extension A2UINode {
    func find(_ id: String) -> A2UINode? { flattened.first { $0.id == id } }
}
