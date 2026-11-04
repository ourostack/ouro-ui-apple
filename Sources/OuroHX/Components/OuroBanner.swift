public import SwiftUI

/// The icon a banner or toast shows: its tone's own (`automatic`), none, or an SF Symbol of yours.
public enum OuroIcon: Sendable, Equatable {
    case automatic
    case none
    case system(String)

    func name(_ tone: OuroTone, _ component: OuroToneComponent) -> String? {
        switch self {
        case .automatic: tone.systemImage(for: component)
        case .none: nil
        case let .system(name): name
        }
    }
}

/// The resolved colours of a banner as seen: a soft tint of its tone over the page, with its words and icon at 5:1
/// (7:1 under increased contrast).
public struct OuroBannerPalette: Sendable {
    public var title: Color.Resolved
    public var description: Color.Resolved
    public var icon: Color.Resolved
    public var border: Color.Resolved
    public var surface: Color.Resolved

    public init(tone: OuroTone, style: OuroHXStyle) {
        let c = style.colors
        let background = OuroInk.r(c.background)
        let toneColour = OuroInk.r(tone.fill(c).fill)
        surface = tone == .secondary ? OuroInk.r(c.muted) : OuroInk.tint(toneColour, over: background, 0.1)
        title = OuroInk.readable(OuroInk.r(c.foreground), on: surface, style)
        description = OuroInk.readable(OuroInk.r(c.mutedForeground), on: surface, style)
        icon = OuroInk.readable(tone == .secondary ? OuroInk.r(c.foreground) : toneColour, on: surface, style)
        border = OuroColor.push(tone == .secondary ? OuroInk.r(c.border) : OuroInk.tint(toneColour, over: background, 0.35), against: surface, to: style.contrast == .increased ? OuroColor.increasedLineContrast : 1)
    }
}

/// Metrics, motion and words every ``OuroBanner`` shares, as data.
public enum OuroBannerMetrics {
    /// The dismiss button's target, in points: 44 on every platform.
    public static let dismissTarget: CGFloat = 44

    /// A banner slides down into place, or crossfades under Reduce Motion.
    public static func appearance(reduceMotion: Bool) -> OuroAppearance {
        .choose(.move(edge: .top), reduceMotion: reduceMotion)
    }

    /// What VoiceOver says when a banner appears: its title, then its description.
    public static func announcement(title: String, description: String?) -> String {
        guard let description, !description.isEmpty else { return title }
        return "\(title). \(description)"
    }
}

/// An inline message in the page: something saved, something failed, something to know before going on. Web's
/// `Alert` (on Apple, "alert" is SwiftUI's modal `.alert`).
///
/// ```swift
/// OuroBanner("Recipe saved", tone: .success)
/// OuroBanner("Couldn't save", description: "Check your connection and try again.", tone: .destructive,
///            onDismiss: { error = nil }) {
///     OuroButton("Try again", size: .sm) { retry() }
/// }
/// ```
///
/// VoiceOver hears it once when it appears: destructive and warning banners at once, the others when it is free.
/// With `onDismiss` it has a 44-point close button named `dismissLabel`. Inserted or removed inside an animation
/// (`withOuroAnimation(.spring, reduceMotion: reduceMotion) { error = nil }`), it slides from the top, or crossfades
/// under Reduce Motion.
public struct OuroBanner<Action: View>: View {
    private let title: String
    private let description: String?
    private let tone: OuroTone
    private let icon: OuroIcon
    private let dismissLabel: String
    private let onDismiss: (() -> Void)?
    private let action: Action
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.ouroTouchTarget) private var touchTarget
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ title: String,
        description: String? = nil,
        tone: OuroTone = .secondary,
        icon: OuroIcon = .automatic,
        dismissLabel: String = "Dismiss",
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.description = description
        self.tone = tone
        self.icon = icon
        self.dismissLabel = dismissLabel
        self.onDismiss = onDismiss
        self.action = action()
    }

    public var body: some View {
        let p = OuroBannerPalette(tone: tone, style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        HStack(alignment: .top, spacing: 12) {
            if let name = icon.name(tone, .banner) {
                Image(systemName: name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(p.icon))
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(p.title))
                        .fixedSize(horizontal: false, vertical: true)
                    if let description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(Color(p.description))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                if Action.self != EmptyView.self { action }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(p.title))
                        .frame(width: max(OuroBannerMetrics.dismissTarget, touchTarget), height: max(OuroBannerMetrics.dismissTarget, touchTarget))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dismissLabel)
                .padding(.trailing, -10)
                .padding(.vertical, -10)
            }
        }
        .padding(14)
        .background(Color(p.surface), in: RoundedRectangle(cornerRadius: theme.radius(.lg), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radius(.lg), style: .continuous).strokeBorder(Color(p.border), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .transition(OuroBannerMetrics.appearance(reduceMotion: reduceMotion).transition)
        .onAppear { OuroAnnounce.post(OuroBannerMetrics.announcement(title: title, description: description), priority: tone.announcementPriority(for: .banner)) }
    }
}

extension OuroBanner where Action == EmptyView {
    /// A banner with no action.
    public init(_ title: String, description: String? = nil, tone: OuroTone = .secondary, icon: OuroIcon = .automatic, dismissLabel: String = "Dismiss", onDismiss: (() -> Void)? = nil) {
        self.init(title, description: description, tone: tone, icon: icon, dismissLabel: dismissLabel, onDismiss: onDismiss) { EmptyView() }
    }
}
