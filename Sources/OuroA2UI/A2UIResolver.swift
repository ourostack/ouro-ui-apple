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

    /// The rows of a confirm sheet: each prepared input with the person's label. An id shows its name (the app's
    /// resolver, else the sibling `shownAs` names, else the value itself), with the id as `raw` when the name replaced
    /// it; a name field that stands in for an id has no row of its own. Core's `confirmFields`.
    static func confirmFields(action: String, _ a: A2UICatalogAction, input: A2UIObject, label: A2UILabelResolver?) -> [A2UIJSON] {
        let names = Set(a.input.compactMap { f -> String? in
            guard input[f.name] != nil, let n = f.shownAs, a.field(n) != nil else { return nil }
            return n
        })
        return a.input.filter { input[$0.name] != nil && !names.contains($0.name) }.map { f in
            let raw = text(input[f.name])
            let sibling = f.shownAs.flatMap { input[$0]?.string }?.trimmingCharacters(in: .whitespacesAndNewlines)
            let prepared = (sibling?.isEmpty ?? true) ? nil : sibling
            let given = label?(A2UILabelContext(action: action, field: f.name, value: raw, input: input))
            let value = given ?? prepared ?? raw
            var row: A2UIObject = ["label": .string(f.label), "value": .string(value)]
            if value != raw { row["raw"] = .string(raw) }
            return .object(row)
        }
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
                let id = text(comp["action"])
                let a = cat.action(id)!
                var input = A2UIObject()
                if !a.isPersonOnly, let given = comp["input"]?.object {
                    for (k, v) in given.pairs { input[k] = value(data, scope, v) ?? .null }
                }
                props["action"] = .string(id)
                props["label"] = .string(a.label)
                props["consent"] = .string(a.consent)
                props["press"] = .string(a.press.rawValue)
                props["input"] = .object(input)
                if a.press == .confirm {
                    props["confirm"] = .object([
                        "title": .string(a.label),
                        "description": .string(a.description),
                        "fields": .array(confirmFields(action: id, a, input: input, label: label)),
                    ])
                }
                if let how = a.how { props["handoff"] = .string(how) }
            }
            if let label = comp["@accessibility"]?.object?["label"] { props["@label"] = .string(text(value(data, scope, label))) }
            return A2UINode(id: text(comp["id"]), component: name, props: props, children: children)
        }
        return node(root, "")
    }

    /// Every surface a stream leaves, resolved, or the validator's problems when it has any.
    public static func resolve(_ messages: A2UIJSON, catalog cat: A2UICatalog, label: A2UILabelResolver? = nil) -> Result<[(String, A2UINode?)], A2UIProblems> {
        let problems = validate(messages, catalog: cat)
        if !problems.isEmpty { return .failure(A2UIProblems(problems: problems)) }
        var surfaces = Ordered<A2UISurfaceState>()
        apply(messages.array ?? [], to: &surfaces)
        return .success(surfaces.pairs.map { ($0.0, resolve($0.1, catalog: cat, label: label)) })
    }

    /// The A2UI `action` message a composed button sends when the person presses it (after confirming, for a
    /// consequential one). Nil for a person-only button, which sends none, and for a consequential one not confirmed.
    public static func actionMessage(surfaceId: String, button: A2UINode, timestamp: String, confirmed: Bool = false) -> A2UIJSON? {
        let press = button.text("press")
        if press == A2UIPress.handoff.rawValue { return nil }
        if press == A2UIPress.confirm.rawValue, !confirmed { return nil }
        var ext: A2UIObject = ["consent": .string(button.text("consent")), "by": .string("person")]
        if press == A2UIPress.confirm.rawValue { ext["confirmed"] = .bool(true) }
        return .object([
            "version": .string(version),
            "action": .object([
                "name": .string(button.text("action")),
                "surfaceId": .string(surfaceId),
                "sourceComponentId": .string(button.id),
                "timestamp": .string(timestamp),
                "userMessage": .string(button.text("label")),
                "context": button.props["input"] ?? .object(A2UIObject()),
                "metadata": .object(["extensions": .object([actionExtensionKey: .object(ext)])]),
            ]),
        ])
    }
}

/// The problems a stream that doesn't validate has.
public struct A2UIProblems: Error, Sendable, Equatable {
    public let problems: [A2UIProblem]
}
