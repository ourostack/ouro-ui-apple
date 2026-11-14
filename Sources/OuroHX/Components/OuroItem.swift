public import SwiftUI

/// A row's frame, as on web: `plain` has none, for rows in an ``OuroItemGroup``; `outline` is a bordered box for a row
/// on its own.
public enum OuroItemVariant: String, CaseIterable, Sendable { case plain, outline }

/// A row's height, as on web: `md` has 12 points above and below its words, `sm` 8, for dense lists.
public enum OuroItemSize: String, CaseIterable, Sendable { case md, sm }

/// The size of a row's leading media, as on web: `icon` is a 40-point tile with a symbol in it, `sm` a 40-point
/// picture, `md` 64 and `lg` 112.
public enum OuroItemMediaSize: String, CaseIterable, Sendable { case icon, sm, md, lg }

/// A group's frame, as on web: `divided` draws a line between rows, `outline` frames them in a bordered box, and
/// `plain` has neither.
public enum OuroItemGroupVariant: String, CaseIterable, Sendable { case divided, outline, plain }

/// The resolved colours of a row as seen: its title and description read at 5:1 on the page (7:1 under increased
/// contrast), and so does an icon tile's symbol on its tile; core claim `contrast.text`.
public struct OuroItemPalette: Sendable {
    public var title: Color.Resolved
    public var description: Color.Resolved
    /// The `icon` media tile and the symbol on it.
    public var iconFill: Color.Resolved
    public var icon: Color.Resolved
    /// The edge of an `outline` row or group, and the line between a group's rows: 3:1 under increased contrast.
    public var line: Color.Resolved
    /// What the words sit on: the page.
    public var surface: Color.Resolved

    public init(style: OuroHXStyle) {
        let c = style.colors
        let page = OuroInk.r(c.background)
        surface = page
        title = OuroInk.readable(OuroInk.r(c.foreground), on: page, style)
        description = OuroInk.readable(OuroInk.r(c.mutedForeground), on: page, style)
        let tile = OuroInk.r(c.muted)
        iconFill = tile
        icon = OuroInk.readable(OuroInk.r(c.mutedForeground), on: tile, style)
        line = OuroColor.push(OuroInk.r(c.border), against: page, to: style.contrast == .increased ? OuroColor.increasedLineContrast : 1)
    }
}

/// Metrics every ``OuroItem`` and ``OuroItemGroup`` share, as data.
public enum OuroItemMetrics {
    public static let defaultVariant = OuroItemVariant.plain
    public static let defaultSize = OuroItemSize.md
    public static let defaultMediaSize = OuroItemMediaSize.sm
    public static let defaultGroupVariant = OuroItemGroupVariant.divided
    /// No line limit on the title or the description at any size (core claim `text.reflows`).
    public static let titleLineLimit: Int? = nil
    public static let descriptionLineLimit: Int? = nil
    /// A row someone presses is at least 44 points tall, web's `pointer-coarse:min-h-11` (core claim `target.size`).
    public static let pressableMinimumHeight: CGFloat = 44
    /// Web's `rounded-xl` for an `outline` row or group.
    public static let radius = OuroRadius.xl
    /// Web's `px-4` inside an `outline` row or group.
    public static let outlineInset: CGFloat = 16
    /// Web's `gap-x-4` between the media, the words and the actions.
    public static let spacing: CGFloat = 16

    /// Web's `py-3` and `py-2`.
    public static func verticalPadding(_ size: OuroItemSize) -> CGFloat { size == .md ? 12 : 8 }

    /// Web's `size-10`, `size-16` and `size-28`.
    public static func mediaSide(_ size: OuroItemMediaSize) -> CGFloat {
        switch size {
        case .icon, .sm: 40
        case .md: 64
        case .lg: 112
        }
    }

    /// Web's `rounded-lg` for an icon tile and the larger pictures, `rounded-md` for a small one.
    public static func mediaRadius(_ size: OuroItemMediaSize) -> OuroRadius { size == .sm ? .md : .lg }

    /// Whether the actions go under the words rather than after them: at the accessibility sizes, as web's
    /// `stackBelow`, so the title has the width and wraps less.
    public static func stacksActions(at size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }

    /// Whether the media goes above the words: a picture does at the accessibility sizes, as web's `mediaAbove`; an
    /// icon tile stays beside them.
    public static func liftsMedia(_ media: OuroItemMediaSize, at size: DynamicTypeSize) -> Bool {
        media != .icon && size.isAccessibilitySize
    }
}

/// Ouro HX's row: a title, a description, leading media and trailing actions, web's `Item`. Put rows in an
/// ``OuroItemGroup``, which makes them a list.
///
/// ```swift
/// OuroItemGroup("Recipes") {
///     OuroItem("Braised short ribs", description: "3 hours, serves six", systemImage: "flame") {
///         OuroBadge("New", tone: .primary, variant: .soft)
///     }
///     OuroItem("Lemon orzo", description: "25 minutes") { open(orzo) }
/// }
/// ```
///
/// A row with an `onPress` closure is one button for VoiceOver, named by its title, and at least 44 points tall; its
/// actions stay their own controls beside it. The media is decorative when it is an icon.
public struct OuroItem<Media: View, Actions: View>: View {
    let title: String
    let description: String?
    let variant: OuroItemVariant
    let size: OuroItemSize
    let mediaSize: OuroItemMediaSize
    let onPress: (() -> Void)?
    let media: Media
    let actions: Actions
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        _ title: String,
        description: String? = nil,
        variant: OuroItemVariant = OuroItemMetrics.defaultVariant,
        size: OuroItemSize = OuroItemMetrics.defaultSize,
        mediaSize: OuroItemMediaSize = OuroItemMetrics.defaultMediaSize,
        onPress: (() -> Void)? = nil,
        @ViewBuilder media: () -> Media,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.description = description
        self.variant = variant
        self.size = size
        self.mediaSize = mediaSize
        self.onPress = onPress
        self.media = media()
        self.actions = actions()
    }

    private var hasMedia: Bool { Media.self != EmptyView.self }
    private var hasActions: Bool { Actions.self != EmptyView.self }

    public var body: some View {
        let style = OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast)
        let palette = OuroItemPalette(style: style)
        let shape = RoundedRectangle(cornerRadius: theme.radius(OuroItemMetrics.radius), style: .continuous)
        let lifted = hasMedia && OuroItemMetrics.liftsMedia(mediaSize, at: typeSize)
        let stacked = hasActions && OuroItemMetrics.stacksActions(at: typeSize)
        VStack(alignment: .leading, spacing: 8) {
            if lifted { mediaView(palette, lifted: true) }
            HStack(alignment: description == nil ? .center : .top, spacing: OuroItemMetrics.spacing) {
                if hasMedia && !lifted { mediaView(palette, lifted: false) }
                VStack(alignment: .leading, spacing: 8) {
                    pressable(words(palette))
                    if stacked { actionsView }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if hasActions && !stacked { actionsView }
            }
        }
        .padding(.vertical, OuroItemMetrics.verticalPadding(size))
        .padding(.horizontal, variant == .outline ? OuroItemMetrics.outlineInset : 0)
        .frame(minHeight: onPress == nil ? nil : OuroItemMetrics.pressableMinimumHeight)
        .overlay {
            if variant == .outline {
                shape.strokeBorder(Color(palette.line), lineWidth: OuroButtonMetrics.outlineWidth(contrast: contrast))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func words(_ palette: OuroItemPalette) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Color(palette.title))
                .lineLimit(OuroItemMetrics.titleLineLimit)
                .fixedSize(horizontal: false, vertical: true)
            if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Color(palette.description))
                    .lineLimit(OuroItemMetrics.descriptionLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The words are the row's one button when it has an `onPress`, as web's stretched link: VoiceOver reads the
    /// title and the description and presses the row, while the actions stay their own controls.
    @ViewBuilder private func pressable(_ words: some View) -> some View {
        if let onPress {
            Button(action: onPress) {
                words
                    .frame(minHeight: OuroItemMetrics.pressableMinimumHeight)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
        } else {
            words.accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func mediaView(_ palette: OuroItemPalette, lifted: Bool) -> some View {
        let side = OuroItemMetrics.mediaSide(mediaSize)
        let shape = RoundedRectangle(cornerRadius: theme.radius(OuroItemMetrics.mediaRadius(mediaSize)), style: .continuous)
        if mediaSize == .icon {
            media
                .font(.title3)
                .foregroundStyle(Color(palette.icon))
                .frame(width: side, height: side)
                .background(shape.fill(Color(palette.iconFill)))
                .accessibilityHidden(true)
        } else if lifted {
            media
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(shape)
        } else {
            media
                .frame(width: side, height: side)
                .clipShape(shape)
        }
    }

    private var actionsView: some View {
        HStack(spacing: 8) { actions }
    }
}

extension OuroItem where Media == EmptyView, Actions == EmptyView {
    /// A row with a title and a description.
    public init(
        _ title: String,
        description: String? = nil,
        variant: OuroItemVariant = OuroItemMetrics.defaultVariant,
        size: OuroItemSize = OuroItemMetrics.defaultSize,
        onPress: (() -> Void)? = nil
    ) {
        self.init(title, description: description, variant: variant, size: size, onPress: onPress, media: { EmptyView() }, actions: { EmptyView() })
    }
}

extension OuroItem where Media == EmptyView {
    /// A row with trailing actions and no media.
    public init(
        _ title: String,
        description: String? = nil,
        variant: OuroItemVariant = OuroItemMetrics.defaultVariant,
        size: OuroItemSize = OuroItemMetrics.defaultSize,
        onPress: (() -> Void)? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.init(title, description: description, variant: variant, size: size, onPress: onPress, media: { EmptyView() }, actions: actions)
    }
}

extension OuroItem where Media == Image {
    /// A row led by an SF Symbol in an icon tile.
    public init(
        _ title: String,
        description: String? = nil,
        systemImage: String,
        variant: OuroItemVariant = OuroItemMetrics.defaultVariant,
        size: OuroItemSize = OuroItemMetrics.defaultSize,
        onPress: (() -> Void)? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.init(title, description: description, variant: variant, size: size, mediaSize: .icon, onPress: onPress, media: { Image(systemName: systemImage) }, actions: actions)
    }
}

extension OuroItem where Media == Image, Actions == EmptyView {
    /// A row led by an SF Symbol in an icon tile, with no actions.
    public init(
        _ title: String,
        description: String? = nil,
        systemImage: String,
        variant: OuroItemVariant = OuroItemMetrics.defaultVariant,
        size: OuroItemSize = OuroItemMetrics.defaultSize,
        onPress: (() -> Void)? = nil
    ) {
        self.init(title, description: description, variant: variant, size: size, mediaSize: .icon, onPress: onPress, media: { Image(systemName: systemImage) }, actions: { EmptyView() })
    }
}

/// A list of ``OuroItem`` rows, web's `ItemGroup`: a label above that names the list, and lines between the rows
/// (`divided`), a bordered box around them (`outline`) or neither (`plain`).
///
/// The label is a heading for VoiceOver, and the rows are one container it names.
public struct OuroItemGroup<Content: View>: View {
    let label: String?
    let variant: OuroItemGroupVariant
    let content: Content
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    public init(_ label: String? = nil, variant: OuroItemGroupVariant = OuroItemMetrics.defaultGroupVariant, @ViewBuilder content: () -> Content) {
        self.label = label
        self.variant = variant
        self.content = content()
    }

    public var body: some View {
        let palette = OuroItemPalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        let width = OuroButtonMetrics.outlineWidth(contrast: contrast)
        let shape = RoundedRectangle(cornerRadius: theme.radius(OuroItemMetrics.radius), style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            if let label {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(palette.description))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        row
                        if variant != .plain, index < rows.count - 1 {
                            Rectangle()
                                .fill(Color(palette.line))
                                .frame(height: width)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .padding(.horizontal, variant == .outline ? OuroItemMetrics.outlineInset : 0)
            .overlay {
                if variant == .outline { shape.strokeBorder(Color(palette.line), lineWidth: width) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(label ?? ""))
        }
    }
}
