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
        problems += Self.envelopeProblems(o, catalog: catalog)
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

/// JavaScript's `===` on JSON values, as core compares them: two strings are the same only when their UTF-16 code units
/// are, where Swift's `==` also takes "é" and "e\u{301}" as one. Missing is the same only as missing.
func same(_ a: A2UIJSON?, _ b: A2UIJSON?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case let (a?, b?): a.serialized.utf16.elementsEqual(b.serialized.utf16)
    default: false
    }
}

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
                                // A field the catalog doesn't carry would be sent without a row on the confirm sheet.
                                if a.field(k) == nil {
                                    let names = a.input.map(\.name).joined(separator: ", ")
                                    fail("\(at)/props/input/\(k)", "\(id) has no input \(k); its fields are \(names.isEmpty ? "none" : names).")
                                }
                                if let b = v.object, b["@path"] != nil, !(isBinding(v) && (b["@path"]?.string.map(A2UI.isDataPointer) ?? false)) {
                                    fail("\(at)/props/input/\(k)", "\(k) is a value, or {\"@path\": \"/...\"} bound to the data model.")
                                }
                            }
                            let expected = actionButtonProps(cat, action: id, prepared: given, label: nil)
                            for key in ["label", "consent", "press", "handoff"] where !same(props[key], expected[key]) {
                                fail("\(at)/props/\(key)", "\(id)'s \(key) is the catalog's \((expected[key] ?? .null).serialized), never the sender's.")
                            }
                            if a.press == .confirm {
                                let c = props["confirm"]?.object
                                if c == nil || !same(c?["title"], .string(a.label)) || !same(c?["description"], .string(a.description)) || c?["fields"]?.array == nil {
                                    fail("\(at)/props/confirm", "\(id) confirms, with the catalog's title and description and a row per prepared input.")
                                } else if let rows = c?["fields"]?.array {
                                    confirmRowProblems(id, a, input: given, rows: rows, at: "\(at)/props/confirm/fields", fail)
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
            if !(v.string.map(A2UI.isDataPointer) ?? false) { bad("a JSON pointer into the data model, such as /servings") }
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
        confirmKeys(a, input: input).compactMap(a.field).map { f in
            if isBinding(input[f.name]), let bind = input[f.name]?["@path"]?.string {
                return .object(["label": .string(f.label), "value": .string(""), "bind": .string(bind)])
            }
            let raw = A2UI.text(input[f.name])
            let sibling = f.shownAs.flatMap { input[$0]?.string }?.trimmingCharacters(in: .whitespacesAndNewlines)
            let prepared = (sibling?.isEmpty ?? true) ? nil : sibling
            // Only an id field (one with shownAs) shows a name; every other row shows exactly what will be sent.
            let named = f.shownAs == nil ? nil : label?(A2UILabelContext(action: action, field: f.name, value: raw, input: input)) ?? prepared
            let value = named ?? raw
            var row: A2UIObject = ["label": .string(f.label), "value": .string(value)]
            if !value.utf16.elementsEqual(raw.utf16) { row["raw"] = .string(raw) }
            return .object(row)
        }
    }

    /// The input fields a confirm sheet has a row for, in the catalog's order: each prepared one, less a name that
    /// stands in for an id. Core's `confirmKeys`.
    static func confirmKeys(_ a: A2UICatalogAction, input: A2UIObject) -> [String] {
        let names = Set(a.input.compactMap { f -> String? in
            guard input[f.name] != nil, let n = f.shownAs, a.field(n) != nil else { return nil }
            return n
        })
        return a.input.map(\.name).filter { input[$0] != nil && !names.contains($0) }
    }

    /// A confirm sheet's rows against the rows the catalog gives for the prepared input: the same fields, in order,
    /// with the catalog's labels, and each row showing what will be sent (its `raw`, or its `value` when it has none)
    /// or, for a bound input, the same binding. Only the words shown for an id may differ, since the app's own resolver
    /// names it. Core's `confirmRowProblems`.
    static func confirmRowProblems(_ id: String, _ a: A2UICatalogAction, input: A2UIObject, rows: [A2UIJSON], at: String,
                                   _ fail: (String, String, A2UIJSON?) -> Void) {
        let expected = confirmFields(action: id, a, input: input, label: nil)
        let keys = confirmKeys(a, input: input)
        func bad() { fail(at, "\(id)'s confirm sheet shows a row for each prepared input, with its label and the value that will be sent; the catalog's rows are \(A2UIJSON.array(expected).serialized).", nil) }
        guard rows.count == expected.count else { return bad() }
        for (i, row) in rows.enumerated() {
            let want = expected[i]
            guard let o = row.object, same(o["label"], want["label"]) else {
                bad()
                continue
            }
            if let bind = want["bind"] {
                if !same(o["bind"], bind) || o["raw"] != nil { bad() }
            } else if o["bind"] != nil || o["value"]?.string == nil {
                bad()
            } else if a.field(keys[i])?.shownAs != nil {
                // An id field may show a name, with the id beside it.
                let shown = (o["raw"] == nil || o["raw"] == .null) ? o["value"] : o["raw"]
                if !same(shown, want["raw"] ?? want["value"]) { bad() }
            } else if !same(o["value"], want["value"]) || o["raw"] != nil {
                bad()
            }
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

// MARK: Updating a tree a renderer already draws

extension ComposedTree {
    /// Every problem in an update that needs no tree: its shape, each node against the catalog (``validate(_:catalog:path:)``,
    /// at `/nodes/<i>`) and each data path, which is absolute and never names an object's prototype
    /// (``A2UI/isDataPointer(_:)``). An update is `{ nodes?, data? }`: each node replaces the tree's one node with its id,
    /// and each `{ path, value }` sets the data model at a JSON pointer, null deleting it. Core's `treeUpdateProblems`.
    public static func treeUpdateProblems(_ update: A2UIJSON, catalog cat: A2UICatalog) -> [ComposedTreeProblem] {
        let shape = "An update is { nodes?, data? }: nodes replace the tree's nodes by id, and data sets values by JSON pointer."
        guard let o = update.object else { return [ComposedTreeProblem(path: "", message: shape)] }
        if let at = nonJSON(update, "") {
            return [ComposedTreeProblem(path: at, message: "An update is JSON: text, finite numbers, true, false, null, lists and objects.")]
        }
        var problems: [ComposedTreeProblem] = []
        for key in o.keys where key != "nodes" && key != "data" {
            problems.append(ComposedTreeProblem(path: "/\(key)", message: "An update has no \(key). \(shape)"))
        }
        if let nodes = o["nodes"] {
            if let list = nodes.array {
                for (i, n) in list.enumerated() { problems += validate(n, catalog: cat, path: "/nodes/\(i)") }
            } else {
                problems.append(ComposedTreeProblem(path: "/nodes", message: "nodes is a list of nodes, each replacing the tree's node with its id."))
            }
        }
        if let data = o["data"] {
            if let list = data.array {
                for (i, d) in list.enumerated() {
                    if let e = d.object, e["value"] != nil, !e.keys.contains(where: { $0 != "path" && $0 != "value" }) {
                        if !(e["path"]?.string.map(A2UI.isDataPointer) ?? false) {
                            problems.append(ComposedTreeProblem(path: "/data/\(i)/path", message: "path is a JSON pointer into the data model, such as /servings, and never names __proto__, constructor or prototype."))
                        }
                    } else {
                        problems.append(ComposedTreeProblem(path: "/data/\(i)", message: "A data entry is { path, value }: value is JSON, and null deletes."))
                    }
                }
            } else {
                problems.append(ComposedTreeProblem(path: "/data", message: "data is a list of { path, value }, each setting the data model at a JSON pointer."))
            }
        }
        return problems
    }

    /// Where a value first stops being JSON: a number that isn't finite, which JavaScript would write as null.
    private static func nonJSON(_ v: A2UIJSON, _ at: String) -> String? {
        switch v {
        case .number(let n): return n.isFinite ? nil : at
        case .array(let a):
            for (i, x) in a.enumerated() { if let found = nonJSON(x, "\(at)/\(i)") { return found } }
        case .object(let o):
            for (k, x) in o.pairs {
                let key = k.replacingOccurrences(of: "~", with: "~0", options: .literal).replacingOccurrences(of: "/", with: "~1", options: .literal)
                if let found = nonJSON(x, "\(at)/\(key)") { return found }
            }
        default: break
        }
        return nil
    }

    /// Why setting `pointer` in `data` would not give JSON: a list is written only at an index from 0 to its length.
    private static func listIndexProblem(_ data: A2UIJSON, _ pointer: String) -> String? {
        var cur: A2UIJSON? = data
        for k in A2UI.segments(pointer) {
            if let list = cur?.array {
                guard isIndex(k), let i = Int(k), i <= list.count else {
                    return "\(pointer) names \(A2UIJSON.string(k).serialized) in a list of \(list.count); in a list, a segment is an index from 0 to \(list.count)."
                }
                cur = i < list.count ? list[i] : nil
            } else if let o = cur?.object {
                cur = o[k]
            } else {
                return nil
            }
        }
        return nil
    }

    /// How many nodes have `id`, compared by code unit as JavaScript's `===` does.
    private static func count(_ id: String, in n: ComposedNode) -> Int {
        (n.id.utf16.elementsEqual(id.utf16) ? 1 : 0) + n.children.reduce(0) { $0 + count(id, in: $1) }
    }

    private static func replacing(_ n: ComposedNode, with by: ComposedNode) -> ComposedNode {
        n.id.utf16.elementsEqual(by.id.utf16) ? by : ComposedNode(id: n.id, component: n.component, props: n.props, children: n.children.map { replacing($0, with: by) })
    }

    /// A tree and its data model after an update, or every problem and no change: never a tree partly updated. Core's
    /// `applyTreeUpdate`, with `data` nil where core's is undefined.
    static func applyTreeUpdate(_ update: A2UIJSON, to tree: ComposedNode, data: A2UIJSON?, catalog cat: A2UICatalog)
        -> Result<(tree: ComposedNode, data: A2UIJSON?), ComposedTreeProblems> {
        let shape = treeUpdateProblems(update, catalog: cat)
        if !shape.isEmpty { return .failure(ComposedTreeProblems(problems: shape)) }
        let given = validate(tree.json, catalog: cat)
        if !given.isEmpty { return .failure(ComposedTreeProblems(problems: given)) }
        var problems: [ComposedTreeProblem] = []
        var next = tree
        for (i, json) in (update["nodes"]?.array ?? []).enumerated() {
            guard let n = try? ComposedNode(json: json) else { continue }
            let found = count(n.id, in: next)
            if found == 0 {
                problems.append(ComposedTreeProblem(path: "/nodes/\(i)/id", message: "\(A2UIJSON.string(n.id).serialized) is not in the tree; replace a node it has, or the node that should hold this one."))
            } else if found > 1 {
                problems.append(ComposedTreeProblem(path: "/nodes/\(i)/id", message: "\(A2UIJSON.string(n.id).serialized) names \(found) nodes, a template's instances; replace the node that holds them, by its own id."))
            } else {
                next = replacing(next, with: n)
            }
        }
        var model = data
        for (i, d) in (update["data"]?.array ?? []).enumerated() {
            let base = model ?? .object(A2UIObject())
            let path = d["path"]?.string ?? ""
            if let index = listIndexProblem(base, path) {
                problems.append(ComposedTreeProblem(path: "/data/\(i)/path", message: index))
                continue
            }
            let written = A2UI.set(base, path, d["value"] ?? .null)
            guard written.isObject else {
                problems.append(ComposedTreeProblem(path: "/data/\(i)/value", message: "The data model is an object; set / only to an object."))
                continue
            }
            model = written
        }
        if !problems.isEmpty { return .failure(ComposedTreeProblems(problems: problems)) }
        let invalid = validate(next.json, catalog: cat)
        return invalid.isEmpty ? .success((next, model)) : .failure(ComposedTreeProblems(problems: invalid))
    }

    /// This tree and its data model after an agent's update, `{ nodes?, data? }`: each node replaces the tree's one node
    /// with its id, children and all, and each `{ path, value }` sets the data model at a JSON pointer, null deleting it,
    /// as A2UI's `updateComponents` and `updateDataModel` do. Throws every problem and changes nothing when an id names no
    /// node or several (a template's instances), a path is unsafe, a list index is out of range, or the tree it would give
    /// fails ``validate(_:catalog:path:)``, so an update can't relabel a button any more than a whole tree can. Core's
    /// `applyTreeUpdate` (ouro-ui-core docs/decisions/2026-11-18-composed-tree-updates.md).
    public func applying(_ update: A2UIJSON, catalog: A2UICatalog) throws(ComposedTreeProblems) -> ComposedTree {
        switch Self.applyTreeUpdate(update, to: root, data: data, catalog: catalog) {
        case .success(let next): return ComposedTree(root: next.tree, data: next.data ?? .object(A2UIObject()))
        case .failure(let problems): throw problems
        }
    }

    /// This tree after the update an MCP tool result carries in `structuredContent.ouro` (core's
    /// `mcpAppTreeUpdateResult`): `{ version, catalogId, update }`. Throws ``ComposedTreeProblems`` when the version or
    /// the catalog isn't this one or the update doesn't apply; each problem's path points into `ouro`.
    public func applying(ouro: A2UIJSON, catalog: A2UICatalog) throws(ComposedTreeProblems) -> ComposedTree {
        guard let o = ouro.object else {
            throw ComposedTreeProblems(problems: [ComposedTreeProblem(path: "", message: "structuredContent.ouro is { version, catalogId, update }.")])
        }
        var problems = Self.envelopeProblems(o, catalog: catalog)
        guard problems.isEmpty else { throw ComposedTreeProblems(problems: problems) }
        switch Self.applyTreeUpdate(o["update"] ?? .null, to: root, data: data, catalog: catalog) {
        case .success(let next): return ComposedTree(root: next.tree, data: next.data ?? .object(A2UIObject()))
        case .failure(let failed):
            problems = failed.problems.map { ComposedTreeProblem(path: "/update\($0.path)", message: $0.message, refusal: $0.refusal) }
            throw ComposedTreeProblems(problems: problems)
        }
    }

    /// The problems with `structuredContent.ouro`'s version and catalog.
    static func envelopeProblems(_ o: A2UIObject, catalog: A2UICatalog) -> [ComposedTreeProblem] {
        var problems: [ComposedTreeProblem] = []
        if o["version"] != .string(version) { problems.append(ComposedTreeProblem(path: "/version", message: "version is \"\(version)\", got \(stringify(o["version"])).")) }
        if o["catalogId"] != .string(catalog.catalogID) { problems.append(ComposedTreeProblem(path: "/catalogId", message: "catalogId is \(catalog.catalogID), got \(stringify(o["catalogId"])).")) }
        return problems
    }
}
