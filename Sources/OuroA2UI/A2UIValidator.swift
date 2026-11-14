import Foundation

/// A problem in A2UI's standard validation error format, plus the typed refusal when one applies.
public struct A2UIProblem: Sendable, Equatable, CustomStringConvertible {
    public let code: String
    public let surfaceId: String?
    public let functionCallId: String?
    /// A JSON pointer into the message stream, such as /2/updateComponents/components/0/text.
    public let path: String
    public let message: String
    public let refusal: A2UIJSON?

    init(_ code: String = "VALIDATION_FAILED", surfaceId: String? = nil, functionCallId: String? = nil, path: String, message: String, refusal: A2UIJSON? = nil) {
        self.code = code
        self.surfaceId = surfaceId
        self.functionCallId = functionCallId
        self.path = path
        self.message = message
        self.refusal = refusal
    }

    /// As core writes it, key for key.
    public var json: A2UIJSON {
        var o = A2UIObject()
        o["code"] = .string(code)
        if let surfaceId { o["surfaceId"] = .string(surfaceId) }
        if let functionCallId { o["functionCallId"] = .string(functionCallId) }
        o["path"] = .string(path)
        o["message"] = .string(message)
        if let refusal { o["refusal"] = refusal }
        return .object(o)
    }

    public var description: String { json.serialized }
}

private let messageKeys = ["createSurface", "updateComponents", "updateDataModel", "deleteSurface", "callRendererFunction", "agentFunctionResponse"]

/// JavaScript's `JSON.stringify(v)` for a value that may be missing.
func stringify(_ v: A2UIJSON?) -> String { v?.serialized ?? "undefined" }

/// A2UI's identifier rule (UAX #31): `^[\p{XID_Start}_][\p{XID_Continue}]*$`.
func isIdentifier(_ s: String) -> Bool {
    var scalars = s.unicodeScalars.makeIterator()
    guard let first = scalars.next(), first == "_" || first.properties.isXIDStart else { return false }
    while let u = scalars.next() { if !u.properties.isXIDContinue { return false } }
    return true
}

func isBinding(_ v: A2UIJSON?) -> Bool {
    guard let o = v?.object, o.count == 1, o["@path"]?.string != nil else { return false }
    return true
}

func isCall(_ v: A2UIJSON?) -> Bool { v?.object?["@call"] != nil }

extension A2UI {
    /// Why an agent can't press a button through the screen: the message for a `callRendererFunction`.
    public static func functionCallProblem(_ cat: A2UICatalog, name: A2UIJSON?) -> (message: String, refusal: A2UIJSON?) {
        let id = name?.string
        let a = id.flatMap { cat.action($0) }
        if let a, a.isPersonOnly, let refusal = a.refusal { return (refusal["summary"]?.string ?? "", refusal) }
        if a != nil, let id { return ("\(id) is an action, and agents run actions through their own tool (MCP \(id)), not through the person's screen.", nil) }
        return ("This catalog has no functions an agent may call\(id.map { ", so \($0) is not one" } ?? "").", nil)
    }

    /// Every problem in a stream of A2UI messages against a catalog: the envelope, each component and its props,
    /// every child id resolving, one root per surface, no cycles, and the action rules. Empty means it renders.
    public static func validate(_ messages: A2UIJSON, catalog cat: A2UICatalog) -> [A2UIProblem] {
        guard let list = messages.array else { return [A2UIProblem(path: "", message: "Send a list of A2UI messages.")] }
        var problems: [A2UIProblem] = []
        var surfaces = Ordered<Ordered<(comp: A2UIObject, path: String)>>()
        for (i, m) in list.enumerated() {
            let at = "/\(i)"
            guard let mo = m.object, mo["version"] == .string(version) else {
                problems.append(A2UIProblem(path: "\(at)/version", message: "Every message has \"version\": \"\(version)\"."))
                continue
            }
            let keys = mo.keys.filter { $0 != "version" }
            guard keys.count == 1, let key = keys.first, messageKeys.contains(key) else {
                problems.append(A2UIProblem(path: at, message: "A message has exactly one of \(messageKeys.joined(separator: ", "))."))
                continue
            }
            guard let body = mo[key]?.object else {
                problems.append(A2UIProblem(path: "\(at)/\(key)", message: "\(key) is an object."))
                continue
            }
            if key == "callRendererFunction" {
                let call = body["callFunction"]?.object?["@call"]
                let p = functionCallProblem(cat, name: call)
                problems.append(A2UIProblem("INVALID_FUNCTION_CALL", functionCallId: body["functionCallId"]?.string ?? "", path: "\(at)/callRendererFunction/callFunction", message: p.message, refusal: p.refusal))
                continue
            }
            if key == "agentFunctionResponse" {
                problems.append(A2UIProblem("INVALID_FUNCTION_CALL", path: "\(at)/agentFunctionResponse", message: "This catalog's renderers call no agent functions, so there is nothing to answer."))
                continue
            }
            guard let surfaceId = body["surfaceId"]?.string, !surfaceId.isEmpty else {
                problems.append(A2UIProblem(path: "\(at)/\(key)/surfaceId", message: "surfaceId is a non-empty string."))
                continue
            }
            var w = Walk(cat: cat, surfaceId: surfaceId)
            if key == "createSurface" {
                if surfaces[surfaceId] != nil { problems.append(A2UIProblem("INTEGRITY_ERROR", surfaceId: surfaceId, path: "\(at)/createSurface/surfaceId", message: "Surface \(surfaceId) already exists; delete it first or use another id.")) }
                if body["catalogId"] != .string(cat.catalogID) { problems.append(A2UIProblem(surfaceId: surfaceId, path: "\(at)/createSurface/catalogId", message: "catalogId is \(cat.catalogID).")) }
                if body["theme"] != nil { problems.append(A2UIProblem(surfaceId: surfaceId, path: "\(at)/createSurface/theme", message: "A2UI v1.0 has no theme; the app's HX theme styles the surface.")) }
                if let d = body["dataModel"], !d.isObject { problems.append(A2UIProblem(surfaceId: surfaceId, path: "\(at)/createSurface/dataModel", message: "dataModel is an object.")) }
                surfaces[surfaceId] = Ordered()
            } else if surfaces[surfaceId] == nil {
                problems.append(A2UIProblem(surfaceId: surfaceId, path: "\(at)/\(key)/surfaceId", message: "Create surface \(surfaceId) before \(key)."))
                continue
            }
            if key == "deleteSurface" {
                surfaces[surfaceId] = nil
                continue
            }
            if key == "updateDataModel" {
                if let path = body["path"], !(path.string.map { $0.isEmpty || $0.hasPrefix("/") } ?? false) {
                    problems.append(A2UIProblem(surfaceId: surfaceId, path: "\(at)/updateDataModel/path", message: "path is a JSON pointer starting with /."))
                }
                if body["value"] == nil { problems.append(A2UIProblem(surfaceId: surfaceId, path: "\(at)/updateDataModel/value", message: "updateDataModel needs value (null deletes).")) }
                continue
            }
            let comps = body["components"]
            if comps == nil, key == "createSurface" { continue }
            guard let comps = comps?.array else {
                problems.append(A2UIProblem(surfaceId: surfaceId, path: "\(at)/\(key)/components", message: "components is a list."))
                continue
            }
            var byId = surfaces[surfaceId]!
            for (j, c) in comps.enumerated() {
                let cpath = "\(at)/\(key)/components/\(j)"
                w.checkComponent(c, path: cpath)
                if let co = c.object, let id = co["id"]?.string { byId[id] = (co, cpath) }
            }
            surfaces[surfaceId] = byId
            problems += w.problems
            continue
        }
        // The tree each surface ends with: every child resolves, one root, no cycles.
        for (surfaceId, byId) in surfaces.pairs {
            if byId.pairs.isEmpty { continue }
            if byId["root"] == nil { problems.append(A2UIProblem(surfaceId: surfaceId, path: "", message: "One component must have id root; it is what the surface shows.")) }
            for (_, entry) in byId.pairs {
                for (child, at) in childRefs(entry.comp, path: entry.path) {
                    if byId[child] == nil { problems.append(A2UIProblem(surfaceId: surfaceId, path: at, message: "No component has id \(child).")) }
                    if child == "root" { problems.append(A2UIProblem(surfaceId: surfaceId, path: at, message: "root can't be a child.")) }
                }
            }
            var seen = Set<String>()
            func visit(_ id: String, _ stack: [String]) {
                if stack.contains(id) {
                    problems.append(A2UIProblem(surfaceId: surfaceId, path: byId[id]!.path, message: "The tree loops: \((stack + [id]).joined(separator: " > "))."))
                    return
                }
                guard !seen.contains(id), let entry = byId[id] else { return }
                for (child, _) in childRefs(entry.comp, path: "") { visit(child, stack + [id]) }
                seen.insert(id)
            }
            if byId["root"] != nil { visit("root", []) }
        }
        return problems
    }
}

func childRefs(_ comp: A2UIObject, path: String) -> [(String, String)] {
    let v = comp["children"]
    if let a = v?.array {
        return a.enumerated().compactMap { i, c in c.string.map { ($0, "\(path)/children/\(i)") } }
    }
    if let id = v?.object?["componentId"]?.string { return [(id, "\(path)/children/componentId")] }
    return []
}

/// A small insertion-ordered map: setting an existing key keeps its place, and removing then adding moves it to the
/// end, as JavaScript's `Map` does.
struct Ordered<Value> {
    private(set) var pairs: [(String, Value)] = []
    subscript(key: String) -> Value? {
        get { pairs.first(where: { $0.0 == key })?.1 }
        set {
            if let i = pairs.firstIndex(where: { $0.0 == key }) {
                if let newValue { pairs[i].1 = newValue } else { pairs.remove(at: i) }
            } else if let newValue {
                pairs.append((key, newValue))
            }
        }
    }
}

private struct Walk {
    let cat: A2UICatalog
    let surfaceId: String
    var problems: [A2UIProblem] = []

    init(cat: A2UICatalog, surfaceId: String) {
        self.cat = cat
        self.surfaceId = surfaceId
    }

    mutating func fail(_ path: String, _ message: String, refusal: A2UIJSON? = nil) {
        problems.append(A2UIProblem(surfaceId: surfaceId, path: path, message: message, refusal: refusal))
    }

    enum Dynamic: String { case string, strings, boolean, value }

    mutating func checkDynamic(_ v: A2UIJSON?, _ kind: Dynamic, _ path: String) {
        if isCall(v) {
            fail(path, "This catalog has no functions; bind to the data model with {\"@path\"} or give the value.")
            return
        }
        if isBinding(v) { return }
        let ok: Bool
        switch kind {
        case .string: ok = v?.string != nil
        case .boolean: if case .bool = v { ok = true } else { ok = false }
        case .strings: ok = v?.array?.allSatisfy { $0.string != nil } ?? false
        case .value: ok = v != nil && !(v?.object?.keys.contains { $0.hasPrefix("@") } ?? false)
        }
        if !ok {
            let what = kind == .strings ? "a list of strings" : kind == .value ? "a value" : "a \(kind.rawValue)"
            fail(path, "Expected \(what) or {\"@path\"}, got \(stringify(v)).")
        }
    }

    mutating func checkInput(_ action: A2UICatalogAction, id: String, input: A2UIJSON?, path: String) {
        if action.isPersonOnly {
            if let input, !(input.object?.isEmpty ?? false) {
                fail(path, action.refusal?["summary"]?.string ?? "", refusal: action.refusal)
            }
            return
        }
        if let input, !input.isObject {
            fail(path, "input is an object of field values.")
            return
        }
        let given = input?.object ?? A2UIObject()
        for (name, v) in given.pairs {
            let at = "\(path)/\(name)"
            guard let f = action.field(name) else {
                let names = action.input.map(\.name).joined(separator: ", ")
                fail(at, "\(id) has no input \(name); its fields are \(names.isEmpty ? "none" : names).")
                continue
            }
            if isCall(v) { checkDynamic(v, .value, at) }
            if isBinding(v) || isCall(v) { continue }
            let ok: Bool
            switch f.kind {
            case "string": ok = v.string != nil
            case "boolean": if case .bool = v { ok = true } else { ok = false }
            case "enum": ok = v.string.map { f.values.contains($0) } ?? false
            default: ok = v.number.map { f.kind == "number" || $0.rounded() == $0 } ?? false
            }
            if !ok {
                let what = f.kind == "enum" ? "one of \(f.values.joined(separator: ", "))" : f.kind == "integer" ? "an integer" : "a \(f.kind)"
                fail(at, "\(f.label) is \(what), got \(stringify(v)).")
            }
        }
        for f in action.input where !f.optional && given[f.name] == nil {
            fail(path, "\(id) needs \(f.name) (\(f.label)) prepared before the person can press it.")
        }
    }

    mutating func checkComponent(_ c: A2UIJSON, path: String) {
        guard let comp = c.object else {
            fail(path, "A component is an object with id and component.")
            return
        }
        let id = comp["id"]
        if !(id?.string.map(isIdentifier) ?? false) {
            fail("\(path)/id", "id \(stringify(id)) is not an identifier: letters, digits and _, not starting with a digit (user_card, not user-card).")
        }
        let component = comp["component"]
        guard let name = component?.string, let spec = cat.component(name) else {
            fail("\(path)/component", "\(stringify(component)) is not in this catalog; use one of \(cat.components.map(\.0).joined(separator: ", ")).")
            return
        }
        if let cid = comp["@catalogId"], cid != .string(cat.catalogID) { fail("\(path)/@catalogId", "This renderer has only the catalog \(cat.catalogID).") }
        let propNames = spec.props.map(\.name)
        for key in comp.keys where !["id", "component", "@catalogId", "@metadata", "@accessibility"].contains(key) {
            if !propNames.contains(key) { fail("\(path)/\(key)", "\(name) has no \(key)\(propNames.isEmpty ? "" : "; its props are \(propNames.joined(separator: ", "))").") }
        }
        if let a11y = comp["@accessibility"]?.object {
            for (k, v) in a11y.pairs {
                if k == "label" || k == "description" { checkDynamic(v, .string, "\(path)/@accessibility/\(k)") }
                else if k == "hidden" { checkDynamic(v, .boolean, "\(path)/@accessibility/\(k)") }
            }
        }
        for prop in spec.props {
            let at = "\(path)/\(prop.name)"
            guard let v = comp[prop.name] else {
                if prop.required { fail(at, "\(name) needs \(prop.name): \(prop.description)") }
                continue
            }
            switch prop.kind {
            case .string: checkDynamic(v, .string, at)
            case .strings: checkDynamic(v, .strings, at)
            case .boolean: checkDynamic(v, .boolean, at)
            case .enumeration(let values, _):
                if !(v.string.map(values.contains) ?? false) { fail(at, "\(prop.name) is one of \(values.joined(separator: ", ")), got \(stringify(v)).") }
            case .level:
                if !(v.number.map { $0 == 1 || $0 == 2 || $0 == 3 } ?? false) { fail(at, "level is 1, 2 or 3, got \(stringify(v)).") }
            case .children:
                if let a = v.array {
                    for (i, c) in a.enumerated() where c.string == nil { fail("\(at)/\(i)", "A child is a component id.") }
                } else if let o = v.object, o["componentId"]?.string != nil, o["path"]?.string != nil, o.count == 2 {
                    // a template
                } else {
                    fail(at, "children is a list of component ids, or a template { componentId, path }.")
                }
            case .terms:
                if isBinding(v) { break }
                guard let a = v.array else {
                    fail(at, "items is a list of { term, detail }, or {\"@path\"} to one.")
                    break
                }
                for (i, it) in a.enumerated() {
                    guard let o = it.object, !o.keys.contains(where: { $0 != "term" && $0 != "detail" }) else {
                        fail("\(at)/\(i)", "Each item is { term, detail }.")
                        continue
                    }
                    for k in ["term", "detail"] {
                        if o[k] == nil { fail("\(at)/\(i)/\(k)", "Each item needs \(k).") } else { checkDynamic(o[k], .string, "\(at)/\(i)/\(k)") }
                    }
                }
            case .action:
                if !(v.string.map { cat.action($0) != nil } ?? false) {
                    fail(at, "\(stringify(v)) is not one of the app's actions: \(cat.actions.map(\.0).joined(separator: ", ")).")
                }
            case .input:
                break
            }
        }
        if name == "ActionButton", let aid = comp["action"]?.string, let a = cat.action(aid) {
            checkInput(a, id: aid, input: comp["input"], path: "\(path)/input")
        }
    }
}

extension Ordered: Sendable where Value: Sendable {}
