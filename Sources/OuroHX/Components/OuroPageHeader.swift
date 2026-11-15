public import SwiftUI

/// How large a page header's title is, as on web: `md` for an app page, `lg` for a landing or profile page.
public enum OuroPageHeaderSize: String, CaseIterable, Sendable { case md, lg }

/// The resolved colours of a page header as seen: title, eyebrow and description read at 5:1 on the page (7:1 under
/// increased contrast); core claim `contrast.text`.
public struct OuroPageHeaderPalette: Sendable {
    public var title: Color.Resolved
    public var eyebrow: Color.Resolved
    public var description: Color.Resolved
    /// The divider under the header: 3:1 under increased contrast, as other lines are.
    public var line: Color.Resolved
    public var surface: Color.Resolved

    public init(style: OuroHXStyle) {
        let c = style.colors
        let page = OuroInk.r(c.background)
        surface = page
        title = OuroInk.readable(OuroInk.r(c.foreground), on: page, style)
        eyebrow = OuroInk.readable(OuroInk.r(c.primary), on: page, style)
        description = OuroInk.readable(OuroInk.r(c.mutedForeground), on: page, style)
        line = OuroColor.push(OuroInk.r(c.border), against: page, to: style.contrast == .increased ? OuroColor.increasedLineContrast : 1)
    }
}

/// Metrics every ``OuroPageHeader`` shares, as data.
public enum OuroPageHeaderMetrics {
    public static let defaultSize = OuroPageHeaderSize.md
    public static let defaultLevel = 1
    /// No line limit on the title or the description at any size (core claim `text.reflows`).
    public static let titleLineLimit: Int? = nil
    /// Web's `gap-2` between the eyebrow, the title and the description, and `gap-4` to the actions and media.
    public static let spacing: CGFloat = 8
    public static let blockSpacing: CGFloat = 16
    /// Web's `rounded-xl` for the media, from the theme.
    public static let mediaRadius = OuroRadius.xl

    /// The title's text style: `largeTitle` for a page's `lg` title, `title` for `md`, `title2` for a section (level 2).
    public static func titleFont(size: OuroPageHeaderSize, level: Int) -> Font {
        titleFont(size: size, level: level, in: OuroTokens.pearl)
    }

    /// The title's font in a theme's heading font (``OuroTheme/heading``), bold, at the same text styles.
    public static func titleFont(size: OuroPageHeaderSize, level: Int, in theme: OuroTheme) -> Font {
        let style: Font.TextStyle = level == 2 ? .title2 : size == .lg ? .largeTitle : .title
        return .ouroHeading(style, weight: 700, in: theme)
    }

    /// VoiceOver's heading level for the title: 1 for a page, 2 for a section, as web's `<h1>` and `<h2>`.
    public static func headingLevel(_ level: Int) -> AccessibilityHeadingLevel { level == 2 ? .h2 : .h1 }

    /// Whether the actions go under the title rather than beside it: at the accessibility sizes always, and otherwise
    /// when they don't fit beside it (SwiftUI's `ViewThatFits`), as web moves them under the title on phones.
    public static func stacksActions(at size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }
}

/// Ouro HX's page header: the top of a page or a section, with its title, a line above it that says where it sits
/// (`eyebrow`), a sentence under it, the page's actions beside it and an image above it, web's `PageHeader`.
///
/// ```swift
/// OuroPageHeader("Lemon orzo", eyebrow: "Weeknight", description: "Bright, quick and one pot.") {
///     OuroButton("Cook", systemImage: "flame") { cook() }
/// }
/// OuroPageHeader("Shopping list", level: 2, divider: true)
/// ```
///
/// The title is a heading (level 1, or 2 for a section) for VoiceOver's rotor. The actions sit at the end of the
/// title where they fit, and go under it where they don't, so the title keeps the width at large text sizes.
public struct OuroPageHeader<Actions: View, Media: View, Content: View>: View {
    let title: String
    let eyebrow: String?
    let description: String?
    let level: Int
    let size: OuroPageHeaderSize
    let divider: Bool
    let actions: Actions
    let media: Media
    let content: Content
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        _ title: String,
        eyebrow: String? = nil,
        description: String? = nil,
        level: Int = OuroPageHeaderMetrics.defaultLevel,
        size: OuroPageHeaderSize = OuroPageHeaderMetrics.defaultSize,
        divider: Bool = false,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder media: () -> Media,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.description = description
        self.level = level == 2 ? 2 : 1
        self.size = size
        self.divider = divider
        self.actions = actions()
        self.media = media()
        self.content = content()
    }

    private var hasActions: Bool { Actions.self != EmptyView.self }
    private var hasMedia: Bool { Media.self != EmptyView.self }
    private var hasContent: Bool { Content.self != EmptyView.self }

    public var body: some View {
        let palette = OuroPageHeaderPalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        VStack(alignment: .leading, spacing: OuroPageHeaderMetrics.blockSpacing) {
            if hasMedia {
                media
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius(OuroPageHeaderMetrics.mediaRadius), style: .continuous))
            }
            if hasActions && !OuroPageHeaderMetrics.stacksActions(at: typeSize) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: OuroPageHeaderMetrics.blockSpacing) {
                        words(palette)
                        actionsRow
                    }
                    stacked(palette)
                }
            } else {
                stacked(palette)
            }
            if divider {
                Rectangle()
                    .fill(Color(palette.line))
                    .frame(height: OuroButtonMetrics.outlineWidth(contrast: contrast))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func stacked(_ palette: OuroPageHeaderPalette) -> some View {
        VStack(alignment: .leading, spacing: OuroPageHeaderMetrics.blockSpacing) {
            words(palette)
            if hasActions { actionsRow }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 8) { actions }
    }

    private func words(_ palette: OuroPageHeaderPalette) -> some View {
        VStack(alignment: .leading, spacing: OuroPageHeaderMetrics.spacing) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(palette.eyebrow))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(title)
                .font(OuroPageHeaderMetrics.titleFont(size: size, level: level, in: theme))
                .foregroundStyle(Color(palette.title))
                .lineLimit(OuroPageHeaderMetrics.titleLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(OuroPageHeaderMetrics.headingLevel(level))
            if let description {
                Text(description)
                    .font(.body)
                    .foregroundStyle(Color(palette.description))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if hasContent { content }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension OuroPageHeader where Actions == EmptyView, Media == EmptyView, Content == EmptyView {
    /// A header with a title and its words, and no actions.
    public init(_ title: String, eyebrow: String? = nil, description: String? = nil, level: Int = OuroPageHeaderMetrics.defaultLevel, size: OuroPageHeaderSize = OuroPageHeaderMetrics.defaultSize, divider: Bool = false) {
        self.init(title, eyebrow: eyebrow, description: description, level: level, size: size, divider: divider, actions: { EmptyView() }, media: { EmptyView() }, content: { EmptyView() })
    }
}

extension OuroPageHeader where Media == EmptyView, Content == EmptyView {
    /// A header with the page's actions beside its title.
    public init(_ title: String, eyebrow: String? = nil, description: String? = nil, level: Int = OuroPageHeaderMetrics.defaultLevel, size: OuroPageHeaderSize = OuroPageHeaderMetrics.defaultSize, divider: Bool = false, @ViewBuilder actions: () -> Actions) {
        self.init(title, eyebrow: eyebrow, description: description, level: level, size: size, divider: divider, actions: actions, media: { EmptyView() }, content: { EmptyView() })
    }
}

extension OuroPageHeader where Media == EmptyView {
    /// A header with actions, and more under the description, such as badges or a byline.
    public init(_ title: String, eyebrow: String? = nil, description: String? = nil, level: Int = OuroPageHeaderMetrics.defaultLevel, size: OuroPageHeaderSize = OuroPageHeaderMetrics.defaultSize, divider: Bool = false, @ViewBuilder actions: () -> Actions, @ViewBuilder content: () -> Content) {
        self.init(title, eyebrow: eyebrow, description: description, level: level, size: size, divider: divider, actions: actions, media: { EmptyView() }, content: content)
    }
}
