import Foundation
public import OuroAX

/// What an agent sees with `ls`: the focused screen, its state, and every action it can take there.
public struct ReinsScreen: Codable, Sendable, Hashable {
    /// The focused (deepest) node's name.
    public var focus: String
    /// Node names from the root to the focus, such as `["app", "tabs", "stack", "recipe"]`.
    public var path: [String]
    /// The focused node's state.
    public var state: ReinsValue
    /// The state of each node above the focus, by name: where a navigator says which tab is selected or how deep its
    /// stack is.
    public var context: [String: ReinsValue]
    /// What the agent can do here: the focused node's own actions, then those lent by its ancestors, nearest first.
    public var actions: [ReinsActionInfo]

    /// The names of ``actions``.
    public var actionNames: [String] { actions.map(\.name) }
}

/// An action as `ls` prints it.
public struct ReinsActionInfo: Codable, Sendable, Hashable {
    public var name: String
    public var title: String
    /// The input's JSON Schema, or absent when the action takes none.
    public var input: ReinsValue?
    /// The node that offers it: the focus itself, or the ancestor that lends it.
    public var from: String
}

/// The answer to `do`: whether it ran, the problem if it didn't, and the screen afterwards.
public struct ReinsReply: Codable, Sendable, Hashable {
    public var ok: Bool
    /// Why the action was refused or failed, in Ouro AX's problem shape: `{code, exit, thing, problem, fix, message}`.
    public var error: OuroAX.Problem?
    /// The screen after the action, or the unchanged screen when it was refused, so the valid actions are always there.
    public var screen: ReinsScreen
}

/// Drives one app's node tree: `ls` reads the focused screen, `perform` runs an action on it.
///
/// The tree is rebuilt from the root on every call, so `ls` always shows current state; nothing is cached between calls.
@MainActor
public final class ReinsSession {
    private let root: @MainActor () -> ReinsNode
    private let settle: @MainActor () async -> Void

    /// Every `do` this session ran, as request lines (`do openRecipe {"id":"r1"}`), refused ones included. Replaying them
    /// on a fresh session over the same fixtures reproduces the run: a failing journey prints it as its bug report.
    public private(set) var transcript: [String] = []

    /// - Parameters:
    ///   - root: Builds the tree from the app's root.
    ///   - settle: Awaited after every action, before the reply reads the screen: the place to wait for work the action
    ///     started (a store's sync task, a debounce). The default yields once.
    public init(root: @escaping @MainActor () -> ReinsNode, settle: @escaping @MainActor () async -> Void = { await Task.yield() }) {
        self.root = root
        self.settle = settle
    }

    public convenience init(_ drivable: some ReinsDrivable, settle: @escaping @MainActor () async -> Void = { await Task.yield() }) {
        self.init(root: { drivable.reinsNode }, settle: settle)
    }

    /// The focused screen.
    public func ls() -> ReinsScreen {
        Self.screen(of: root())
    }

    /// Runs `action` on the focused screen. An action the screen doesn't offer, a missing or malformed input, or input
    /// sent to an action that takes none is refused before anything runs, and the reply lists what is available.
    public func perform(_ action: String, input: ReinsValue? = nil) async -> ReinsReply {
        transcript.append(input.map { "do \(action) \($0.json)" } ?? "do \(action)")
        let tree = root()
        let before = Self.screen(of: tree)
        guard let found = Self.available(in: tree).first(where: { $0.action.name == action }) else {
            return ReinsReply(ok: false, error: ReinsProblem.unavailable(action, on: before), screen: before)
        }
        let target = found.action
        switch (target.input, input) {
        case (nil, .some(let value)) where value != .null && value != .object([:]):
            return ReinsReply(ok: false, error: ReinsProblem.unexpectedInput(action, value: value), screen: before)
        case (.some(let schema), let value):
            let problems = schema.problems(in: value ?? .object([:]))
            if !problems.isEmpty {
                return ReinsReply(ok: false, error: ReinsProblem.invalidInput(action, problems: problems, schema: schema), screen: before)
            }
        default:
            break
        }
        do {
            try await target.perform(input)
        } catch {
            await settle()
            return ReinsReply(ok: false, error: ReinsProblem.failed(action, error: error), screen: ls())
        }
        await settle()
        return ReinsReply(ok: true, error: nil, screen: ls())
    }

    /// The focus's own actions, then each ancestor's lent actions, nearest first. A name already offered nearer the
    /// focus hides the same name further up.
    static func available(in tree: ReinsNode) -> [(action: ReinsAction, from: String)] {
        let path = tree.path
        guard let focus = path.last else { return [] }
        let labels = labels(for: path)
        var seen = Set<String>()
        var result: [(ReinsAction, String)] = []
        for action in focus.actions where seen.insert(action.name).inserted { result.append((action, labels.last!)) }
        for (ancestor, label) in zip(path.dropLast(), labels.dropLast()).reversed() {
            for action in ancestor.lends where seen.insert(action.name).inserted { result.append((action, label)) }
        }
        return result
    }

    /// Each node's name along the path, made unique: the second `stack` from the root is `stack.2`, so nested
    /// navigators don't overwrite each other in `context` and `from` says which one lends an action.
    static func labels(for path: [ReinsNode]) -> [String] {
        var counts: [String: Int] = [:]
        return path.map { node in
            counts[node.name, default: 0] += 1
            let count = counts[node.name]!
            return count == 1 ? node.name : "\(node.name).\(count)"
        }
    }

    static func screen(of tree: ReinsNode) -> ReinsScreen {
        let path = tree.path
        let focus = path.last!
        let labels = labels(for: path)
        var context: [String: ReinsValue] = [:]
        for (node, label) in zip(path.dropLast(), labels.dropLast()) { context[label] = node.state }
        return ReinsScreen(
            focus: labels.last ?? focus.name,
            path: labels,
            state: focus.state,
            context: context,
            actions: available(in: tree).map { ReinsActionInfo(name: $0.action.name, title: $0.action.title, input: $0.action.input?.json, from: $0.from) }
        )
    }
}

/// The problems Reins refuses with. Codes are stable slugs an agent can branch on.
public enum ReinsProblem {
    public static func unavailable(_ action: String, on screen: ReinsScreen) -> OuroAX.Problem {
        OuroAX.Problem(
            code: "action-unavailable",
            exit: 2,
            thing: "do \(action)",
            problem: "\(action) isn't available on \(screen.focus)",
            fix: screen.actionNames.isEmpty ? "nothing can be done on \(screen.focus); run ls" : "use one of: \(screen.actionNames.joined(separator: ", "))"
        )
    }

    static func unexpectedInput(_ action: String, value: ReinsValue) -> OuroAX.Problem {
        OuroAX.Problem(code: "input-unexpected", exit: 2, thing: "do \(action)", problem: "\(action) takes no input, got \(value.json)", fix: "send `do \(action)` with no input")
    }

    static func invalidInput(_ action: String, problems: [String], schema: ReinsSchema) -> OuroAX.Problem {
        OuroAX.Problem(
            code: "input-invalid",
            exit: 2,
            thing: "do \(action)",
            problem: problems.joined(separator: "; "),
            fix: "send input matching \(schema.json.json)"
        )
    }

    static func failed(_ action: String, error: any Error) -> OuroAX.Problem {
        if let problem = error as? OuroAX.Problem { return problem }
        return OuroAX.Problem(code: "action-failed", exit: 1, thing: "do \(action)", problem: "\(action) threw \(error)", fix: nil)
    }

    static func badRequest(_ problem: String) -> OuroAX.Problem {
        OuroAX.Problem(
            code: "bad-request",
            exit: 2,
            thing: "request",
            problem: problem,
            fix: #"send `ls`, `do <action> [json]`, or {"op":"ls"} / {"op":"do","action":"<name>","input":{...}}"#
        )
    }
}
