public import OuroHX
public import SwiftUI

// Ouro's composed tree drawn with Ouro HX, whatever format it arrived in. A format's entry point (``A2UISurface`` for
// A2UI) resolves its input into this tree and wraps a press in its own message; nothing in this file knows a format.
// Decision: ouro-ui-core docs/decisions/2026-11-14-composed-ui-own-tree.md.

/// Ouro's composed tree drawn with Ouro HX. Every button is one of the app's declared actions and pressing it follows
/// its consent class: read and write press at once, consequential opens a sheet built from the declaration and presses
/// only when the person confirms, and person-only hands the person to the app's own screen and never presses.
///
/// A field the person fills in (`TextField`, `Checkbox`, `Select`) starts with what the data model holds at its
/// `value` and writes their answer there. The surface keeps the data model, and a button bound to a field sends what
/// the person entered, in the confirm sheet and in the press (``ComposedTree/resolveButton(_:data:)``). When the
/// `data` you pass changes, the surface starts again from it.
///
/// ```swift
/// ComposedSurface(tree) { press in callTool(press.action, press.input) } onHandoff: { action, how in open(action) }
/// ```
public struct ComposedSurface: View {
    let node: ComposedNode
    let data: A2UIJSON
    let onPress: @MainActor (PersonPress) -> Void
    let onHandoff: @MainActor (_ action: String, _ how: String) -> Void
    /// The data model as the person's answers leave it.
    @State private var answers: A2UIJSON

    /// - Parameters:
    ///   - node: the tree's root, from a format's resolver (``A2UI/resolveSurfaces(_:catalog:label:)`` for A2UI) or
    ///     from ``ComposedTree``.
    ///   - data: the data model the tree's fields start from: A2UI's `dataModel`, or MCP Apps'
    ///     `structuredContent.ouro.data`.
    ///   - onPress: a read or write button, or a consequential one the person confirmed.
    ///   - onHandoff: a person-only button: take the person to the action's own screen; `how` is the declaration's.
    public init(_ node: ComposedNode, data: A2UIJSON, onPress: @escaping @MainActor (PersonPress) -> Void,
                onHandoff: @escaping @MainActor (_ action: String, _ how: String) -> Void) {
        self.node = node
        self.data = data
        self._answers = State(initialValue: data)
        self.onPress = onPress
        self.onHandoff = onHandoff
    }

    /// A tree with no fields, or whose fields start empty: its data model is `{}`.
    public init(_ node: ComposedNode, onPress: @escaping @MainActor (PersonPress) -> Void,
                onHandoff: @escaping @MainActor (_ action: String, _ how: String) -> Void) {
        self.init(node, data: .object(A2UIObject()), onPress: onPress, onHandoff: onHandoff)
    }

    /// A tree checked against the app's catalog (``ComposedTree``), with its data model.
    public init(_ tree: ComposedTree, onPress: @escaping @MainActor (PersonPress) -> Void,
                onHandoff: @escaping @MainActor (_ action: String, _ how: String) -> Void) {
        self.init(tree.root, data: tree.data, onPress: onPress, onHandoff: onHandoff)
    }

    public var body: some View {
        A2UINodeView(node: node, context: A2UIPressContext(data: $answers, onPress: onPress, onHandoff: onHandoff))
            .onChange(of: data) { answers = data }
    }
}
