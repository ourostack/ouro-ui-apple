public import Foundation

/// One look at the screen, for readiness: how many pieces of the content a check measures it found, read by the
/// check's own walk of the screen; the app's own readiness signal when it gives one (`nil` when it does not); and, when
/// no content was found, why, when the walk can tell (the snapshot failed, the page named in `within` was not on screen).
public struct FeelReadyLook: Equatable, Sendable {
    public var content: Int
    public var signal: Bool?
    public var why: String?

    public init(content: Int, signal: Bool? = nil, why: String? = nil) {
        self.content = content
        self.signal = signal
        self.why = why
    }

    /// Content is on screen, and the app, if it signals, says it is ready.
    public var ready: Bool { content > 0 && signal != false }
}

/// How the wait for content went: whether it became ready, after how long, in how many looks, and the last look.
public struct FeelReadiness: Equatable, Sendable {
    public var ready: Bool
    public var waited: TimeInterval
    public var looks: Int
    public var last: FeelReadyLook

    public init(ready: Bool, waited: TimeInterval, looks: Int, last: FeelReadyLook) {
        self.ready = ready
        self.waited = waited
        self.looks = looks
        self.last = last
    }
}

/// Content readiness: a check that measures what you read waits for it first, so it never scores an empty page.
///
/// In gatefold run 46076998864 (duo-feel-closed, on a loaded runner), covered content found no text in the reader's
/// page and failed without measuring anything, though the reader's own ready probe had passed before the checks ran.
/// The wait is on a signal, never a sleep: the content the check itself measures, and the app's own signal when it
/// gives one. A page that never becomes ready within the timeout fails as "never became ready", which is neither a bug
/// found nor a "could not check".
public enum FeelReady {
    /// How long a check waits for its content by default: generous, since a loaded runner can be very slow.
    public static let timeout: TimeInterval = 120

    /// Looks until the content is ready or `timeout` has passed, at most every `every` seconds. It always looks once,
    /// and pauses only between looks, so content already on screen costs one look.
    public static func wait(timeout: TimeInterval = FeelReady.timeout, every: TimeInterval = 0.25, now: () -> Double,
                            look: () -> FeelReadyLook, pause: (Double) -> Void) -> FeelReadiness {
        let start = now()
        var looks = 0
        while true {
            let began = now()
            let seen = look()
            looks += 1
            if seen.ready { return FeelReadiness(ready: true, waited: round3(began - start), looks: looks, last: seen) }
            if now() - start >= timeout { return FeelReadiness(ready: false, waited: round3(now() - start), looks: looks, last: seen) }
            let rest = every - (now() - began)
            if rest > 0 { pause(rest) }
        }
    }

    /// The result of a check whose content never became ready: it fails, and says why, with the time it waited.
    /// `what` names the element the content was looked for in, if any.
    public static func neverReady(check: String, readiness: FeelReadiness, what: String?, pose: String) -> FeelResult {
        let place = what.map { " in \"\($0)\"" } ?? ""
        let why = readiness.last.content == 0
            ? "no content came on screen\(place)" + (readiness.last.why.map { " (\($0))" } ?? "")
            : "the app never signalled ready (\(readiness.last.content) pieces of content were on screen\(place))"
        let detail = "\(why) in \(pose) after \(Self.seconds(readiness.waited)) s and \(readiness.looks) looks"
        return FeelResult(check: check, passed: false, summary: "never became ready: \(detail)",
                          measures: ["waited": readiness.waited, "looks": Double(readiness.looks),
                                     "content": Double(readiness.last.content)],
                          findings: [.neverBecameReady(detail)])
    }

    static func seconds(_ value: Double) -> String { String(format: "%.1f", value) }
}
