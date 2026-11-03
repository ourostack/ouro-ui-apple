public import SwiftUI

/// Motion from core's tokens, with one Reduce Motion rule: everything that moves becomes a short crossfade, and a
/// press stops scaling. From Spoonjoy's `KitchenMotion` (the crossfade rule) and core's `ouro.duration`, `ouro.ease`,
/// `ouro.spring` and `ouro.press`.
public enum OuroMotion {
    /// What is moving.
    public enum Kind: String, CaseIterable, Sendable {
        /// Most state changes: core's spring.
        case spring
        /// Hover and small fades (`ouro.duration.fast`, ease out).
        case fast
        /// Ordinary transitions (`ouro.duration.base`, ease out).
        case base
        /// Larger moves (`ouro.duration.slow`, ease in-out).
        case slow
        /// A control's press (`ouro.duration.press`, ease out).
        case press
        /// A sheet or drawer (`ouro.duration.sheet`, the drawer ease).
        case sheet
        /// A line drawing itself (`ouro.duration.draw`, ease out).
        case draw
    }

    /// How a change moves, as data, so a test can check it without rendering.
    public enum Step: Equatable, Sendable {
        case spring(visualDuration: Double, bounce: Double)
        case curve(OuroCubicBezier, duration: Double)
        case crossfade(duration: Double)
        /// No animation at all.
        case none

        public var animation: Animation? {
            switch self {
            case let .spring(duration, bounce): .spring(duration: duration, bounce: bounce)
            case let .curve(bezier, duration): bezier.animation(duration: duration)
            case let .crossfade(duration): .easeInOut(duration: duration)
            case .none: nil
            }
        }
    }

    /// The crossfade every kind but `press` becomes under Reduce Motion.
    public static let reducedMotionCrossfade = OuroTokens.Duration.base

    public static func step(_ kind: Kind, reduceMotion: Bool) -> Step {
        if reduceMotion { return kind == .press ? .none : .crossfade(duration: reducedMotionCrossfade) }
        typealias D = OuroTokens.Duration
        typealias E = OuroTokens.Ease
        switch kind {
        case .spring: return .spring(visualDuration: OuroTokens.Spring.visualDuration, bounce: OuroTokens.Spring.bounce)
        case .fast: return .curve(E.out, duration: D.fast)
        case .base: return .curve(E.out, duration: D.base)
        case .slow: return .curve(E.inOut, duration: D.slow)
        case .press: return .curve(E.out, duration: D.press)
        case .sheet: return .curve(E.drawer, duration: D.sheet)
        case .draw: return .curve(E.out, duration: D.draw)
        }
    }

    public static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation? {
        step(kind, reduceMotion: reduceMotion).animation
    }

    /// `transition`, or a plain fade under Reduce Motion.
    public static func transition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }

    /// The scale of a pressed control: core's press scale, or none under Reduce Motion.
    public static func pressScale(isPressed: Bool, reduceMotion: Bool) -> Double {
        isPressed && !reduceMotion ? OuroTokens.Press.scale : 1
    }
}

/// Animates `body` with an HX motion kind, honouring Reduce Motion.
@MainActor
public func withOuroAnimation<Result>(_ kind: OuroMotion.Kind, reduceMotion: Bool, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(OuroMotion.animation(kind, reduceMotion: reduceMotion), body)
}

private struct OuroAnimationModifier<V: Equatable>: ViewModifier {
    let kind: OuroMotion.Kind
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(OuroMotion.animation(kind, reduceMotion: reduceMotion), value: value)
    }
}

private struct OuroTransitionModifier: ViewModifier {
    let transition: AnyTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(OuroMotion.transition(transition, reduceMotion: reduceMotion))
    }
}

extension View {
    /// Animates changes to `value` with an HX motion kind, as a crossfade under Reduce Motion.
    public func ouroAnimation(_ kind: OuroMotion.Kind = .spring, value: some Equatable) -> some View {
        modifier(OuroAnimationModifier(kind: kind, value: value))
    }

    /// A transition that becomes a fade under Reduce Motion.
    public func ouroTransition(_ transition: AnyTransition) -> some View {
        modifier(OuroTransitionModifier(transition: transition))
    }
}

/// A button style that shrinks to core's press scale while pressed (none under Reduce Motion).
public struct OuroPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration)
    }

    private struct PressBody: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(OuroMotion.pressScale(isPressed: configuration.isPressed, reduceMotion: reduceMotion))
                .animation(OuroMotion.animation(.press, reduceMotion: reduceMotion), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == OuroPressStyle {
    /// Core's press: `.buttonStyle(.ouroPress)`.
    public static var ouroPress: OuroPressStyle { OuroPressStyle() }
}
