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
/// `value` and writes their answer there. The surface keeps the person's answers over the `data` you pass, and a button
/// bound to a field sends what the person entered, in the confirm sheet and in the press
/// (``ComposedTree/resolveButton(_:data:)``). When the data changes, as an agent's update changes it, what the person
/// entered stays, except where the new data changed that value or the list item it is in: there the agent's value wins.
///
/// ```swift
/// ComposedSurface(tree) { press in callTool(press.action, press.input) } onHandoff: { action, how in open(action) }
/// ```
///
/// For an MCP tool's results, pass each `structuredContent.ouro` in order with
/// ``init(results:catalog:onProblems:onPress:onHandoff:)``: a tree replaces what the surface shows, and an update
/// changes it (``ComposedTree/applying(ouro:catalog:)``).
public struct ComposedSurface: View {
    /// What the surface draws: a tree you hold, or what a list of MCP results leaves.
    enum Source {
        case tree(ComposedNode, data: A2UIJSON)
        case results([A2UIJSON], catalog: A2UICatalog, onProblems: (@MainActor (ComposedTreeProblems) -> Void)?)
    }

    let source: Source
    let onPress: @MainActor (PersonPress) -> Void
    let onHandoff: @MainActor (_ action: String, _ how: String) -> Void
    /// The person's answers, by pointer, in the order they gave them; drawn over `data`.
    @State private var answers = A2UIObject()

    /// - Parameters:
    ///   - node: the tree's root, from a format's resolver (``A2UI/resolveSurfaces(_:catalog:label:)`` for A2UI) or
    ///     from ``ComposedTree``.
    ///   - data: the data model the tree's fields start from: A2UI's `dataModel`, or MCP Apps'
    ///     `structuredContent.ouro.data`.
    ///   - onPress: a read or write button, or a consequential one the person confirmed.
    ///   - onHandoff: a person-only button: take the person to the action's own screen; `how` is the declaration's.
    public init(_ node: ComposedNode, data: A2UIJSON, onPress: @escaping @MainActor (PersonPress) -> Void,
                onHandoff: @escaping @MainActor (_ action: String, _ how: String) -> Void) {
        self.source = .tree(node, data: data)
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

    /// The tree an MCP tool's results leave, each a `structuredContent.ouro` in the order they came: a tree
    /// (`{ version, catalogId, tree, data }`) replaces what the surface shows, and an update (`{ version, catalogId,
    /// update }`) changes it. When the newest result has problems (a tree that fails the checks, or an update that
    /// doesn't apply), the surface shows a short alert in their place and `onProblems` gets them, for the agent to
    /// correct; the next update applies to the last tree that passed, and what the person entered there stays.
    ///
    /// ```swift
    /// ComposedSurface(results: results.map { $0["structuredContent"]?["ouro"] ?? .null }, catalog: catalog) { press in
    ///     callTool(press.action, press.input)
    /// } onHandoff: { action, _ in open(action) }
    /// ```
    public init(results: [A2UIJSON], catalog: A2UICatalog, onProblems: (@MainActor (ComposedTreeProblems) -> Void)? = nil,
                onPress: @escaping @MainActor (PersonPress) -> Void,
                onHandoff: @escaping @MainActor (_ action: String, _ how: String) -> Void) {
        self.source = .results(results, catalog: catalog, onProblems: onProblems)
        self.onPress = onPress
        self.onHandoff = onHandoff
    }

    /// What the surface shows: the last tree that passed and its data, and the newest result's problems, if it has any.
    var shown: (tree: ComposedTree?, problems: ComposedTreeProblems?) {
        switch source {
        case .tree(let node, let data): return (ComposedTree(root: node, data: data), nil)
        case .results(let results, let catalog, _): return Self.shown(results, catalog: catalog)
        }
    }

    /// What a list of `structuredContent.ouro` results leaves: the last tree that passed, with every update after it
    /// that applied, and the newest result's problems.
    static func shown(_ results: [A2UIJSON], catalog: A2UICatalog) -> (tree: ComposedTree?, problems: ComposedTreeProblems?) {
        var good: ComposedTree?
        var problems: ComposedTreeProblems?
        for result in results {
            do throws(ComposedTreeProblems) {
                if result["update"] != nil, result["tree"] == nil {
                    guard let tree = good else {
                        throw ComposedTreeProblems(problems: [ComposedTreeProblem(path: "/update", message: "An update changes a tree the view shows, and this view shows none yet; send the tree first.")])
                    }
                    good = try tree.applying(ouro: result, catalog: catalog)
                } else {
                    good = try ComposedTree(ouro: result, catalog: catalog)
                }
                problems = nil
            } catch {
                problems = error
            }
        }
        return (good, problems)
    }

    public var body: some View {
        let shown = shown
        let data = shown.tree?.data ?? .object(A2UIObject())
        Group {
            if shown.problems != nil {
                A2UIInvalidCard()
            } else if let tree = shown.tree {
                A2UINodeView(node: tree.root, context: A2UIPressContext(data: data, answers: $answers, onPress: onPress, onHandoff: onHandoff))
            }
        }
        .onChange(of: data) { old, new in answers = Self.kept(answers, from: old, to: new) }
        .onAppear { report(shown.problems) }
        .onChange(of: shown.problems) { _, problems in report(problems) }
    }

    private func report(_ problems: ComposedTreeProblems?) {
        if let problems, case .results(_, _, let onProblems?) = source { onProblems(problems) }
    }

    /// The person's answers that still stand when the data changes from `old` to `new`: every answer but those whose
    /// value, or a list item on the way to it, the change touched, where the new data wins. Web's `carry`
    /// (ourostack/ouro-ui#2115).
    static func kept(_ answers: A2UIObject, from old: A2UIJSON, to new: A2UIJSON) -> A2UIObject {
        var kept = A2UIObject()
        for (pointer, value) in answers.pairs where anchors(old, pointer).allSatisfy({ same(A2UI.get(old, $0), A2UI.get(new, $0)) }) {
            kept[pointer] = value
        }
        return kept
    }

    /// The pointers an answer at `pointer` depends on: the pointer itself and each list item on the way to it, since a
    /// list that loses an item moves the next one into its place. Web's `anchors`.
    static func anchors(_ data: A2UIJSON, _ pointer: String) -> [String] {
        let keys = pointer.unicodeScalars.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map { String(String.UnicodeScalarView($0)) }
        let prefixes = keys.indices.map { "/" + keys[...$0].joined(separator: "/") }
        // The data model is an object, so the first key is never a list item.
        return prefixes.indices.filter { $0 == prefixes.count - 1 || ($0 > 0 && A2UI.get(data, prefixes[$0 - 1])?.array != nil) }.map { prefixes[$0] }
    }
}

/// What the surface shows in place of a tree that fails the checks or an update that doesn't apply: web's short alert.
struct A2UIInvalidCard: View {
    static let title = "This card can't be shown"
    static let description = "It didn't pass the checks for composed UI."

    var body: some View {
        OuroBanner(Self.title, description: Self.description, tone: .destructive)
    }
}
