public import SwiftUI

/// How an ``OuroEmptyState`` lines up: `center` for a page or panel, `leading` with the text around it.
public enum OuroEmptyStateAlignment: Sendable { case center, leading }

/// `plain`, the default, sits open on the page the way Apple's `ContentUnavailableView` does; `outline` draws a dashed
/// edge around the empty area, for a drop zone or a slot that something will fill.
public enum OuroEmptyStateVariant: Sendable { case outline, plain }

/// The resolved colours of an empty state as seen; its words read at 5:1 (7:1 under increased contrast).
public struct OuroEmptyStatePalette: Sendable {
    public var title: Color.Resolved
    public var description: Color.Resolved
    public var icon: Color.Resolved
    public var iconWell: Color.Resolved
    public var border: Color.Resolved
    public var surface: Color.Resolved

    /// `hasAction`: the symbol gives way to the action, in the secondary colour, so there is one thing to look at.
    public init(style: OuroHXStyle, hasAction: Bool = false) {
        let c = style.colors
        surface = OuroInk.r(c.background)
        title = OuroInk.readable(OuroInk.r(c.foreground), on: surface, style)
        description = OuroInk.readable(OuroInk.r(c.mutedForeground), on: surface, style)
        iconWell = OuroInk.r(c.muted)
        // Standing alone the symbol is the state's one note of colour, the theme's primary; with an action it is quiet,
        // the secondary colour, and the action carries the colour. Hierarchical either way, reading at the words'
        // contrast where it is solid.
        icon = OuroInk.readable(OuroInk.r(hasAction ? c.mutedForeground : c.primary), on: surface, style)
        border = OuroColor.push(OuroInk.r(c.border), against: surface, to: OuroColor.increasedLineContrast)
    }
}

/// What a list, search or page shows when it has nothing in it: an icon, a title that says what is empty, a sentence
/// on what to do, and the action that does it. Web's `Empty`.
///
/// ```swift
/// OuroEmptyState("No recipes yet", systemImage: "book", description: "Start by creating your first recipe.") {
///     OuroButton("Create recipe") { create() }
/// }
/// ```
///
/// The title is a VoiceOver heading; the icon is decorative and hidden from VoiceOver. Everything wraps at large text
/// sizes, and at the accessibility sizes the action spans the width.
public struct OuroEmptyState<Action: View>: View {
    private let title: String
    private let systemImage: String?
    private let description: String?
    private let alignment: OuroEmptyStateAlignment
    private let variant: OuroEmptyStateVariant
    private let action: Action
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The symbol's size, which grows with Dynamic Type like the title under it.
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
    @State private var arrived = false

    public init(
        _ title: String,
        systemImage: String? = nil,
        description: String? = nil,
        alignment: OuroEmptyStateAlignment = .center,
        variant: OuroEmptyStateVariant = .plain,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.alignment = alignment
        self.variant = variant
        self.action = action()
    }

    public var body: some View {
        let p = OuroEmptyStatePalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast), hasAction: Action.self != EmptyView.self)
        let symbolSize = min(OuroEmptyStateMetrics.symbolSize(alignment: alignment) * scale, OuroEmptyStateMetrics.maximumSymbolSize)
        let horizontal: HorizontalAlignment = alignment == .center ? .center : .leading
        let text: TextAlignment = alignment == .center ? .center : .leading
        VStack(alignment: horizontal, spacing: 0) {
            if let systemImage {
                // A large symbol on the page, no well or tile around it, as in Apple's own empty states. It gives
                // one small bounce as it arrives (not under Reduce Motion).
                Image(systemName: systemImage)
                    .font(.system(size: symbolSize, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(p.icon))
                    .symbolEffect(.bounce.down, options: .nonRepeating, value: arrived)
                    // A symbol's own side bearing sets it in from a leading edge; this lines its ink up with the title.
                    .padding(.leading, alignment == .leading ? -symbolSize * 0.08 : 0)
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color(p.title))
                .multilineTextAlignment(text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let description {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(Color(p.description))
                    .multilineTextAlignment(text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, OuroEmptyStateMetrics.descriptionSpacing)
            }
            if Action.self != EmptyView.self {
                action
                    .environment(\.ouroButtonFillsWidth, typeSize.isAccessibilitySize)
                    .padding(.top, 20)
            }
        }
        // A short measure keeps the sentence to two or three balanced lines, as Apple's empty states do.
        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : OuroEmptyStateMetrics.maximumTextWidth, alignment: alignment == .center ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .padding(.vertical, 32)
        // Centred it keeps clear of the edges; leading, it lines up with the page's own margin, like the text around it.
        .padding(.horizontal, alignment == .center ? 24 : 0)
        .onAppear { if !reduceMotion { arrived = true } }
        .overlay {
            if variant == .outline {
                RoundedRectangle(cornerRadius: theme.radius(.xl), style: .continuous)
                    .strokeBorder(Color(p.border), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension OuroEmptyState where Action == EmptyView {
    /// An empty state with no action.
    public init(_ title: String, systemImage: String? = nil, description: String? = nil, alignment: OuroEmptyStateAlignment = .center, variant: OuroEmptyStateVariant = .plain) {
        self.init(title, systemImage: systemImage, description: description, alignment: alignment, variant: variant) { EmptyView() }
    }
}

/// Metrics every ``OuroEmptyState`` shares, as data.
public enum OuroEmptyStateMetrics {
    /// The widest its words run, below the accessibility text sizes: 340 points.
    public static let maximumTextWidth: CGFloat = 340
    /// The symbol's size at the default text size: a 60-point hero centred, 44 points inline beside leading text. It
    /// grows with Dynamic Type up to ``maximumSymbolSize``.
    public static func symbolSize(alignment: OuroEmptyStateAlignment) -> CGFloat { alignment == .center ? 60 : 44 }
    /// The largest the symbol grows, so at the accessibility sizes the words and action stay in view.
    public static let maximumSymbolSize: CGFloat = 80
    /// The gap from the title to the description.
    public static let descriptionSpacing: CGFloat = 8
}
