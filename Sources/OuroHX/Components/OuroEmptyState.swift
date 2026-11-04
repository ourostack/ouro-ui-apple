public import SwiftUI

/// How an ``OuroEmptyState`` lines up: `center` for a page or panel, `leading` with the text around it.
public enum OuroEmptyStateAlignment: Sendable { case center, leading }

/// `outline` draws a dashed edge around the empty area; `plain` has none, for one inside a list or card that
/// already has an edge.
public enum OuroEmptyStateVariant: Sendable { case outline, plain }

/// The resolved colours of an empty state as seen; its words read at 4.5:1 (7:1 under increased contrast).
public struct OuroEmptyStatePalette: Sendable {
    public var title: Color.Resolved
    public var description: Color.Resolved
    public var icon: Color.Resolved
    public var iconWell: Color.Resolved
    public var border: Color.Resolved
    public var surface: Color.Resolved

    public init(style: OuroHXStyle) {
        let c = style.colors
        surface = OuroInk.r(c.background)
        title = OuroInk.readable(OuroInk.r(c.foreground), on: surface, style)
        description = OuroInk.readable(OuroInk.r(c.mutedForeground), on: surface, style)
        iconWell = OuroInk.r(c.muted)
        icon = OuroInk.readable(OuroInk.r(c.mutedForeground), on: iconWell, style)
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

    public init(
        _ title: String,
        systemImage: String? = nil,
        description: String? = nil,
        alignment: OuroEmptyStateAlignment = .center,
        variant: OuroEmptyStateVariant = .outline,
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
        let p = OuroEmptyStatePalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        let horizontal: HorizontalAlignment = alignment == .center ? .center : .leading
        let text: TextAlignment = alignment == .center ? .center : .leading
        VStack(alignment: horizontal, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color(p.icon))
                    .frame(width: 56, height: 56)
                    .background(Color(p.iconWell), in: Circle())
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(p.title))
                .multilineTextAlignment(text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let description {
                Text(description)
                    .font(.body)
                    .foregroundStyle(Color(p.description))
                    .multilineTextAlignment(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if Action.self != EmptyView.self {
                action
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .padding(24)
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
    public init(_ title: String, systemImage: String? = nil, description: String? = nil, alignment: OuroEmptyStateAlignment = .center, variant: OuroEmptyStateVariant = .outline) {
        self.init(title, systemImage: systemImage, description: description, alignment: alignment, variant: variant) { EmptyView() }
    }
}
