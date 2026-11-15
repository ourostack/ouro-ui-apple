public import SwiftUI

/// An avatar's size, as on web: 24, 32, 40, 48, 64, 72 and 112 points. Web's `2xl` and `3xl` are `xxl` and `xxxl`.
public enum OuroAvatarSize: String, CaseIterable, Sendable { case xs, sm, md, lg, xl, xxl, xxxl }

/// An avatar's shape, as on web: `circle` for a person, `square` for a team, a channel, an app or a bot (with a
/// second edge behind it, and no presence), `agent` for an AI agent (a less-rounded tile).
public enum OuroAvatarShape: String, CaseIterable, Sendable { case circle, square, agent }

/// Where the initials' colours come from, as on web: `colorful` picks one of the theme's eight avatar hues from the
/// name (or `idForColor`), the same hue web picks; `brand` is the theme's primary; `neutral` the secondary surface.
public enum OuroAvatarColor: String, CaseIterable, Sendable { case colorful, brand, neutral }

/// A person's presence, as on web: each state has its own glyph as well as its tone, so it never relies on colour.
public enum OuroAvatarPresence: String, CaseIterable, Sendable {
    case available, busy, away, doNotDisturb, offline, outOfOffice

    /// The tone web gives each state.
    public var tone: OuroTone {
        switch self {
        case .available: .success
        case .busy, .doNotDisturb: .destructive
        case .away: .warning
        case .offline: .secondary
        case .outOfOffice: .primary
        }
    }

    /// The glyph, from 40 points up; below that the dot is plain, as on web.
    public var systemImage: String {
        switch self {
        case .available: "checkmark.circle.fill"
        case .busy: "circle.fill"
        case .away: "clock.fill"
        case .doNotDisturb: "minus.circle.fill"
        case .offline: "xmark.circle"
        case .outOfOffice: "arrow.left.circle.fill"
        }
    }
}

/// The resolved colours of an avatar's initials and surface: the initials read at 5:1 on the surface (7:1 under
/// increased contrast) in every theme and hue; core claim `contrast.text`.
public struct OuroAvatarPalette: Sendable {
    public var label: Color.Resolved
    public var fill: Color.Resolved
    /// The second edge behind a `square` avatar.
    public var edge: Color.Resolved

    /// `hue` is 0 to 7, one of the theme's avatar colours; it is used only when `color` is `colorful`.
    public init(color: OuroAvatarColor, hue: Int, style: OuroHXStyle) {
        let c = style.colors
        let page = OuroInk.r(c.background)
        let ink = OuroInk.r(c.foreground)
        let base: Color.Resolved? = switch color {
        case .colorful: OuroInk.r([c.avatar1, c.avatar2, c.avatar3, c.avatar4, c.avatar5, c.avatar6, c.avatar7, c.avatar8][((hue % 8) + 8) % 8])
        case .brand: OuroInk.r(c.primary)
        case .neutral: nil
        }
        if let base {
            fill = OuroInk.tint(base, over: page, 0.18)
            label = OuroInk.readable(OuroColor.mix(ink, base, 0.7), on: fill, style)
        } else {
            fill = OuroInk.r(c.secondary)
            label = OuroInk.readable(OuroInk.r(c.secondaryForeground), on: fill, style)
        }
        edge = OuroColor.mix(page, ink, style.scheme == .dark ? 0.3 : 0.2)
    }
}

/// Metrics every ``OuroAvatar`` shares, as data.
public enum OuroAvatarMetrics {
    public static let defaultSize = OuroAvatarSize.md
    public static let defaultShape = OuroAvatarShape.circle
    public static let defaultColor = OuroAvatarColor.colorful

    /// Web's `size-6` to `size-28`.
    public static func side(_ size: OuroAvatarSize) -> CGFloat {
        switch size {
        case .xs: 24
        case .sm: 32
        case .md: 40
        case .lg: 48
        case .xl: 64
        case .xxl: 72
        case .xxxl: 112
        }
    }

    /// The initials' point size: web's `text-[0.625rem]` to `text-4xl`. Fixed, as the avatar is; the name is what
    /// VoiceOver reads, so the initials are drawn, not spoken (core claim `name.spoken`).
    public static func fontSize(_ size: OuroAvatarSize) -> CGFloat {
        switch size {
        case .xs: 10
        case .sm: 12
        case .md: 14
        case .lg: 16
        case .xl: 20
        case .xxl: 24
        case .xxxl: 36
        }
    }

    /// How far the initials may shrink to fit the avatar at their default size; at larger text sizes they first grow
    /// with Dynamic Type, then shrink back into the avatar, which keeps its size.
    public static let initialsMinimumScale: CGFloat = 0.5

    /// The presence dot's side: web's 8 to 31 pixels.
    public static func presenceSide(_ size: OuroAvatarSize) -> CGFloat {
        switch size {
        case .xs: 8
        case .sm: 9
        case .md: 11
        case .lg: 13
        case .xl: 18
        case .xxl: 20
        case .xxxl: 31
        }
    }

    /// Below 40 points a glyph can't be read, so the dot is plain; from 40 up it carries its glyph, as on web.
    public static func presenceHasGlyph(_ size: OuroAvatarSize) -> Bool { side(size) >= 40 }

    /// The corner radius: a circle for a person, a squircle at a fifth of the side for a square, a less-rounded
    /// tile for an agent.
    public static func radius(_ shape: OuroAvatarShape, side: CGFloat) -> CGFloat {
        switch shape {
        case .circle: side / 2
        case .square: side * 0.3
        case .agent: side * 0.22
        }
    }

    /// The first letters of the first and last words, as web's `initialsOf`: "Ana Lind" is "AL", "Rachel" is "R".
    public static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        let first = { (w: Substring?) in w?.first.map { String($0).uppercased() } ?? "" }
        return first(words.first) + (words.count > 1 ? first(words.last) : "")
    }

    /// One of the eight hues for a key, the same index web's `hueOf` picks on the server and in the browser: an FNV
    /// hash over the trimmed, lowercased key's code points, mixed by MurmurHash3's finalizer and scaled from its top
    /// bits, so the same person has the same colour on web and on Apple.
    public static func hue(_ key: String) -> Int {
        var hash: UInt32 = 0x811c_9dc5
        for scalar in key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().unicodeScalars {
            hash ^= scalar.value
            hash = hash &* 0x0100_0193
        }
        hash ^= hash >> 16
        hash = hash &* 0x85eb_ca6b
        hash ^= hash >> 13
        hash = hash &* 0xc2b2_ae35
        hash ^= hash >> 16
        return Int((UInt64(hash) * 8) >> 32)
    }

    /// What VoiceOver says: the name (or `alt`), then the presence's words, as web's "Ana Lind, Busy".
    public static func spokenName(name: String?, alt: String?, presenceLabel: String?, loadingLabel: String) -> String {
        let who = alt ?? name ?? loadingLabel
        guard let presenceLabel, !presenceLabel.isEmpty else { return who }
        return who.isEmpty ? presenceLabel : "\(who), \(presenceLabel)"
    }
}

/// Ouro HX's avatar: a person's or a thing's picture, or their initials on a colour that is theirs, web's `Avatar`.
///
/// ```swift
/// OuroAvatar(name: "Ana Lind")
/// OuroAvatar(name: "Ana Lind", url: chef.photoURL, size: .xl, presence: .busy, presenceLabel: "Cooking")
/// OuroAvatar(name: "Spoonjoy", systemImage: "fork.knife", shape: .square, color: .brand)
/// ```
///
/// VoiceOver reads it as an image named by `name` (or `alt`), then the presence's words. Pass `alt: ""` when the
/// name is written beside it, so it isn't read twice. A `nil` name shimmers in the avatar's shape while it loads.
public struct OuroAvatar: View {
    let name: String?
    let url: URL?
    let image: Image?
    let initials: String?
    let systemImage: String?
    let alt: String?
    let shape: OuroAvatarShape
    let color: OuroAvatarColor
    let idForColor: String?
    let size: OuroAvatarSize
    let presence: OuroAvatarPresence?
    let presenceLabel: String?
    let loadingLabel: String
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    /// The initials follow Dynamic Type, then shrink to fit the avatar, which keeps its size as web's does.
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1

    public init(
        name: String?,
        url: URL? = nil,
        image: Image? = nil,
        initials: String? = nil,
        systemImage: String? = nil,
        alt: String? = nil,
        shape: OuroAvatarShape = OuroAvatarMetrics.defaultShape,
        color: OuroAvatarColor = OuroAvatarMetrics.defaultColor,
        idForColor: String? = nil,
        size: OuroAvatarSize = OuroAvatarMetrics.defaultSize,
        presence: OuroAvatarPresence? = nil,
        presenceLabel: String? = nil,
        loadingLabel: String = "Name loading"
    ) {
        self.name = name
        self.url = url
        self.image = image
        self.initials = initials
        self.systemImage = systemImage
        self.alt = alt
        self.shape = shape
        self.color = color
        self.idForColor = idForColor
        self.size = size
        self.presence = shape == .square ? nil : presence
        self.presenceLabel = shape == .square ? nil : presenceLabel
        self.loadingLabel = loadingLabel
    }

    public var body: some View {
        let style = OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast)
        let palette = OuroAvatarPalette(color: color, hue: OuroAvatarMetrics.hue(idForColor ?? name ?? ""), style: style)
        let side = OuroAvatarMetrics.side(size)
        let tile = RoundedRectangle(cornerRadius: OuroAvatarMetrics.radius(shape, side: side), style: .continuous)
        ZStack(alignment: .bottomTrailing) {
            if shape == .square {
                tile.fill(Color(palette.edge))
                    .frame(width: side, height: side)
                    .offset(x: side * 0.07, y: -side * 0.07)
            }
            face(palette)
                .frame(width: side, height: side)
                .clipShape(tile)
            if let presence { dot(presence, style: style) }
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(OuroAvatarMetrics.spokenName(name: name, alt: alt, presenceLabel: presenceLabel, loadingLabel: loadingLabel)))
        .accessibilityAddTraits(.isImage)
        .accessibilityHidden(alt == "" && presence == nil)
    }

    @ViewBuilder private func face(_ palette: OuroAvatarPalette) -> some View {
        if name == nil {
            Rectangle().fill(Color(palette.fill)).opacity(0.6)
        } else if let image {
            image.resizable().scaledToFill()
        } else if let url {
            AsyncImage(url: url) { phase in
                if let picture = phase.image { picture.resizable().scaledToFill() } else { fallback(palette) }
            }
        } else {
            fallback(palette)
        }
    }

    private func fallback(_ palette: OuroAvatarPalette) -> some View {
        ZStack {
            Color(palette.fill)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: OuroAvatarMetrics.fontSize(size), weight: .semibold))
            } else {
                Text(initials ?? OuroAvatarMetrics.initials(name ?? ""))
                    .font(.system(size: OuroAvatarMetrics.fontSize(size) * typeScale, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(OuroAvatarMetrics.initialsMinimumScale / typeScale)
                    // Drawn, never read: the avatar is one image named by its person.
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Color(palette.label))
    }

    private func dot(_ presence: OuroAvatarPresence, style: OuroHXStyle) -> some View {
        let p = OuroButtonPalette(tone: presence.tone, variant: .solid, style: style)
        let d = OuroAvatarMetrics.presenceSide(size)
        return ZStack {
            Circle().fill(Color(OuroInk.r(style.colors.background)))
                .frame(width: d + 3, height: d + 3)
            if OuroAvatarMetrics.presenceHasGlyph(size) {
                Image(systemName: presence.systemImage)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color(p.fill ?? p.label))
                    .frame(width: d, height: d)
            } else {
                Circle().fill(Color(p.fill ?? p.label)).frame(width: d, height: d)
            }
        }
        .offset(x: d * 0.2, y: d * 0.2)
    }
}
