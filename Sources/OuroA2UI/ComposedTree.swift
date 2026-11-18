import Foundation

// Ouro's composed tree, whatever format it arrived in: core's src/composed.mts, ported. It holds the tree's validator,
// the props of an action's button, a button as it stands when the person presses it, and what a press sends. Nothing
// here knows a format. Decisions: ouro-ui-core docs/decisions/2026-11-14-composed-ui-own-tree.md and
// 2026-11-17-composed-fields.md.

/// A node of Ouro's composed tree: the component, its props resolved, and its children. Core's `ComposedNode`.
public typealias ComposedNode = A2UINode

extension A2UINode {
    /// A node read from JSON: `{ id, component, props, children }`, as core writes it. Throws
    /// ``ComposedTreeProblems`` when any node in it has another shape; it checks nothing against a catalog, so draw a
    /// tree that came from outside your code through ``ComposedTree/init(tree:data:catalog:)``, which does.
    public init(json: A2UIJSON) throws(ComposedTreeProblems) {
        try self.init(json: json, path: "")
    }

    private init(json: A2UIJSON, path: String) throws(ComposedTreeProblems) {
        guard let o = json.object, let id = o["id"]?.string, let component = o["component"]?.string, let props = o["props"]?.object,
              let children = o["children"]?.array else {
            throw ComposedTreeProblems(problems: [ComposedTreeProblem(path: path, message: ComposedTree.nodeShape)])
        }
        var nodes: [A2UINode] = []
        for (i, c) in children.enumerated() { nodes.append(try A2UINode(json: c, path: "\(path)/children/\(i)")) }
        self.init(id: id, component: component, props: props, children: nodes)
    }
}

/// A problem in a composed tree: a JSON pointer into it and one sentence, with the typed refusal when one applies.
/// Core's `TreeProblem`.
public struct ComposedTreeProblem: Sendable, Equatable, CustomStringConvertible {
    /// A JSON pointer into the tree, such as /children/0/props/label.
    public let path: String
    public let message: String
    /// For a person-only action given input: the refusal every agent door answers, as JSON.
    public let refusal: A2UIJSON?

    public init(path: String, message: String, refusal: A2UIJSON? = nil) {
        self.path = path
        self.message = message
        self.refusal = refusal
    }

    /// As core writes it, key for key.
    public var json: A2UIJSON {
        var o: A2UIObject = ["path": .string(path), "message": .string(message)]
        if let refusal { o["refusal"] = refusal }
        return .object(o)
    }

    public var description: String { json.serialized }
}

/// The problems a tree that doesn't validate has.
public struct ComposedTreeProblems: Error, Sendable, Equatable {
    public let problems: [ComposedTreeProblem]
}

/// A composed tree checked against an app's catalog, with the data model its fields start from. Build one from a tree
/// that didn't come through A2UI: your own code's, or an MCP tool result's `structuredContent.ouro`.
///
/// ```swift
/// let tree = try ComposedTree(ouro: result["structuredContent"]?["ouro"] ?? .null, catalog: catalog)
/// ComposedSurface(tree) { press in callTool(press.action, press.input) } onHandoff: { action, _ in open(action) }
/// ```
public struct ComposedTree: Sendable, Equatable {
    /// The composed tree's version, which `structuredContent.ouro.version` carries. Core's `COMPOSED_VERSION`.
    public static let version = "1"

    /// The tree's root.
    public let root: ComposedNode
    /// The data model the tree's fields start from and write to: a JSON object, addressed by JSON pointer.
    public let data: A2UIJSON

    /// A tree that passed ``validate(_:catalog:path:)``, and its data model. Throws ``ComposedTreeProblems`` with every
    /// problem when it doesn't pass, or when `data` isn't an object.
    public init(tree: A2UIJSON, data: A2UIJSON = .object(A2UIObject()), catalog: A2UICatalog) throws(ComposedTreeProblems) {
        var problems = Self.validate(tree, catalog: catalog)
        if !data.isObject { problems.append(ComposedTreeProblem(path: "", message: Self.dataShape)) }
        if !problems.isEmpty { throw ComposedTreeProblems(problems: problems) }
        root = try A2UINode(json: tree)
        self.data = data
    }

    /// The tree an MCP tool result carries in `structuredContent.ouro` (core's `mcpAppTreeResult`): `{ version,
    /// catalogId, tree, data }`, where `data` is optional. Throws ``ComposedTreeProblems`` when the version or the
    /// catalog isn't this one, or the tree doesn't validate against it; each problem's path points into `ouro`.
    public init(ouro: A2UIJSON, catalog: A2UICatalog) throws(ComposedTreeProblems) {
        var problems: [ComposedTreeProblem] = []
        guard let o = ouro.object else {
            throw ComposedTreeProblems(problems: [ComposedTreeProblem(path: "", message: "structuredContent.ouro is { version, catalogId, tree, data }.")])
        }
        if o["version"] != .string(Self.version) { problems.append(ComposedTreeProblem(path: "/version", message: "version is \"\(Self.version)\", got \(stringify(o["version"])).")) }
        if o["catalogId"] != .string(catalog.catalogID) { problems.append(ComposedTreeProblem(path: "/catalogId", message: "catalogId is \(catalog.catalogID), got \(stringify(o["catalogId"])).")) }
        let tree = o["tree"] ?? .null
        problems += Self.validate(tree, catalog: catalog, path: "/tree")
        let data = o["data"] ?? .object(A2UIObject())
        if !data.isObject { problems.append(ComposedTreeProblem(path: "/data", message: Self.dataShape)) }
        if !problems.isEmpty { throw ComposedTreeProblems(problems: problems) }
        root = try A2UINode(json: tree)
        self.data = data
    }

    /// A tree you resolved or built yourself and the data model beside it; nothing is checked.
    public init(root: ComposedNode, data: A2UIJSON = .object(A2UIObject())) {
        self.root = root
        self.data = data
    }

    static let nodeShape = "A node is { id, component, props, children }."
    static let dataShape = "data is an object: the data model the tree's fields read and write."
}

// MARK: The validator

private let buttonProps = ["action", "label", "consent", "press", "input", "confirm", "handoff", "emphasis", "@label"]

extension ComposedTree {
    /// Every problem in a composed tree against a catalog: each component is the catalog's, each prop is resolved and
    /// of its kind, and each ActionButton is exactly what the catalog says its action's button is, so no adapter and no
    /// sender can relabel a button or loosen its consent. Empty means it renders. Core's `validateTree`.
    public static func validate(_ tree: A2UIJSON, catalog cat: A2UICatalog, path: String = "") -> [ComposedTreeProblem] {
        var problems: [ComposedTreeProblem] = []
        func fail(_ at: String, _ message: String, refusal: A2UIJSON? = nil) { problems.append(ComposedTreeProblem(path: at, message: message, refusal: refusal)) }
        func visit(_ n: A2UIJSON, _ at: String) {
            guard let o = n.object, o["id"]?.string != nil, let name = o["component"]?.string, let props = o["props"]?.object,
                  let children = o["children"]?.array else {
                fail(at, nodeShape)
                return
            }
            guard let spec = cat.component(name) else {
                fail("\(at)/component", "\(stringify(o["component"])) is not in this catalog; use one of \(cat.components.map(\.0).joined(separator: ", ")).")
                return
            }
            let allowed = name == "ActionButton" ? buttonProps : spec.props.filter { $0.kind != .children }.map(\.name) + ["@label"]
            for key in props.keys where !allowed.contains(key) { fail("\(at)/props/\(key)", "\(name) has no \(key).") }
            if let l = props["@label"], l.string == nil { fail("\(at)/props/@label", "@label is text.") }
            for p in spec.props {
                if p.kind == .children || p.kind == .action || p.kind == .input { continue }
                guard let v = props[p.name] else {
                    if p.required { fail("\(at)/props/\(p.name)", "\(name) needs \(p.name): \(p.description)") }
                    continue
                }
                checkProp(p, v, "\(at)/props/\(p.name)", fail)
            }
            if name == "ActionButton" {
                let id = props["action"]?.string
                if let id, let a = cat.action(id) {
                    let input = props["input"]
                    if let given = input?.object {
                        if a.isPersonOnly, !given.isEmpty {
                            fail("\(at)/props/input", a.refusal?["summary"]?.string ?? "", refusal: a.refusal)
                        } else {
                            for (k, v) in given.pairs {
                                if let b = v.object, b["@path"] != nil, !(isBinding(v) && (b["@path"]?.string?.hasPrefix("/") ?? false)) {
                                    fail("\(at)/props/input/\(k)", "\(k) is a value, or {\"@path\": \"/...\"} bound to the data model.")
                                }
                            }
                            let expected = actionButtonProps(cat, action: id, prepared: given, label: nil)
                            for key in ["label", "consent", "press", "handoff"] where props[key]?.serialized != expected[key]?.serialized {
                                fail("\(at)/props/\(key)", "\(id)'s \(key) is the catalog's \((expected[key] ?? .null).serialized), never the sender's.")
                            }
                            if a.press == .confirm {
                                let c = props["confirm"]?.object
                                if c == nil || c?["title"] != .string(a.label) || c?["description"] != .string(a.description) || c?["fields"]?.array == nil {
                                    fail("\(at)/props/confirm", "\(id) confirms, with the catalog's title and description and a row per prepared input.")
                                }
                            } else if props["confirm"] != nil {
                                fail("\(at)/props/confirm", "\(id) doesn't confirm; only a consequential action does.")
                            }
                        }
                    } else {
                        fail("\(at)/props/input", "input is an object of field values.")
                    }
                } else {
                    fail("\(at)/props/action", "\(stringify(props["action"])) is not one of the app's actions: \(cat.actions.map(\.0).joined(separator: ", ")).")
                }
            }
            if !spec.props.contains(where: { $0.name == "children" }), !children.isEmpty { fail("\(at)/children", "\(name) has no children.") }
            for (i, c) in children.enumerated() { visit(c, "\(at)/children/\(i)") }
        }
        visit(tree, path)
        return problems
    }

    private static func checkProp(_ p: A2UIProp, _ v: A2UIJSON, _ at: String, _ fail: (String, String, A2UIJSON?) -> Void) {
        func bad(_ expected: String) { fail(at, "\(p.name) is \(expected), got \(v.serialized).", nil) }
        if p.isPath {
            if !(v.string?.hasPrefix("/") ?? false) { bad("a JSON pointer into the data model, such as /servings") }
            return
        }
        switch p.kind {
        case .string:
            if v.string == nil { bad("text") }
        case .strings:
            if !(v.array?.allSatisfy { $0.string != nil } ?? false) { bad("a list of text") }
        case .boolean:
            if case .bool = v {} else { bad("true or false") }
        case .enumeration(let values, _):
            if !(v.string.map(values.contains) ?? false) { bad("one of \(values.joined(separator: ", "))") }
        case .level:
            if !(v.number.map { $0 == 1 || $0 == 2 || $0 == 3 } ?? false) { bad("1, 2 or 3") }
        case .terms:
            let ok = v.array?.allSatisfy { it in
                guard let o = it.object else { return false }
                return o["term"]?.string != nil && o["detail"]?.string != nil && o.count == 2
            } ?? false
            if !ok { bad("a list of { term, detail } text") }
        case .children, .action, .input:
            break
        }
    }
}

// MARK: Buttons and presses

extension ComposedTree {
    /// A value bound to the data model: `{ "@path": "/servings" }`. In a tree, the path is absolute. Core's `isBinding`.
    public static func isBinding(_ v: A2UIJSON?) -> Bool {
        guard let o = v?.object, o.count == 1, o["@path"]?.string != nil else { return false }
        return true
    }

    /// The props of an ActionButton for an action and the input an agent prepared: everything else comes from the
    /// catalog. Core's `actionButtonProps`.
    static func actionButtonProps(_ cat: A2UICatalog, action: String, prepared: A2UIObject, label: A2UILabelResolver?) -> A2UIObject {
        let a = cat.action(action)!
        let input = a.isPersonOnly ? A2UIObject() : prepared
        var props: A2UIObject = ["action": .string(action), "label": .string(a.label), "consent": .string(a.consent), "press": .string(a.press.rawValue), "input": .object(input)]
        if a.press == .confirm {
            props["confirm"] = .object([
                "title": .string(a.label),
                "description": .string(a.description),
                "fields": .array(confirmFields(action: action, a, input: input, label: label)),
            ])
        }
        if let how = a.how { props["handoff"] = .string(how) }
        return props
    }

    /// The rows of a confirm sheet: each prepared input with the person's label. An id shows its name (the app's
    /// resolver, else the sibling `shownAs` names, else the value itself), with the id as `raw` when the name replaced
    /// it; a name field that stands in for an id has no row of its own. An input bound to a field the person fills in
    /// is a row with an empty value and `bind`, its path, which ``resolveButton(_:data:)`` fills when they press. Core's
    /// `confirmFields`.
    static func confirmFields(action: String, _ a: A2UICatalogAction, input: A2UIObject, label: A2UILabelResolver?) -> [A2UIJSON] {
        let names = Set(a.input.compactMap { f -> String? in
            guard input[f.name] != nil, let n = f.shownAs, a.field(n) != nil else { return nil }
            return n
        })
        return a.input.filter { input[$0.name] != nil && !names.contains($0.name) }.map { f in
            if isBinding(input[f.name]), let bind = input[f.name]?["@path"]?.string {
                return .object(["label": .string(f.label), "value": .string(""), "bind": .string(bind)])
            }
            let raw = A2UI.text(input[f.name])
            let sibling = f.shownAs.flatMap { input[$0]?.string }?.trimmingCharacters(in: .whitespacesAndNewlines)
            let prepared = (sibling?.isEmpty ?? true) ? nil : sibling
            let given = label?(A2UILabelContext(action: action, field: f.name, value: raw, input: input))
            let value = given ?? prepared ?? raw
            var row: A2UIObject = ["label": .string(f.label), "value": .string(value)]
            if value != raw { row["raw"] = .string(raw) }
            return .object(row)
        }
    }

    /// A button as it stands when the person presses it: each input bound to the data model (`{"@path"}`) replaced by
    /// what `data` holds there now (null when nothing), and each bound row of its confirm sheet showing that value. A
    /// renderer calls it with its current data before it shows the confirm sheet or presses. Core's `resolveButton`.
    public static func resolveButton(_ button: ComposedNode, data: A2UIJSON) -> ComposedNode {
        guard let given = button.props["input"]?.object, given.pairs.contains(where: { isBinding($0.1) }) else { return button }
        var input = A2UIObject()
        for (k, v) in given.pairs { input[k] = isBinding(v) ? (A2UI.get(data, v["@path"]?.string ?? "") ?? .null) : v }
        var props = button.props
        props["input"] = .object(input)
        if var confirm = props["confirm"]?.object, let rows = confirm["fields"]?.array {
            confirm["fields"] = .array(rows.map { row in
                guard let bind = row.object?["bind"]?.string else { return row }
                var o = A2UIObject()
                o["label"] = row["label"]
                o["value"] = .string(A2UI.text(A2UI.get(data, bind)))
                return .object(o)
            })
            props["confirm"] = .object(confirm)
        }
        return ComposedNode(id: button.id, component: button.component, props: props, children: button.children)
    }
}

/// What pressing a composed button asks the app to do: the action, the input the agent prepared, and that the person
/// pressed it. Core's `PersonPress`; a format's entry point wraps it in its own message.
public struct PersonPress: Sendable, Equatable {
    /// The action's id, which is also its MCP tool's name.
    public let action: String
    /// The input the agent prepared, by field name, with the person's answers in the fields bound to theirs.
    public let input: A2UIObject
    /// The action's consent class.
    public let consent: String
    /// The button's label, as the person read it.
    public let label: String
    /// The button's component id.
    public let sourceComponentId: String
    /// True for a consequential action the person confirmed.
    public let confirmed: Bool

    /// The press a button makes, or nil when it makes none: a person-only button hands the person to the app's own
    /// screen, and a consequential one asks only after the person confirms. An input bound to a field the person fills
    /// in is read from `data`, the data model as they left it (``ComposedTree/resolveButton(_:data:)``).
    public static func of(_ button: ComposedNode, confirmed: Bool = false, data: A2UIJSON) -> PersonPress? {
        of(ComposedTree.resolveButton(button, data: data), confirmed: confirmed)
    }

    /// The press a button makes as the tree has it, or nil when it makes none: a person-only button hands the person to
    /// the app's own screen, and a consequential one asks only after the person confirms. For a tree with fields, use
    /// ``of(_:confirmed:data:)``, so an input bound to one carries the person's answer.
    public static func of(_ button: ComposedNode, confirmed: Bool = false) -> PersonPress? {
        let press = button.text("press")
        if press == A2UIPress.handoff.rawValue { return nil }
        if press == A2UIPress.confirm.rawValue, !confirmed { return nil }
        return PersonPress(action: button.text("action"), input: button.props["input"]?.object ?? A2UIObject(), consent: button.text("consent"),
                           label: button.text("label"), sourceComponentId: button.id, confirmed: press == A2UIPress.confirm.rawValue)
    }
}
