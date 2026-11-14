import Foundation

/// Ouro HX as an A2UI v1.0 catalog, ported from core's `src/a2ui.mts` (ouro-ui-core v0.7.1). Core's conformance cases,
/// vendored in `Tests/OuroA2UITests/Conformance`, prove this port gives the same trees and the same problems.
public enum A2UI {
    /// A2UI's protocol version these catalogs target.
    public static let version = "1.0"
    /// Ouro HX's catalog id; an app's catalog, with its actions, takes its own.
    public static let hxCatalogID = "https://ui.ouroboros.bot/a2ui/v1/catalog.json"
    /// The catalog-scope extension key that carries what each action's button does.
    public static let extensionKey = "bot_ouroboros_hx"
    /// The action-egress extension key on every A2UI `action` a composed button sends.
    public static let actionExtensionKey = "bot_ouroboros_action"
}

/// A prop's kind: what the validator checks and what the resolver produces.
public enum A2UIPropKind: Sendable, Equatable {
    case string, strings, children, terms, action, input
    case enumeration(values: [String], default: String)
    case boolean(default: Bool)
    case level(default: Int)
}

public struct A2UIProp: Sendable {
    public let name: String
    public let description: String
    public let required: Bool
    public let kind: A2UIPropKind
}

public struct A2UIComponentSpec: Sendable {
    public let description: String
    /// In core's order, which is the order a resolved node's props are written in.
    public let props: [A2UIProp]
}

private func p(_ name: String, _ description: String, required: Bool = false, _ kind: A2UIPropKind) -> A2UIProp {
    A2UIProp(name: name, description: description, required: required, kind: kind)
}

private let tones = ["neutral", "info", "success", "warning", "danger"]

extension A2UI {
    /// Ouro HX's catalog components, named as on web, in core's order.
    public static let components: [(String, A2UIComponentSpec)] = [
        ("Card", A2UIComponentSpec(description: "A raised surface that groups one thing's content; its children stack vertically.", props: [
            p("children", "What the card holds, top to bottom.", required: true, .children),
        ])),
        ("Stack", A2UIComponentSpec(description: "Lays children out in a column or a row with HX spacing.", props: [
            p("children", "What the stack holds, in order.", required: true, .children),
            p("direction", "vertical stacks top to bottom; horizontal lays out a row that wraps.", .enumeration(values: ["vertical", "horizontal"], default: "vertical")),
            p("gap", "Space between children, from HX's spacing scale.", .enumeration(values: ["none", "small", "medium", "large"], default: "medium")),
        ])),
        ("Heading", A2UIComponentSpec(description: "A title. Level 1 is a card's or page's title, 2 a section, 3 a subsection.", props: [
            p("text", "The heading's words.", required: true, .string),
            p("level", "1, 2 or 3.", .level(default: 2)),
        ])),
        ("Text", A2UIComponentSpec(description: "A paragraph of plain text.", props: [
            p("text", "The words, plain text without Markdown.", required: true, .string),
            p("tone", "muted for secondary text such as a byline or a note.", .enumeration(values: ["default", "muted"], default: "default")),
        ])),
        ("Image", A2UIComponentSpec(description: "A picture with a description for people who can't see it.", props: [
            p("url", "The image's https URL.", required: true, .string),
            p("description", "What the picture shows, for a screen reader; never \"image of\".", required: true, .string),
            p("aspect", "The frame's shape; the picture fills it.", .enumeration(values: ["landscape", "square", "portrait", "wide"], default: "landscape")),
        ])),
        ("Badge", A2UIComponentSpec(description: "A short label for a status or a category, such as \"Vegetarian\".", props: [
            p("text", "One to three words.", required: true, .string),
            p("tone", "neutral unless the label is a status.", .enumeration(values: tones, default: "neutral")),
        ])),
        ("List", A2UIComponentSpec(description: "A list of short plain-text items, such as ingredients or steps.", props: [
            p("items", "The items, in order.", required: true, .strings),
            p("ordered", "true numbers the items, for steps that happen in order.", .boolean(default: false)),
        ])),
        ("DescriptionList", A2UIComponentSpec(description: "Pairs of a term and its detail, such as \"Time\" and \"25 min\".", props: [
            p("items", "The pairs, each { term, detail }.", required: true, .terms),
        ])),
        ("Separator", A2UIComponentSpec(description: "A hairline between groups of content.", props: [])),
        ("Alert", A2UIComponentSpec(description: "A message the person should notice: a warning, an error, a success or information.", props: [
            p("title", "One line saying what happened.", required: true, .string),
            p("text", "What to do about it, if anything.", .string),
            p("tone", "How serious it is.", .enumeration(values: ["info", "success", "warning", "danger"], default: "info")),
        ])),
    ]

    public static let actionButton = A2UIComponentSpec(
        description: "A button for one of the app's declared actions. Its label and what pressing it does come from the action, so you choose only the action, the input you prepared and its emphasis.",
        props: [
            p("action", "The action's id.", required: true, .action),
            p("input", "The input you prepared, by field name; values may bind to the data model. Never give input to a person-only action.", .input),
            p("emphasis", "primary for the one main action on a surface; secondary for the rest.", .enumeration(values: ["primary", "secondary"], default: "secondary")),
        ])
}

/// What pressing an action's button does: run it, confirm then run it, or hand the person to the app's own screen.
public enum A2UIPress: String, Sendable { case run, confirm, handoff }

/// An action as the catalog carries it.
public struct A2UICatalogAction: Sendable {
    public struct Field: Sendable {
        public let name: String
        public let label: String
        public let kind: String
        public let optional: Bool
        public let values: [String]
    }

    public let consent: String
    public let press: A2UIPress
    public let label: String
    public let description: String
    /// In the catalog's order.
    public let input: [Field]
    /// For a person-only action: where the person does it.
    public let how: String?
    /// For a person-only action: the typed refusal every agent door answers, as JSON.
    public let refusal: A2UIJSON?

    public var isPersonOnly: Bool { how != nil }
    func field(_ name: String) -> Field? { input.first { $0.name == name } }
}

public struct A2UICatalogError: Error, Sendable, CustomStringConvertible {
    public let description: String
}

/// A catalog core's `ouro-a2ui-catalog.mts` wrote. Its component specs are HX's, so a hand-edited catalog can't widen them.
public struct A2UICatalog: Sendable {
    public let catalogID: String
    /// In the catalog's order.
    public let components: [(String, A2UIComponentSpec)]
    /// In the catalog's order.
    public let actions: [(String, A2UICatalogAction)]

    public init(json: A2UIJSON) throws {
        guard let id = json["catalogId"]?.string, let comps = json["components"]?.object else {
            throw A2UICatalogError(description: "not an A2UI catalog: it has no catalogId or components. Fix: pass a catalog ouro-a2ui wrote.")
        }
        catalogID = id
        components = try comps.keys.map { name in
            let spec = name == "ActionButton" ? A2UI.actionButton : A2UI.components.first(where: { $0.0 == name })?.1
            guard let spec else { throw A2UICatalogError(description: "catalog \(id): component \(name) is not Ouro HX's. Fix: regenerate it with ouro-a2ui catalog.") }
            return (name, spec)
        }
        let raw = json["metadata"]?["extensions"]?[A2UI.extensionKey]?["actions"]?.object ?? A2UIObject()
        actions = raw.pairs.map { id, a in
            let fields = (a["input"]?.object?.pairs ?? []).map { name, f in
                A2UICatalogAction.Field(name: name, label: f["label"]?.string ?? name, kind: f["kind"]?.string ?? "string",
                                        optional: f["optional"] == .bool(true), values: f["values"]?.array?.compactMap(\.string) ?? [])
            }
            return (id, A2UICatalogAction(
                consent: a["consent"]?.string ?? "read",
                press: A2UIPress(rawValue: a["press"]?.string ?? "run") ?? .run,
                label: a["label"]?.string ?? id,
                description: a["description"]?.string ?? "",
                input: fields,
                how: a["personOnly"]?["how"]?.string,
                refusal: a["personOnly"]?["refusal"]))
        }
    }

    public init(data: Data) throws { try self.init(json: A2UIJSON.parse(data)) }

    public func component(_ name: String) -> A2UIComponentSpec? { components.first { $0.0 == name }?.1 }
    public func action(_ id: String) -> A2UICatalogAction? { actions.first { $0.0 == id }?.1 }
}
