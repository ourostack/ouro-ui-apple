public import Foundation
#if canImport(FoundationNetworking)
public import FoundationNetworking
#endif
import OuroAX
import Synchronization

/// Zero network in a behavior session: every URL load in the process fails at once, and every attempt is recorded, so a
/// test fails on an attempt even when the app caught the error and carried on.
///
/// ```swift
/// let guardrail = ReinsNetworkGuard.begin()
/// defer { guardrail.end() }
/// // … drive the session …
/// try guardrail.check()   // throws `network-attempted`, listing each request
/// ```
///
/// What it covers, each proven in `ReinsNetworkAndSocketTests`:
/// - `URLSession.shared`, through a `URLProtocol` registered for the whole process;
/// - every session made from `URLSessionConfiguration.default` or `.ephemeral` while the guard is active: registering
///   a protocol doesn't reach those, so the guard also adds its protocol to the configurations those two return (the
///   approach OHHTTPStubs takes, swapping the two getters once per process);
/// - every session made from a configuration ``ReinsNetworkGuard/blocking(_:)`` returned, guard or no guard.
///
/// What it doesn't: a session made before the guard began from a plain configuration, background sessions,
/// Network.framework, raw sockets and WebKit (its loads run in another process). An app adopting Reins injects its
/// transports (the fixtures-through-constructors rule), so a behavior session never builds one of those.
///
/// One guard is active at a time in a process; ``begin()`` waits for the previous one to end, so tests that use it can
/// run in parallel without seeing each other's attempts.
public final class ReinsNetworkGuard: Sendable {
    /// A blocked request.
    public struct Attempt: Sendable, Hashable, Codable, CustomStringConvertible {
        public var method: String
        public var url: String
        public var description: String { "\(method) \(url)" }
    }

    private struct State {
        var active: ObjectIdentifier?
        var attempts: [Attempt] = []
    }

    private static let state = Mutex(State())
    private static let gate = Mutex<[CheckedContinuation<Void, Never>]>([])

    /// Starts blocking. Pair it with ``end()``.
    public static func begin() -> ReinsNetworkGuard {
        let guardrail = ReinsNetworkGuard()
        while !state.withLock({ state in
            guard state.active == nil else { return false }
            state.active = ObjectIdentifier(guardrail)
            state.attempts = []
            return true
        }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
        URLProtocol.registerClass(ReinsBlockingURLProtocol.self)
        _ = configurationGettersSwapped
        return guardrail
    }

    /// Runs `body` with the network blocked, then throws `network-attempted` if anything tried to load. `body` runs on
    /// the caller's actor, so a `@MainActor` test can drive its view models inside it.
    public static func withNetworkBlocked<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async throws -> T {
        let guardrail = begin()
        let result: T
        do {
            result = try await body()
        } catch {
            guardrail.end()
            throw error
        }
        let attempts = guardrail.end()
        if !attempts.isEmpty { throw problem(attempts) }
        return result
    }

    /// The attempts so far.
    public var attempts: [Attempt] {
        Self.state.withLock { $0.active == ObjectIdentifier(self) ? $0.attempts : [] }
    }

    /// Throws `network-attempted` if anything tried to load.
    public func check() throws {
        let attempts = self.attempts
        if !attempts.isEmpty { throw Self.problem(attempts) }
    }

    /// Stops blocking and returns every attempt it saw.
    @discardableResult
    public func end() -> [Attempt] {
        let attempts: [Attempt]? = Self.state.withLock { state in
            guard state.active == ObjectIdentifier(self) else { return nil }
            let seen = state.attempts
            state.active = nil
            state.attempts = []
            return seen
        }
        guard let attempts else { return [] }
        URLProtocol.unregisterClass(ReinsBlockingURLProtocol.self)
        return attempts
    }

    /// `base` with the blocking protocol first, for the sessions an app builds and injects in a behavior session.
    public static func blocking(_ base: URLSessionConfiguration = .ephemeral) -> URLSessionConfiguration {
        let configuration = base.copy() as! URLSessionConfiguration
        configuration.protocolClasses = [ReinsBlockingURLProtocol.self] + (configuration.protocolClasses ?? [])
        return configuration
    }

    static func problem(_ attempts: [Attempt]) -> OuroAX.Problem {
        OuroAX.Problem(
            code: "network-attempted",
            exit: 3,
            thing: "behavior session",
            problem: "\(attempts.count) network request\(attempts.count == 1 ? "" : "s") attempted: \(attempts.map(\.description).joined(separator: ", "))",
            fix: "inject a fixture for each one through the type's constructor"
        )
    }

    static func record(_ request: URLRequest) -> Bool {
        state.withLock { state in
            guard state.active != nil else { return false }
            state.attempts.append(Attempt(method: request.httpMethod ?? "GET", url: request.url?.absoluteString ?? "(no URL)"))
            return true
        }
    }

    static var isActive: Bool { state.withLock { $0.active != nil } }

    /// Swaps `URLSessionConfiguration.default` and `.ephemeral` for versions that add the blocking protocol while a guard
    /// is active, once per process. With no guard active they return exactly what the originals do.
    private static let configurationGettersSwapped: Bool = {
        #if canImport(ObjectiveC)
        for (original, replacement) in [
            ("defaultSessionConfiguration", #selector(URLSessionConfiguration.reins_defaultSessionConfiguration)),
            ("ephemeralSessionConfiguration", #selector(URLSessionConfiguration.reins_ephemeralSessionConfiguration)),
        ] {
            guard let from = class_getClassMethod(URLSessionConfiguration.self, NSSelectorFromString(original)),
                  let to = class_getClassMethod(URLSessionConfiguration.self, replacement) else { return false }
            method_exchangeImplementations(from, to)
        }
        return true
        #else
        return false
        #endif
    }()
}

#if canImport(ObjectiveC)
import ObjectiveC

extension URLSessionConfiguration {
    // After the swap, each of these names the original getter, so the call inside reaches the system's configuration.
    @objc dynamic class func reins_defaultSessionConfiguration() -> URLSessionConfiguration {
        ReinsNetworkGuard.guarded(reins_defaultSessionConfiguration())
    }

    @objc dynamic class func reins_ephemeralSessionConfiguration() -> URLSessionConfiguration {
        ReinsNetworkGuard.guarded(reins_ephemeralSessionConfiguration())
    }
}
#endif

extension ReinsNetworkGuard {
    static func guarded(_ configuration: URLSessionConfiguration) -> URLSessionConfiguration {
        guard isActive else { return configuration }
        configuration.protocolClasses = [ReinsBlockingURLProtocol.self] + (configuration.protocolClasses ?? [])
        return configuration
    }
}

/// Fails every request while a guard is active, after recording it. A session built from ``ReinsNetworkGuard/blocking(_:)``
/// fails its requests even with no guard active, so a fixture session can never reach the network.
final class ReinsBlockingURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        _ = ReinsNetworkGuard.record(request)
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet, userInfo: [
            NSLocalizedDescriptionKey: "Ouro Reins blocked this request: behavior sessions have no network.",
        ]))
    }

    override func stopLoading() {}
}
