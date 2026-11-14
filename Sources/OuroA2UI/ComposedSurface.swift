public import OuroHX
public import SwiftUI

// Ouro's composed tree drawn with Ouro HX, whatever format it arrived in: core's composed.mts, ported. A format's entry
// point (``A2UISurface`` for A2UI) resolves its input into this tree and wraps a press in its own message; nothing in
// this file knows a format. Decision: ouro-ui-core docs/decisions/2026-11-14-composed-ui-own-tree.md.

/// A node of Ouro's composed tree: the component, its props resolved, and its children. Core's `ComposedNode`.
public typealias ComposedNode = A2UINode

/// What pressing a composed button asks the app to do: the action, the input the agent prepared, and that the person
/// pressed it. Core's `PersonPress`; a format's entry point wraps it in its own message.
public struct PersonPress: Sendable, Equatable {
    /// The action's id, which is also its MCP tool's name.
    public let action: String
    /// The input the agent prepared, by field name.
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
    /// screen, and a consequential one asks only after the person confirms.
    public static func of(_ button: ComposedNode, confirmed: Bool = false) -> PersonPress? {
        let press = button.text("press")
        if press == A2UIPress.handoff.rawValue { return nil }
        if press == A2UIPress.confirm.rawValue, !confirmed { return nil }
        return PersonPress(action: button.text("action"), input: button.props["input"]?.object ?? A2UIObject(), consent: button.text("consent"),
                           label: button.text("label"), sourceComponentId: button.id, confirmed: press == A2UIPress.confirm.rawValue)
    }
}

/// Ouro's composed tree drawn with Ouro HX. Every button is one of the app's declared actions and pressing it follows
/// its consent class: read and write press at once, consequential opens a sheet built from the declaration and presses
/// only when the person confirms, and person-only hands the person to the app's own screen and never presses.
///
/// ```swift
/// ComposedSurface(tree) { press in callTool(press.action, press.input) } onHandoff: { action, how in open(action) }
/// ```
public struct ComposedSurface: View {
    let node: ComposedNode
    let onPress: @MainActor (PersonPress) -> Void
    let onHandoff: @MainActor (_ action: String, _ how: String) -> Void

    /// - Parameters:
    ///   - node: the tree's root, from a format's resolver (``A2UI/resolve(_:catalog:label:)-(A2UIJSON,_,_)`` for A2UI).
    ///   - onPress: a read or write button, or a consequential one the person confirmed.
    ///   - onHandoff: a person-only button: take the person to the action's own screen; `how` is the declaration's.
    public init(_ node: ComposedNode, onPress: @escaping @MainActor (PersonPress) -> Void,
                onHandoff: @escaping @MainActor (_ action: String, _ how: String) -> Void) {
        self.node = node
        self.onPress = onPress
        self.onHandoff = onHandoff
    }

    public var body: some View {
        A2UINodeView(node: node, context: A2UIPressContext(onPress: onPress, onHandoff: onHandoff))
    }
}
