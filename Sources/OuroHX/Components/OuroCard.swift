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

    /// From the media to the title, as web's card gap: an outlined card's padding (24, 16 small), 16 and 12 when plain.
    public static func mediaGap(size: OuroCardSize, variant: OuroCardVariant) -> CGFloat {
        variant == .outline ? padding(size: size, variant: variant) : (size == .md ? 16 : 12)
    }

    /// A plain card's media corner, as web's: the theme's `xl`, `lg` in a small card.
    public static func plainMediaRadius(size: OuroCardSize) -> OuroRadius { size == .md ? .xl : .lg }

    /// The press shade of a pressable card: web's linked card tints 6% toward its words.
    public static let pressTint = 0.06

    /// The space between a card's header, body and footer: 16 points, 12 in a small card.
    public static func spacing(size: OuroCardSize) -> CGFloat { size == .md ? 16 : 12 }

    /// Whether the action goes under the title rather than beside it: at the accessibility sizes, so the title has the
    /// width and wraps less.
    public static func stacksAction(at size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }
}

/// Ouro HX's card: a surface that groups one thing's content, with a picture across its top, a title, a description
/// and an action beside it, a body, and a footer. Web's `Card`.
///
/// ```swift
/// OuroCard("Pantry", description: "What you have on hand") {
///     Text("Flour, rice, black beans.")
/// } action: {
///     OuroButton("Edit", variant: .plain, size: .sm) { edit() }
/// }
///
/// OuroCard("Weeknight dinners", description: "12 recipes", size: .sm, onPress: { open() }, media: {
///     CoverArt().aspectRatio(4 / 3, contentMode: .fill)
/// })
/// ```
///
/// `media` runs edge to edge across an outlined card's top, inside its corners, and is a rounded picture of its own on
/// a plain card. `onPress` is web's `href`: the whole card is one button, which VoiceOver names by its title and
/// description, and a press shrinks it to core's press scale and shades it, as web's linked card does. A pressable
/// card's action and footer are drawn but take no taps of their own; put a control that needs one beside the card.
///
/// The title is a heading for VoiceOver. Use ``OuroItem`` for a compact row in a list, and a plain stack when the group
/// needs no surface.
public struct OuroCard<Content: View, Action: View, Footer: View>: View {
    let title: String?
    let description: String?
    let variant: OuroCardVariant
    let size: OuroCardSize
    let media: AnyView?
    let onPress: (@MainActor () -> Void)?
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
        onPress: (@MainActor () -> Void)?,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action,
        @ViewBuilder footer: () -> Footer
    ) {
        self.init(title, description: description, variant: variant, size: size, onPress: onPress, media: nil,
                  content: content(), action: action(), footer: footer())
    }

    /// A card with a body, an action beside its title and a footer.
    public init(
        _ title: String? = nil,
        description: String? = nil,
        variant: OuroCardVariant = OuroCardMetrics.defaultVariant,
        size: OuroCardSize = OuroCardMetrics.defaultSize,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action,
        @ViewBuilder footer: () -> Footer
    ) {
        self.init(title, description: description, variant: variant, size: size, onPress: nil, content: content, action: action, footer: footer)
    }

    /// A card with a picture across its top.
    public init<Media: View>(
        _ title: String? = nil,
        description: String? = nil,
        variant: OuroCardVariant = OuroCardMetrics.defaultVariant,
        size: OuroCardSize = OuroCardMetrics.defaultSize,
        onPress: (@MainActor () -> Void)? = nil,
        @ViewBuilder media: () -> Media,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action,
        @ViewBuilder footer: () -> Footer
    ) {
        self.init(title, description: description, variant: variant, size: size, onPress: onPress, media: AnyView(media()),
                  content: content(), action: action(), footer: footer())
    }

    private init(_ title: String?, description: String?, variant: OuroCardVariant, size: OuroCardSize,
                 onPress: (@MainActor () -> Void)?, media: AnyView?, content: Content, action: Action, footer: Footer) {
        self.title = title
        self.description = description
        self.variant = variant
        self.size = size
        self.onPress = onPress
        self.media = media
        self.content = content
        self.action = action
        self.footer = footer
    }

    public var body: some View {
        let palette = OuroCardPalette(variant: variant, style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        let shape = RoundedRectangle(cornerRadius: theme.radius(OuroCardMetrics.radius), style: .continuous)
        if let onPress {
            Button(action: onPress) { surface(palette, shape: shape) }
                .buttonStyle(OuroCardPress(shape: shape, tint: Color(palette.title)))
                .accessibilityElement(children: .combine)
        } else {
            surface(palette, shape: shape)
                .accessibilityElement(children: .contain)
        }
    }

    private func surface(_ palette: OuroCardPalette, shape: RoundedRectangle) -> some View {
        let padding = OuroCardMetrics.padding(size: size, variant: variant)
        return VStack(alignment: .leading, spacing: 0) {
            if let media {
                media
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: variant == .plain ? theme.radius(OuroCardMetrics.plainMediaRadius(size: size)) : 0, style: .continuous))
                    .accessibilityHidden(title != nil)
            }
            VStack(alignment: .leading, spacing: OuroCardMetrics.spacing(size: size)) {
                header(palette)
                if Content.self != EmptyView.self {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if Footer.self != EmptyView.self { footer }
            }
            .padding(.horizontal, padding)
            .padding(.bottom, padding)
            .padding(.top, media == nil ? padding : OuroCardMetrics.mediaGap(size: size, variant: variant))
        }
        .foregroundStyle(Color(palette.title))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if let fill = palette.fill { shape.fill(Color(fill)) }
        }
        // An outlined card's media runs to its edge, inside its corners.
        .modifier(OuroCardMediaClip(shape: shape, clips: variant == .outline && media != nil))
        .overlay {
            if let border = palette.border {
                shape.strokeBorder(Color(border), lineWidth: OuroButtonMetrics.outlineWidth(contrast: contrast))
            }
        }
        .contentShape(shape)
    }

    @ViewBuilder private func header(_ palette: OuroCardPalette) -> some View {
        let words = VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.ouroHeading(.headline, weight: 600, in: theme))
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
        onPress: (@MainActor () -> Void)?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, description: description, variant: variant, size: size, onPress: onPress, content: content, action: { EmptyView() }, footer: { EmptyView() })
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
        self.init(title, description: description, variant: variant, size: size, onPress: nil, content: content)
    }
}

extension OuroCard where Content == EmptyView, Action == EmptyView, Footer == EmptyView {
    /// A picture with its title and description under it, such as a cookbook in a grid: web's
    /// `<Card href=… title=… description=… media={…} />`. Pass `media:` by its label: a trailing closure here reads
    /// as a body.
    public init<Media: View>(
        _ title: String,
        description: String? = nil,
        variant: OuroCardVariant = OuroCardMetrics.defaultVariant,
        size: OuroCardSize = OuroCardMetrics.defaultSize,
        onPress: (@MainActor () -> Void)? = nil,
        @ViewBuilder media: () -> Media
    ) {
        self.init(title, description: description, variant: variant, size: size, onPress: onPress, media: media,
                  content: { EmptyView() }, action: { EmptyView() }, footer: { EmptyView() })
    }
}

extension OuroCard where Footer == EmptyView {
    /// A card with a body and an action beside its title.
    public init(
        _ title: String? = nil,
        description: String? = nil,
        variant: OuroCardVariant = OuroCardMetrics.defaultVariant,
        size: OuroCardSize = OuroCardMetrics.defaultSize,
        onPress: (@MainActor () -> Void)?,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) {
        self.init(title, description: description, variant: variant, size: size, onPress: onPress, content: content, action: action, footer: { EmptyView() })
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
        self.init(title, description: description, variant: variant, size: size, onPress: nil, content: content, action: action)
    }
}

/// A pressable card's press: core's press scale on the press springs, and web's 6% tint on the press shade's curve (`OuroMotion.pressShadeStep`).
private struct OuroCardPress: ButtonStyle {
    let shape: RoundedRectangle
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .overlay {
                shape.fill(tint.opacity(pressed ? OuroCardMetrics.pressTint : 0))
                    .allowsHitTesting(false)
                    .animation(OuroMotion.pressShadeStep(reduceMotion: reduceMotion).animation, value: pressed)
            }
            .scaleEffect(OuroMotion.pressScale(isPressed: pressed, reduceMotion: reduceMotion))
            .animation(OuroMotion.animation(pressed ? .pressIn : .pressOut, reduceMotion: reduceMotion), value: pressed)
    }
}

/// Clips an outlined card with media to its corners, and leaves every other card unclipped, so a child's focus ring or
/// shadow can spill past it.
private struct OuroCardMediaClip: ViewModifier {
    let shape: RoundedRectangle
    let clips: Bool

    func body(content: Content) -> some View {
        if clips { content.clipShape(shape) } else { content }
    }
}
