public import SwiftUI

/// A badge's visual weight, as on web: `solid` fills it with the tone, `soft` tints it, `outline` draws only the edge.
public enum OuroBadgeVariant: String, CaseIterable, Sendable {
    case solid, soft, outline

    /// The button variant drawn the same way, so a badge beside a button of its tone reads as one family.
    var button: OuroButtonVariant {
        switch self {
        case .solid: .solid
        case .soft: .soft
        case .outline: .outline
        }
    }
}

/// The resolved colours of a badge, for one tone, variant and theme as seen: an ``OuroButtonPalette``'s, so its words
/// read at 5:1 on what is behind them (7:1 under increased contrast) in every theme; core claim `contrast.text`.
public struct OuroBadgePalette: Sendable {
    public var label: Color.Resolved
    public var fill: Color.Resolved?
    public var border: Color.Resolved?
    /// What the words sit on: the fill, or the page for `outline`.
    public var surface: Color.Resolved

    public init(tone: OuroTone, variant: OuroBadgeVariant, style: OuroHXStyle) {
        let p = OuroButtonPalette(tone: tone, variant: variant.button, style: style)
        label = p.label
        fill = p.fill
        border = p.border
        surface = p.surface
    }
}

/// Metrics every ``OuroBadge`` shares, as data.
public enum OuroBadgeMetrics {
    /// Web's default tone: a quiet neutral label.
    public static let defaultTone = OuroTone.secondary
    /// Web's default variant.
    public static let defaultVariant = OuroBadgeVariant.solid
    /// Web's `h-6`: 24 points at the default text size, taller as the text grows.
    public static let minimumHeight: CGFloat = 24
    /// Web's `px-2`.
    public static let horizontalPadding: CGFloat = 8
    /// Web's `rounded-md`, from the theme.
    public static let radius = OuroRadius.md

    /// One line up to the largest standard size, as web's `whitespace-nowrap`. At the accessibility sizes a badge
    /// wraps instead, so its words are never cut off (core claim `text.reflows`).
    public static func lineLimit(for size: DynamicTypeSize) -> Int? { size.isAccessibilitySize ? nil : 1 }
}

/// Ouro HX's badge: a short label or a count beside something else, web's `Badge`.
///
/// ```swift
/// OuroBadge("Vegan", systemImage: "leaf", tone: .success, variant: .soft)
/// OuroBadge("3", tone: .destructive)
/// ```
///
/// It is a label, not a control: VoiceOver reads its words with whatever it sits in, and its icon is decorative. For a
/// chip someone presses, such as a filter, use ``OuroButton`` at size `.sm`.
public struct OuroBadge: View {
    let text: String
    let systemImage: String?
    let tone: OuroTone
    let variant: OuroBadgeVariant
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ text: String, systemImage: String? = nil, tone: OuroTone = OuroBadgeMetrics.defaultTone, variant: OuroBadgeVariant = OuroBadgeMetrics.defaultVariant) {
        self.text = text
        self.systemImage = systemImage
        self.tone = tone
        self.variant = variant
    }

    public var body: some View {
        let palette = OuroBadgePalette(tone: tone, variant: variant, style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        let shape = RoundedRectangle(cornerRadius: theme.radius(OuroBadgeMetrics.radius), style: .continuous)
        let width = OuroButtonMetrics.outlineWidth(contrast: contrast)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .lineLimit(OuroBadgeMetrics.lineLimit(for: typeSize))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.medium))
        .multilineTextAlignment(.leading)
        .foregroundStyle(Color(palette.label))
        .padding(.horizontal, OuroBadgeMetrics.horizontalPadding)
        .padding(.vertical, 3)
        .frame(minHeight: OuroBadgeMetrics.minimumHeight)
        .background {
            if let fill = palette.fill { shape.fill(Color(fill)) }
        }
        .overlay {
            if let border = palette.border { shape.strokeBorder(Color(border), lineWidth: width) }
        }
        .accessibilityElement(children: .combine)
    }
}
