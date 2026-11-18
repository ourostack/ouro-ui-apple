import Foundation

/// `^\d+$`: a JSON pointer token that indexes an array.
func isIndex(_ s: String) -> Bool { !s.isEmpty && s.unicodeScalars.allSatisfy { $0 >= "0" && $0 <= "9" } }

/// What an app's resolver is asked to name: one prepared input of a button that confirms.
public struct A2UILabelContext: Sendable {
    public let action: String
    public let field: String
    /// The prepared value, as text: the id.
    public let value: String
    /// Every prepared input of the button.
    public let input: A2UIObject
}

/// The app's own word for an id, from its own data, such as a recipe's title for `rcp_lemon_orzo`; nil leaves the field
/// to the agent's `shownAs` name, then to the id itself. Asked for each field a confirm sheet shows, and it wins over
/// what the agent prepared, since the agent's text is the one thing the person can't check.
public typealias A2UILabelResolver = @Sendable (A2UILabelContext) -> String?

/// A resolved node: the component, its props with every binding resolved and defaults filled, and its children. Its
/// ``json`` is core's reference tree, which the conformance cases check.
public struct A2UINode: Sendable, Equatable {
    /// The component id it came from (a template's id for each of its instances); the action message a button sends
    /// names it as `sourceComponentId`.
    public let id: String
    public let component: String
    public let props: A2UIObject
    public let children: [A2UINode]

    /// A node of the composed tree. Check a tree your own code built with ``ComposedTree/validate(_:catalog:path:)``
    /// (or build it with ``ComposedTree/init(tree:data:catalog:)``) before you draw it.
    public init(id: String, component: String, props: A2UIObject, children: [A2UINode] = []) {
        self.id = id
        self.component = component
        self.props = props
        self.children = children
    }

    public var json: A2UIJSON {
        .object(["id": .string(id), "component": .string(component), "props": .object(props), "children": .array(children.map(\.json))])
    }

    public func text(_ key: String) -> String { props[key]?.string ?? "" }
}

/// One surface's state: its catalog, its components by id and its data model.
public struct A2UISurfaceState: Sendable {
    public var catalogID: String
    var components = Ordered<A2UIObject>()
    public var data: A2UIJSON
}

extension A2UI {
    /// Reads a JSON pointer (RFC 6901). A missing value is nil.
    public static func get(_ data: A2UIJSON, _ pointer: String) -> A2UIJSON? {
        if pointer.isEmpty || pointer == "/" { return data }
        var cur: A2UIJSON? = data
        for raw in tokens(pointer) {
            switch cur {
            case .array(let a)?:
                cur = isIndex(raw) ? Int(raw).flatMap { $0 < a.count ? a[$0] : nil } : nil
            case .object(let o)?: cur = o[raw]
            default: return nil
            }
            if cur == nil { return nil }
        }
        return cur
    }

    /// Writes a JSON pointer, creating objects on the way; null deletes.
    public static func set(_ data: A2UIJSON, _ pointer: String, _ value: A2UIJSON) -> A2UIJSON {
        if pointer.isEmpty || pointer == "/" { return value == .null ? .object(A2UIObject()) : value }
        let root: A2UIJSON = (data.isObject || data.array != nil) ? data : .object(A2UIObject())
        return write(root, tokens(pointer)[...], value)
    }

    private static func tokens(_ pointer: String) -> [String] {
        let body = pointer.hasPrefix("/") ? String(pointer.dropFirst()) : pointer
        return body.split(separator: "/", omittingEmptySubsequences: false).map {
            $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        }
    }

    private static func write(_ node: A2UIJSON, _ keys: ArraySlice<String>, _ value: A2UIJSON) -> A2UIJSON {
        let k = keys.first!
        let last = keys.count == 1
        if case .array(var a) = node, isIndex(k), let i = Int(k) {
            if last {
                if value == .null { if i < a.count { a.remove(at: i) } }
                else {
                    while a.count <= i { a.append(.null) }
                    a[i] = value
                }
            } else {
                while a.count <= i { a.append(.null) }
                let next = a[i]
                a[i] = write((next.isObject || next.array != nil) ? next : .object(A2UIObject()), keys.dropFirst(), value)
            }
            return .array(a)
        }
        guard case .object(var o) = node else { return node }
        if last {
            o[k] = value == .null ? nil : value
        } else {
            let next = o[k]
            o[k] = write((next?.isObject ?? false) || next?.array != nil ? next! : .object(A2UIObject()), keys.dropFirst(), value)
        }
        return .object(o)
    }

    /// A2UI's type conversion to a string: numbers and booleans as written, null and missing as "", others as JSON.
    public static func text(_ v: A2UIJSON?) -> String {
        switch v {
        case nil, .null?: ""
        case .string(let s)?: s
        case .number(let n)?: A2UIJSON.numberText(n)
        case .bool(let b)?: b ? "true" : "false"
        case let other?: other.serialized
        }
    }

    /// Applies a stream to surfaces. Validate first: a stream the validator rejects applies only in part.
    static func apply(_ messages: [A2UIJSON], to surfaces: inout Ordered<A2UISurfaceState>) {
        for m in messages {
            if let b = m["createSurface"]?.object {
                var s = A2UISurfaceState(catalogID: text(b["catalogId"]), data: b["dataModel"] ?? .object(A2UIObject()))
                for c in b["components"]?.array ?? [] { if let o = c.object { s.components[text(o["id"])] = o } }
                surfaces[text(b["surfaceId"])] = s
            } else if let b = m["updateComponents"]?.object, var s = surfaces[text(b["surfaceId"])] {
                for c in b["components"]?.array ?? [] { if let o = c.object { s.components[text(o["id"])] = o } }
                surfaces[text(b["surfaceId"])] = s
            } else if let b = m["updateDataModel"]?.object, var s = surfaces[text(b["surfaceId"])] {
                s.data = set(s.data, b["path"]?.string ?? "/", b["value"] ?? .null)
                surfaces[text(b["surfaceId"])] = s
            } else if let b = m["deleteSurface"]?.object {
                surfaces[text(b["surfaceId"])] = nil
            }
        }
    }

    private static func scoped(_ scope: String, _ p: String) -> String {
        p.hasPrefix("/") ? p : p.isEmpty ? scope : "\(scope)/\(p)"
    }

    private static func value(_ data: A2UIJSON, _ scope: String, _ v: A2UIJSON?) -> A2UIJSON? {
        if isBinding(v), let p = v?["@path"]?.string { return get(data, scoped(scope, p)) }
        return v
    }

    /// One surface as every renderer must show it; nil when it has no root yet. `label` is the app's own word for an
    /// id (see ``A2UILabelContext``); it wins over the name the agent prepared.
    public static func resolve(_ surface: A2UISurfaceState, catalog cat: A2UICatalog, label: A2UILabelResolver? = nil) -> A2UINode? {
        guard let root = surface.components["root"] else { return nil }
        let data = surface.data
        func node(_ comp: A2UIObject, _ scope: String) -> A2UINode {
            let name = text(comp["component"])
            let spec = cat.component(name)!
            var props = A2UIObject()
            var children: [A2UINode] = []
            for p in spec.props {
                let raw = comp[p.name]
                if p.isPath {
                    props[p.name] = .string(isBinding(raw) ? absolute(scoped(scope, raw?["@path"]?.string ?? "")) : "")
                    continue
                }
                switch p.kind {
                case .string:
                    if raw != nil || p.required { props[p.name] = .string(text(value(data, scope, raw))) }
                case .strings:
                    props[p.name] = .array((value(data, scope, raw)?.array ?? []).map { .string(text($0)) })
                case .boolean(let d):
                    let v = raw == nil ? .bool(d) : value(data, scope, raw)
                    props[p.name] = .bool(v == .bool(true))
                case .enumeration(_, let d):
                    props[p.name] = .string(raw?.string ?? d)
                case .level(let d):
                    props[p.name] = .number(raw?.number ?? Double(d))
                case .terms:
                    let v = value(data, scope, raw)
                    let bound = isBinding(raw)
                    let base = bound ? scoped(scope, raw?["@path"]?.string ?? "") : scope
                    props[p.name] = .array((v?.array ?? []).enumerated().map { i, it in
                        let s = bound ? "\(base)/\(i)" : scope
                        return .object(["term": .string(text(value(data, s, it.object?["term"]))),
                                        "detail": .string(text(value(data, s, it.object?["detail"])))])
                    })
                case .children:
                    if let ids = raw?.array {
                        for id in ids { if let c = surface.components[text(id)] { children.append(node(c, scope)) } }
                    } else if let t = raw?.object {
                        let base = scoped(scope, text(t["path"]))
                        if let list = get(data, base)?.array, let tpl = surface.components[text(t["componentId"])] {
                            for i in list.indices { children.append(node(tpl, "\(base)/\(i)")) }
                        }
                    }
                case .action, .input:
                    break
                }
            }
            if name == "ActionButton" {
                // Bindings stay bindings here; once the tree is whole, live() reads those no field writes and adds the
                // catalog's props.
                let id = text(comp["action"])
                var input = A2UIObject()
                if !cat.action(id)!.isPersonOnly, let given = comp["input"]?.object {
                    for (k, v) in given.pairs {
                        input[k] = isBinding(v) ? .object(["@path": .string(absolute(scoped(scope, v["@path"]?.string ?? "")))]) : v
                    }
                }
                props["action"] = .string(id)
                props["input"] = .object(input)
            }
            if let label = comp["@accessibility"]?.object?["label"] { props["@label"] = .string(text(value(data, scope, label))) }
            return A2UINode(id: text(comp["id"]), component: name, props: props, children: children)
        }
        return live(cat, node(root, ""), data: data, label: label)
    }

    /// A pointer that starts at the data model's root.
    private static func absolute(_ p: String) -> String { p.hasPrefix("/") ? p : "/\(p)" }

    /// The tree with each button input bound to a path no field writes read from the data now, as before fields
    /// existed; one bound to a field the person fills in stays bound, so a press sends their answer
    /// (``ComposedTree/resolveButton(_:data:)``). Core's `live`.
    private static func live(_ cat: A2UICatalog, _ tree: A2UINode, data: A2UIJSON, label: A2UILabelResolver?) -> A2UINode {
        var written = Set<String>()
        func collect(_ n: A2UINode) {
            if inputComponents.contains(n.component), let path = n.props["value"]?.string { written.insert(path) }
            n.children.forEach(collect)
        }
        collect(tree)
        func fix(_ n: A2UINode) -> A2UINode {
            let children = n.children.map(fix)
            guard n.component == "ActionButton", let prepared = n.props["input"]?.object else {
                return A2UINode(id: n.id, component: n.component, props: n.props, children: children)
            }
            var rest = n.props
            rest["action"] = nil
            rest["input"] = nil
            rest["@label"] = nil
            // A value read from the data is a value: one shaped like a binding is sent as its text, never followed.
            func read(_ p: String) -> A2UIJSON {
                let v = get(data, p) ?? .null
                return isBinding(v) ? .string(text(v)) : v
            }
            var input = A2UIObject()
            for (k, v) in prepared.pairs {
                if isBinding(v), let p = v["@path"]?.string, !written.contains(p) { input[k] = read(p) } else { input[k] = v }
            }
            // The catalog's props, computed once per button, so the app's label resolver is asked once per field.
            var props = rest
            for (k, v) in ComposedTree.actionButtonProps(cat, action: text(n.props["action"]), prepared: input, label: label).pairs { props[k] = v }
            if let l = n.props["@label"] { props["@label"] = l }
            return A2UINode(id: n.id, component: n.component, props: props, children: children)
        }
        return fix(tree)
    }

    /// Every surface a stream leaves, resolved, or the validator's problems when it has any. Use
    /// ``resolveSurfaces(_:catalog:label:)`` for each surface's data model too, which its fields start from.
    public static func resolve(_ messages: A2UIJSON, catalog cat: A2UICatalog, label: A2UILabelResolver? = nil) -> Result<[(String, A2UINode?)], A2UIProblems> {
        resolveSurfaces(messages, catalog: cat, label: label).map { $0.map { ($0.id, $0.node) } }
    }

    /// Every surface a stream leaves, with its tree and its data model, or the validator's problems when it has any.
    public static func resolveSurfaces(_ messages: A2UIJSON, catalog cat: A2UICatalog, label: A2UILabelResolver? = nil) -> Result<[A2UIResolvedSurface], A2UIProblems> {
        let problems = validate(messages, catalog: cat)
        if !problems.isEmpty { return .failure(A2UIProblems(problems: problems)) }
        var surfaces = Ordered<A2UISurfaceState>()
        apply(messages.array ?? [], to: &surfaces)
        return .success(surfaces.pairs.map { A2UIResolvedSurface(id: $0.0, node: resolve($0.1, catalog: cat, label: label), data: $0.1.data) })
    }

    /// The A2UI `action` message a composed button sends when the person presses it (after confirming, for a
    /// consequential one). Nil for a person-only button, which sends none, and for a consequential one not confirmed.
    public static func actionMessage(surfaceId: String, button: A2UINode, timestamp: String, confirmed: Bool = false) -> A2UIJSON? {
        PersonPress.of(button, confirmed: confirmed).map { actionMessage(surfaceId: surfaceId, press: $0, timestamp: timestamp) }
    }

    /// A press wrapped in A2UI's `action` message: named after the action, the prepared input as its context, and in
    /// `metadata.extensions` the consent class and that the person pressed it.
    public static func actionMessage(surfaceId: String, press: PersonPress, timestamp: String) -> A2UIJSON {
        var ext: A2UIObject = ["consent": .string(press.consent), "by": .string("person")]
        if press.confirmed { ext["confirmed"] = .bool(true) }
        return .object([
            "version": .string(version),
            "action": .object([
                "name": .string(press.action),
                "surfaceId": .string(surfaceId),
                "sourceComponentId": .string(press.sourceComponentId),
                "timestamp": .string(timestamp),
                "userMessage": .string(press.label),
                "context": .object(press.input),
                "metadata": .object(["extensions": .object([actionExtensionKey: .object(ext)])]),
            ]),
        ])
    }
}

/// A surface a stream leaves: its id, its tree (nil until it has a root) and its data model, which the tree's fields
/// start from. Draw it with ``A2UISurface/init(_:now:onAction:onHandoff:)``.
public struct A2UIResolvedSurface: Sendable, Equatable {
    /// The surface's id, which each action message names.
    public let id: String
    /// The surface's tree; nil until it has a root.
    public let node: A2UINode?
    /// The surface's data model: `createSurface`'s `dataModel` with each `updateDataModel` applied.
    public let data: A2UIJSON
}

/// The problems a stream that doesn't validate has.
public struct A2UIProblems: Error, Sendable, Equatable {
    public let problems: [A2UIProblem]
}
