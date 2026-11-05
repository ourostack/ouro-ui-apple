import Foundation

/// Behavior tests over a session, in any test framework: wait for a screen, act, wait for the state you expect.
///
/// Each step polls (every 5 ms, up to `timeout`) rather than sleeping, and a failure says what it waited for and prints
/// the last screen it saw, so a red test reads like a bug report.
///
/// ```swift
/// let journey = ReinsJourney(session)
/// try await journey.expect("kitchen")
/// try await journey.do("openRecipe", ["id": "r1"], until: { $0.focus == "recipe" })
/// ```
@MainActor
public struct ReinsJourney {
    public let session: ReinsSession
    public let timeout: Duration

    public init(_ session: ReinsSession, timeout: Duration = .seconds(2)) {
        self.session = session
        self.timeout = timeout
    }

    /// Waits until the focus is `focus` and `until` holds.
    @discardableResult
    public func expect(_ focus: String, describing what: String = "", until condition: (ReinsScreen) -> Bool = { _ in true }) async throws -> ReinsScreen {
        try await poll("focus \(focus)\(what.isEmpty ? "" : ", \(what)")") { $0.focus == focus && condition($0) }
    }

    /// Runs `action` and waits until `until` holds. A refusal or failure throws at once, with the problem.
    @discardableResult
    public func `do`(_ action: String, _ input: ReinsValue? = nil, describing what: String = "", until condition: (ReinsScreen) -> Bool = { _ in true }) async throws -> ReinsScreen {
        let reply = await session.perform(action, input: input)
        guard reply.ok else {
            throw ReinsJourneyFailure(waitedFor: "do \(action) to run", problem: reply.error?.message, lastScreen: reply.screen, transcript: session.transcript)
        }
        if condition(reply.screen) { return reply.screen }
        return try await poll("after do \(action): \(what.isEmpty ? "the expected state" : what)", condition)
    }

    private func poll(_ waitedFor: String, _ condition: (ReinsScreen) -> Bool) async throws -> ReinsScreen {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var screen = session.ls()
        while !condition(screen) {
            guard clock.now < deadline else {
                throw ReinsJourneyFailure(waitedFor: waitedFor, problem: nil, lastScreen: screen, transcript: session.transcript)
            }
            try await Task.sleep(for: .milliseconds(5))
            screen = session.ls()
        }
        return screen
    }
}

/// A journey step that didn't happen: what it waited for, the problem if an action was refused, and the last screen.
public struct ReinsJourneyFailure: Error, CustomStringConvertible {
    public let waitedFor: String
    public let problem: String?
    public let lastScreen: ReinsScreen
    /// The session's `do` lines up to the failure; replay them to reproduce it.
    public let transcript: [String]

    public var description: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let screen = (try? encoder.encode(lastScreen)).map { String(decoding: $0, as: UTF8.self) } ?? "\(lastScreen)"
        return "Waited for \(waitedFor)." + (problem.map { " \($0)" } ?? "") + "\nLast screen:\n\(screen)"
            + "\nReplay:\n" + transcript.joined(separator: "\n")
    }
}
