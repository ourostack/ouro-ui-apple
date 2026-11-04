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
        // A soft wash of the tone. In dark mode it is stronger and washes the raised card colour rather than the page,
        // since a faint tint over near-black reads as mud.
        let base = style.scheme == .dark ? OuroInk.r(c.card) : background
        surface = tone == .secondary ? OuroInk.r(c.muted) : OuroInk.tint(toneColour, over: base, style.scheme == .dark ? 0.18 : 0.1)
        title = OuroInk.readable(OuroInk.r(c.foreground), on: surface, style)
        // The description leans toward the tone, so the words belong to the wash rather than sitting grey on it.
        let leaning = tone == .secondary ? OuroInk.r(c.mutedForeground) : OuroInk.tint(toneColour, over: OuroInk.r(c.mutedForeground), 0.3)
        description = OuroInk.readable(leaning, on: surface, style)
        icon = OuroInk.readable(tone == .secondary ? OuroInk.r(c.foreground) : toneColour, on: surface, style)
        border = OuroColor.push(tone == .secondary ? OuroInk.r(c.border) : OuroInk.tint(toneColour, over: background, 0.35), against: surface, to: style.contrast == .increased ? OuroColor.increasedLineContrast : 1)
    }
}

/// Metrics, motion and words every ``OuroBanner`` shares, as data.
public enum OuroBannerMetrics {
    /// Whether a banner says `words`, given what it last said: once when it arrives, and again only when its words
    /// change, not each time it scrolls back into view or its screen is shown again.
    public static func announces(_ words: String, after last: String?) -> Bool { words != last }

    /// The corner radius: 18 points, continuous, the radius of Apple's inset grouped cells and notifications.
    public static let cornerRadius: CGFloat = 18

    /// The dismiss button's target, in points: 44 on every platform.
    public static let dismissTarget: CGFloat = 44

    /// A banner unfolds in place as the page makes room, never sliding over what is above it; it crossfades under
    /// Reduce Motion.
    public static func appearance(reduceMotion: Bool) -> OuroAppearance {
        .choose(.unfold, reduceMotion: reduceMotion)
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
/// With `onDismiss` it has a 44-point close button named `dismissLabel`. Prefer `isPresented` to an `if` around it:
/// changed inside an animation (`withOuroAnimation(.layout, reduceMotion: reduceMotion) { saved = false }`) it folds
/// away and back in place, and turns around smoothly if changed again mid-way. Folded away it takes no height, but a
/// stack's `spacing` still puts a gap where it was: in a stack with spacing, give the banner its gap as padding in a
/// `spacing: 0` stack instead. Inserted or removed inside an animation
/// (`withOuroAnimation(.layout, reduceMotion: reduceMotion) { error = nil }`), it unfolds in place, or crossfades
/// under Reduce Motion.
public struct OuroBanner<Action: View>: View {
    private let title: String
    private let description: String?
    private let tone: OuroTone
    private let icon: OuroIcon
    private let dismissLabel: String
    private let onDismiss: (() -> Void)?
    private let isPresented: Bool
    private let action: Action
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.ouroTouchTarget) private var touchTarget
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// What VoiceOver last heard from this banner.
    @State private var announced: String?

    public init(
        _ title: String,
        description: String? = nil,
        tone: OuroTone = .secondary,
        icon: OuroIcon = .automatic,
        dismissLabel: String = "Dismiss",
        onDismiss: (() -> Void)? = nil,
        isPresented: Bool = true,
        @ViewBuilder action: () -> Action
    ) {
        self.isPresented = isPresented
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
        Group {
            if typeSize.isAccessibilitySize {
                // At the accessibility sizes the words get the whole width: the icon and the close button share a row
                // above them, so nothing squeezes the sentence to a word a line.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        iconView(p)
                        Spacer(minLength: 0)
                        closeButton(p)
                    }
                    words(p)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    iconView(p).padding(.top, 1)
                    words(p)
                    closeButton(p)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // A wash of colour with no outline, so it reads as part of the page rather than a box on it; under increased
        // contrast it gains a 2-point edge.
        .background(Color(p.surface), in: RoundedRectangle(cornerRadius: OuroBannerMetrics.cornerRadius, style: .continuous))
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: OuroBannerMetrics.cornerRadius, style: .continuous).strokeBorder(Color(p.border), lineWidth: 2)
            }
        }
        .accessibilityElement(children: .contain)
        // Shown and hidden in place: its height, scale and opacity are animated values, so a banner hidden and shown
        // again mid-way turns around smoothly on the spring, which an `if` around it (a removal) cannot do.
        .modifier(Unfolds(shown: isPresented, reduceMotion: reduceMotion))
        .transition(OuroBannerMetrics.appearance(reduceMotion: reduceMotion).transition)
        // Spoken once when it arrives and again when its words change, not each time it scrolls back into view.
        .onAppear { if isPresented { announceIfNew() } }
        .onChange(of: isPresented) { _, now in if now { announced = nil; announceIfNew() } }
        .onChange(of: OuroBannerMetrics.announcement(title: title, description: description)) { announceIfNew() }
    }
}

extension OuroBanner {
    @ViewBuilder private func iconView(_ p: OuroBannerPalette) -> some View {
        if let name = icon.name(tone, .banner) {
            Image(systemName: name)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(p.icon))
                .accessibilityHidden(true)
        }
    }

    private func words(_ p: OuroBannerPalette) -> some View {
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
    }

    @ViewBuilder private func closeButton(_ p: OuroBannerPalette) -> some View {
        if let onDismiss {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(p.description))
                    .frame(width: max(OuroBannerMetrics.dismissTarget, touchTarget), height: max(OuroBannerMetrics.dismissTarget, touchTarget))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.ouroPress)
            .accessibilityLabel(dismissLabel)
            .padding(.trailing, -12)
            .padding(.vertical, -12)
        }
    }

    private func announceIfNew() {
        guard isPresented else { return }
        let words = OuroBannerMetrics.announcement(title: title, description: description)
        guard OuroBannerMetrics.announces(words, after: announced) else { return }
        announced = words
        OuroAnnounce.post(words, priority: tone.announcementPriority(for: .banner))
    }
}

extension OuroBanner where Action == EmptyView {
    /// A banner with no action.
    public init(_ title: String, description: String? = nil, tone: OuroTone = .secondary, icon: OuroIcon = .automatic, dismissLabel: String = "Dismiss", onDismiss: (() -> Void)? = nil, isPresented: Bool = true) {
        self.init(title, description: description, tone: tone, icon: icon, dismissLabel: dismissLabel, onDismiss: onDismiss, isPresented: isPresented) { EmptyView() }
    }
}

/// Folds a banner away to nothing at its top edge, and back. One animatable value drives its height, scale and
/// opacity, so a change mid-way retargets that value on the spring; animating the frame's height instead stalled a
/// frame at every turnaround in the gallery's frame captures.
private struct Unfolds: ViewModifier {
    let shown: Bool
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        let progress = shown ? 1.0 : 0
        FoldLayout(progress: progress) {
            content
                .modifier(FoldLook(progress: progress, scales: !reduceMotion))
        }
        .clipped()
        .accessibilityHidden(!shown)
        .allowsHitTesting(shown)
    }
}

/// Opacity, and a scale from 96% at the top edge, for a fold `progress` of the way open.
private struct FoldLook: ViewModifier, @MainActor Animatable {
    var progress: Double
    let scales: Bool
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content
            .scaleEffect(scales ? 0.96 + 0.04 * progress : 1, anchor: .top)
            .opacity(progress)
    }
}

/// Takes `progress` of its child's height, the child pinned to the top.
private struct FoldLayout: Layout {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: size.width, height: size.height * max(0, progress))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
