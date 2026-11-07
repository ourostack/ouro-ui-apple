public import SwiftUI
import os

/// A clock OuroHX's motion can run on in place of the screen's, so a UI test can film a real spring one tick at a
/// time and reach the same verdicts on a busy machine as on an idle one.
///
/// Test-only, so it is SPI: `@_spi(OuroMotionClock) import OuroHX`.
///
/// An app installs one for a test run (``OuroMotion/clock``) and calls ``advance(by:)`` each time the test asks it to
/// tick, for example on a Darwin notification posted by `FeelClock.darwinNotification(_:)`. Every animation OuroHX makes
/// then holds still between ticks and moves on by exactly one tick at each, whatever the wall clock does. Not for
/// production: with a clock installed and nothing advancing it, OuroHX's motion never finishes.
///
/// One difference from the screen: a spring interrupted mid-flight runs alongside the new one, the two adding up, where
/// on screen it would merge into it (retarget, keeping its speed). The wrapper cannot reach the spring inside the
/// animation it interrupts to merge with it. Both are continuous; the path between differs.
@_spi(OuroMotionClock) public final class OuroMotionClock: Hashable, Sendable {
    private let seconds = OSAllocatedUnfairLock(initialState: 0.0)

    public init() {}

    /// Seconds of motion so far.
    public var now: TimeInterval { seconds.withLock { $0 } }

    /// Moves the clock on by `interval` seconds.
    public func advance(by interval: TimeInterval) { seconds.withLock { $0 += interval } }

    public static func == (a: OuroMotionClock, b: OuroMotionClock) -> Bool { a === b }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

@_spi(OuroMotionClock) extension OuroMotion {
    private static let installed = OSAllocatedUnfairLock<OuroMotionClock?>(initialState: nil)

    /// The clock OuroHX's motion runs on, or nil (the default) for the screen's own.
    public static var clock: OuroMotionClock? {
        get { installed.withLock { $0 } }
        set { installed.withLock { $0 = newValue } }
    }

    /// `animation` timed by `clock` rather than the screen: it starts at the clock's time when it first runs, and each
    /// frame shows where it is by that clock. With no clock, `animation` as it is.
    public static func clocked(_ animation: Animation?, on clock: OuroMotionClock?) -> Animation? {
        animation.map { clocked($0, on: clock) }
    }

    public static func clocked(_ animation: Animation, on clock: OuroMotionClock?) -> Animation {
        clock.map { Animation(ClockedAnimation(base: animation, clock: $0)) } ?? animation
    }
}

private struct ClockedAnimation: CustomAnimation {
    let base: Animation
    let clock: OuroMotionClock

    private struct Start: AnimationStateKey {
        static var defaultValue: TimeInterval? { nil }
    }

    private func elapsed<V: VectorArithmetic>(_ context: inout AnimationContext<V>) -> TimeInterval {
        let now = clock.now
        if let start = context.state[Start.self] { return now - start }
        context.state[Start.self] = now
        return 0
    }

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        base.animate(value: value, time: elapsed(&context), context: &context)
    }

    func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        var context = context
        return base.velocity(value: value, time: elapsed(&context), context: context)
    }
}
