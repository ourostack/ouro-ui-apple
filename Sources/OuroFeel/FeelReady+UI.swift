#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
import Foundation
public import OuroFeelCore
public import XCTest

extension OuroFeel {
    // MARK: Content readiness

    /// When a call's wait for content ends: ``readyTimeout`` from now, shared by every pose of the call, so a round trip
    /// of poses never waits more than one timeout in all.
    func readyDeadline() -> Double { Date().timeIntervalSinceReferenceDate + readyTimeout }

    /// Looks with `look` (a read of the content by the check's own walk of the screen, with ``ready`` folded in) until
    /// it is ready or `deadline` passes. `nil` once ready; otherwise the failed result that says it never became ready.
    func awaitReady(check: String, what: String?, pose: String, until deadline: Double,
                    look: () -> FeelReadyLook) -> FeelResult? {
        let readiness = FeelReady.wait(timeout: max(0, deadline - Date().timeIntervalSinceReferenceDate),
                                       now: { Date().timeIntervalSinceReferenceDate }, look: look, pause: { self.pause($0) })
        guard !readiness.ready else { return nil }
        var result = FeelReady.neverReady(check: check, readiness: readiness, what: what, pose: pose)
        result.environment = environment
        return result
    }

    /// The app's ``ready`` signal now, or `nil` when none is given.
    var readySignal: Bool? { ready.map { $0(app) } }

    /// `nil` once `read` returns something and the app's ``ready`` signal, if any, holds; otherwise the failed result.
    /// The place checks read the place with the caller's own `read`, so this waits on exactly what they compare.
    func awaitReading(check: String, read: () -> String) -> FeelResult? {
        awaitReady(check: check, what: "the place's reading", pose: "the current pose", until: readyDeadline()) {
            FeelReadyLook(content: read().isEmpty ? 0 : 1, signal: readySignal)
        }
    }
}
#endif
