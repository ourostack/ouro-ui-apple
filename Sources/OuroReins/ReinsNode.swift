import Foundation

/// Something a person can do on a screen, offered to an agent: a stable name, a title and, when it takes one, an input.
///
/// An action only ever calls the view model's own entry point (the method a button calls), so an agent and a finger
/// take the same path.
public struct ReinsAction: Sendable {
    /// A stable, camel-case name an agent sends with `do`, such as `openRecipe` or `goBack`.
    public let name: String
    /// What the action does, in the person's words.
    public let title: String
    /// The input's schema, or nil when the action takes none.
    public let input: ReinsSchema?
    let perform: @MainActor @Sendable (ReinsValue?) async throws -> Void

    /// An action that takes no input.
    public init(_ name: String, _ title: String, perform: @escaping @MainActor @Sendable () async throws -> Void) {
        self.name = name
        self.title = title
        self.input = nil
        self.perform = { _ in try await perform() }
    }

    /// An action whose input decodes as `Input`; its schema comes from ``ReinsInput/reinsSchema``.
    public init<Input: ReinsInput>(
        _ name: String,
        _ title: String,
        input: Input.Type,
        perform: @escaping @MainActor @Sendable (Input) async throws -> Void
    ) {
        self.name = name
        self.title = title
        self.input = Input.reinsSchema
        self.perform = { value in try await perform(try (value ?? .object([:])).decode(as: Input.self)) }
    }
}

/// One level of what's on screen: a view model's name, its state as JSON, its actions, and the node it shows inside it.
///
/// A navigator (a tab bar, a push stack, a modal) is a node too. It *lends* actions such as `goBack` to whatever node is
/// focused beneath it, the way the back button belongs to the navigation bar and not to the page.
///
/// Three rules, from Shopify's Reflex: everything a person can see is in `state`; everything a person can do is in
/// `actions`; and actions call the same entry points the view does, never anything only an agent can reach.
public struct ReinsNode: Sendable {
    /// A stable screen name, such as `kitchen`, `recipe` or `cook`. Ouro Feel uses the focused node's name as the
    /// screen's identity.
    public var name: String
    public var state: ReinsValue
    public var actions: [ReinsAction]
    /// Actions this node offers to the focused node beneath it.
    public var lends: [ReinsAction]
    private var children: [ReinsNode]

    /// The node shown inside this one, or nil when this one is the deepest.
    public var child: ReinsNode? {
        get { children.first }
        set { children = newValue.map { [$0] } ?? [] }
    }

    public init(
        _ name: String,
        state: ReinsValue = .object([:]),
        actions: [ReinsAction] = [],
        lends: [ReinsAction] = [],
        child: ReinsNode? = nil
    ) {
        self.name = name
        self.state = state
        self.actions = actions
        self.lends = lends
        self.children = child.map { [$0] } ?? []
    }

    /// A node whose state is any `Encodable` value. A state that fails to encode shows as
    /// `{"x-ouro-reins-state-error": "..."}`, so the failure is visible in `ls` rather than hidden.
    public init(
        _ name: String,
        encoding state: some Encodable,
        actions: [ReinsAction] = [],
        lends: [ReinsAction] = [],
        child: ReinsNode? = nil
    ) {
        let value: ReinsValue
        do { value = try ReinsValue(encoding: state) } catch { value = ["x-ouro-reins-state-error": .string("\(error)")] }
        self.init(name, state: value, actions: actions, lends: lends, child: child)
    }

    /// The chain from this node down to the deepest one.
    public var path: [ReinsNode] {
        var chain = [self]
        while let next = chain.last?.child { chain.append(next) }
        return chain
    }
}

extension ReinsNode {
    /// A push stack. It lends `goBack` while it's deeper than its root; its state is `{depth}`.
    public static func stack(
        _ name: String = "stack",
        depth: Int,
        goBack: @escaping @MainActor @Sendable () async throws -> Void,
        child: ReinsNode
    ) -> ReinsNode {
        ReinsNode(
            name,
            state: ["depth": .number(Double(depth))],
            lends: depth > 0 ? [ReinsAction("goBack", "Go back a page", perform: goBack)] : [],
            child: child
        )
    }

    /// A tab bar. It always lends `selectTab {tab}`; its state is `{selected, tabs}`.
    public static func tabs(
        _ name: String = "tabs",
        selected: String,
        tabs: [String],
        select: @escaping @MainActor @Sendable (String) async throws -> Void,
        child: ReinsNode
    ) -> ReinsNode {
        ReinsNode(
            name,
            state: ["selected": .string(selected), "tabs": .array(tabs.map(ReinsValue.string))],
            lends: [
                ReinsAction("selectTab", "Switch to a tab", input: ReinsTabInput.self) { try await select($0.tab) }
                    .narrowed(.object(properties: ["tab": .oneOf(tabs)], required: ["tab"])),
            ],
            child: child
        )
    }
}

/// `selectTab`'s input.
public struct ReinsTabInput: ReinsInput {
    public let tab: String
}

extension ReinsAction {
    /// The same action with a narrower input schema: the values valid on this screen right now, such as `selectTab`
    /// limited to the tabs that exist or `openRecipe` limited to the recipes on screen. `ls` then shows an agent exactly
    /// what it may send, and anything else is refused before the action runs.
    public func narrowed(_ input: ReinsSchema) -> ReinsAction {
        ReinsAction(name: name, title: title, input: input, perform: perform)
    }

    private init(name: String, title: String, input: ReinsSchema?, perform: @escaping @MainActor @Sendable (ReinsValue?) async throws -> Void) {
        self.name = name
        self.title = title
        self.input = input
        self.perform = perform
    }
}

/// A view model, store or app root that can describe itself as a node.
@MainActor
public protocol ReinsDrivable: AnyObject {
    var reinsNode: ReinsNode { get }
}
