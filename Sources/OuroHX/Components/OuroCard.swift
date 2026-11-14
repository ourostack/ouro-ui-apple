public import SwiftUI

/// A card's frame, as on web: `outline` is a bordered surface in the theme's card colours; `plain` has no frame or
/// padding, for a card's structure inside a surface of your own.
public enum OuroCardVariant: String, CaseIterable, Sendable { case outline, plain }

/// A card's padding, as on web: `md` is 24 points, `sm` 16, for dense grids.
public enum OuroCardSize: String, CaseIterable, Sendable { case md, sm }

/// The resolved colours of a card as seen: its title and description read at 5:1 on its surface (7:1 under
/// increased contrast), and its edge at 3:1 under increased contrast; core claim `contrast.text`.
public struct OuroCardPalette: Sendable {
    public var title: Color.Resolved
    public var description: Color.Resolved
    public var fill: Color.Resolved?
    public var border: Color.Resolved?
    /// What the words sit on: the theme's card colour, or the page for `plain`.
    public var surface: Color.Resolved

    public init(variant: OuroCardVariant, style: OuroHXStyle) {
        let c = style.colors
        switch variant {
        case .outline:
            let card = OuroInk.r(c.card)
            fill = card
            surface = card
            border = OuroColor.push(OuroInk.r(c.border), against: card, to: style.contrast == .increased ? OuroColor.increasedLineContrast : 1)
            title = OuroInk.readable(OuroInk.r(c.cardForeground), on: card, style)
        case .plain:
            let page = OuroInk.r(c.background)
            fill = nil
            border = nil
            surface = page
            title = OuroInk.readable(OuroInk.r(c.foreground), on: page, style)
        }
        description = OuroInk.readable(OuroInk.r(c.mutedForeground), on: surface, style)
    }
}

/// Metrics every ``OuroCard`` shares, as data.
public enum OuroCardMetrics {
    public static let defaultVariant = OuroCardVariant.outline
    public static let defaultSize = OuroCardSize.md
    /// The theme's `xl` corner, continuous, as A2UI's card already drew it.
    public static let radius = OuroRadius.xl
    /// No line limit on the title or the description at any size (core claim `text.reflows`).
    public static let titleLineLimit: Int? = nil
    public static let descriptionLineLimit: Int? = nil

    /// Web's padding: `md` 24 points, `sm` 16; none for `plain`.
    public static func padding(size: OuroCardSize, variant: OuroCardVariant) -> CGFloat {
        guard variant == .outline else { return 0 }
        return size == .md ? 24 : 16
    }

    /// The space between a card's header, body and footer: 16 points, 12 in a small card.
    public static func spacing(size: OuroCardSize) -> CGFloat { size == .md ? 16 : 12 }

    /// Whether the action goes under the title rather than beside it: at the accessibility sizes, so the title has the
    /// width and wraps less.
    public static func stacksAction(at size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }
}

/// Ouro HX's card: a surface that groups one thing's content, with a title, a description and an action beside it, a
/// body, and a footer. Web's `Card`.
///
/// ```swift
/// OuroCard("Pantry", description: "What you have on hand") {
///     Text("Flour, rice, black beans.")
/// } action: {
///     OuroButton("Edit", variant: .plain, size: .sm) { edit() }
/// }
/// ```
///
/// The title is a heading for VoiceOver. Use a `List` row (or a future `OuroItem`) for a compact row in a list, and a
/// plain stack when the group needs no surface.
public struct OuroCard<Content: View, Action: View, Footer: View>: View {
    let title: String?
    let description: String?
    let variant: OuroCardVariant
    let size: OuroCardSize
    let content: Content
    let action: Action
    let footer: Footer
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        _ title: String? = nil,
        description: String? = nil,
        variant: OuroCardVariant = OuroCardMetrics.defaultVariant,
        size: OuroCardSize = OuroCardMetrics.defaultSize,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.description = description
        self.variant = variant
        self.size = size
        self.content = content()
        self.action = action()
        self.footer = footer()
    }

    public var body: some View {
        let palette = OuroCardPalette(variant: variant, style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        let shape = RoundedRectangle(cornerRadius: theme.radius(OuroCardMetrics.radius), style: .continuous)
        VStack(alignment: .leading, spacing: OuroCardMetrics.spacing(size: size)) {
            header(palette)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            if Footer.self != EmptyView.self { footer }
        }
        .foregroundStyle(Color(palette.title))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OuroCardMetrics.padding(size: size, variant: variant))
        .background {
            if let fill = palette.fill { shape.fill(Color(fill)) }
        }
        .overlay {
            if let border = palette.border {
                shape.strokeBorder(Color(border), lineWidth: OuroButtonMetrics.outlineWidth(contrast: contrast))
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func header(_ palette: OuroCardPalette) -> some View {
        let words = VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.headline)
                    .lineLimit(OuroCardMetrics.titleLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Color(palette.description))
                    .lineLimit(OuroCardMetrics.descriptionLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if title != nil || description != nil || Action.self != EmptyView.self {
            if OuroCardMetrics.stacksAction(at: typeSize) {
                VStack(alignment: .leading, spacing: 8) {
                    words
                    action
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    words.frame(maxWidth: .infinity, alignment: .leading)
                    action
                }
            }
        }
    }
}

extension OuroCard where Action == EmptyView, Footer == EmptyView {
    /// A card with a body, and a title and description if you give them.
    public init(
        _ title: String? = nil,
        description: String? = nil,
        variant: OuroCardVariant = OuroCardMetrics.defaultVariant,
        size: OuroCardSize = OuroCardMetrics.defaultSize,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, description: description, variant: variant, size: size, content: content, action: { EmptyView() }, footer: { EmptyView() })
    }
}

extension OuroCard where Footer == EmptyView {
    /// A card with a body and an action beside its title.
    public init(
        _ title: String? = nil,
        description: String? = nil,
        variant: OuroCardVariant = OuroCardMetrics.defaultVariant,
        size: OuroCardSize = OuroCardMetrics.defaultSize,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) {
        self.init(title, description: description, variant: variant, size: size, content: content, action: action, footer: { EmptyView() })
    }
}
