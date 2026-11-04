public import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A colour role from the theme, named after its token, as on web: `primary` reads `colors.primary`. The tone also
/// sets how urgently VoiceOver hears a banner or toast, and which haptic a toast plays.
public enum OuroTone: String, CaseIterable, Sendable {
    case primary, secondary, destructive, success, warning

    /// How urgently VoiceOver hears a banner or toast of this tone, as on web. A destructive or warning banner
    /// interrupts (web Alert's `role="alert"`); a toast interrupts only when destructive (web's Toaster puts warning
    /// toasts in its polite region). The rest wait their turn. Core claim `announce.urgency`.
    public func announcementPriority(for component: OuroToneComponent) -> OuroAnnouncementPriority {
        switch (self, component) {
        case (.destructive, _), (.warning, .banner): .high
        default: .default
        }
    }

    /// The haptic a toast of this tone plays when it shows: success finishes, warning warns, destructive fails.
    public var haptic: OuroHapticMoment? {
        switch self {
        case .success: .finished
        case .warning: .warned
        case .destructive: .failed
        case .primary, .secondary: nil
        }
    }

    /// The SF Symbol a banner or toast shows by default. A secondary toast has none, as on web.
    public func systemImage(for component: OuroToneComponent) -> String? {
        switch self {
        case .primary: "info.circle.fill"
        case .secondary: component == .banner ? "info.circle" : nil
        case .destructive: "xmark.octagon.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    /// The tone's fill and the label that goes on it, from the theme.
    func fill(_ c: OuroColors) -> (fill: Color, label: Color) {
        switch self {
        case .primary: (c.primary, c.primaryForeground)
        case .secondary: (c.secondary, c.secondaryForeground)
        case .destructive: (c.destructive, c.destructiveForeground)
        case .success: (c.success, c.successForeground)
        case .warning: (c.warning, c.warningForeground)
        }
    }
}

/// Which component asks a tone for its icon.
public enum OuroToneComponent: Sendable { case banner, toast }

/// How urgently VoiceOver speaks an announcement.
public enum OuroAnnouncementPriority: Sendable { case high, `default` }

/// How a component is pressed: a finger on a touch screen, or a pointer.
public enum OuroInput: Sendable {
    case touch, pointer

    /// Touch on iPhone, iPad and Vision Pro; a pointer on the Mac.
    public static var current: OuroInput {
        #if os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
        .touch
        #else
        .pointer
        #endif
    }
}

/// How a component comes and goes, as data, so a test can check it without rendering. Under Reduce Motion every
/// component uses ``fade``: a crossfade over `ouro.duration.base`. Core claim `motion.reduced`.
public enum OuroAppearance: Equatable, Sendable {
    /// Slides in from an edge on core's spring.
    case move(edge: Edge)
    /// Crossfades.
    case fade

    public var transition: AnyTransition {
        switch self {
        case let .move(edge): .move(edge: edge).combined(with: .opacity)
        case .fade: .opacity
        }
    }

    public func step(reduceMotion: Bool) -> OuroMotion.Step {
        switch self {
        case .move: OuroMotion.step(.spring, reduceMotion: reduceMotion)
        case .fade: .crossfade(duration: OuroMotion.reducedMotionCrossfade)
        }
    }

    /// `moving` normally, ``fade`` under Reduce Motion.
    public static func choose(_ moving: OuroAppearance, reduceMotion: Bool) -> OuroAppearance {
        reduceMotion ? .fade : moving
    }
}

enum OuroAnnounce {
    /// Speaks `text` through VoiceOver with the priority, without moving focus (WCAG 4.1.3).
    @MainActor
    static func post(_ text: String, priority: OuroAnnouncementPriority) {
        guard !text.isEmpty else { return }
        var string = AttributedString(text)
        string.accessibilitySpeechAnnouncementPriority = priority == .high ? .high : .default
        AccessibilityNotification.Announcement(string).post()
    }
}

// MARK: Resolved colours shared by the components

enum OuroInk {
    static func r(_ c: Color) -> Color.Resolved { OuroColor.resolve(c) }

    /// `text` raised until it reads on `surface` at the style's target: 5:1, or 7:1 under increased contrast. WCAG asks
    /// for 4.5; the margin is because Xcode's audit measures antialiased pixels, and read a soft button's label and a
    /// banner's description at exactly 4.5:1 as "Contrast nearly passed".
    static func readable(_ text: Color.Resolved, on surface: Color.Resolved, _ style: OuroHXStyle) -> Color.Resolved {
        OuroColor.push(text, against: surface, to: target(style))
    }

    static func target(_ style: OuroHXStyle) -> Double {
        style.contrast == .increased ? OuroColor.increasedTextContrast : 5
    }

    /// The tone's colour laid over `base` at `amount`, the way a soft fill looks.
    static func tint(_ tone: Color.Resolved, over base: Color.Resolved, _ amount: Double) -> Color.Resolved {
        OuroColor.mix(base, tone, amount)
    }
}

extension EnvironmentValues {
    /// The touch target for controls here, in layout points: 44, or 46 inside an `.ouroSheet`, which iOS draws at 96%
    /// below its full height (``OuroSheetMetrics/drawnScale``). ``OuroButton`` reads it; size custom rows with it too.
    @Entry public var ouroTouchTarget: CGFloat = 44
}
