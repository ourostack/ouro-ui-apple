public import SwiftUI

/// A button's visual weight, as on web: `solid` for the screen's main action, `soft` for secondary actions,
/// `outline` for a quiet bordered control, `plain` for a borderless one, and `glass` for Liquid Glass (iOS 26 and
/// macOS 26; a material before them), the way Spoonjoy and Gatefold float actions over content.
public enum OuroButtonVariant: String, CaseIterable, Sendable { case solid, soft, outline, plain, glass }

/// A button's size, as on web. On a touch screen every size is at least 44 points tall (core claim `target.touch`);
/// with a pointer they step down to desktop density.
public enum OuroButtonSize: String, CaseIterable, Sendable {
    case sm, md, lg

    /// The smallest target a control may have on `input`: 44 points on a touch screen.
    public static func minimumTarget(on input: OuroInput) -> CGFloat { input == .touch ? 44 : 24 }

    /// The button's minimum pressable height: 44, 50 and 56 on a touch screen, 28, 32 and 40 with a pointer.
    public func minimumHeight(on input: OuroInput) -> CGFloat {
        minimumHeight(on: input, target: Self.minimumTarget(on: .touch))
    }

    /// The minimum pressable height when the touch target is `target` points, as inside an `.ouroSheet`
    /// (``OuroSheetMetrics/touchTarget``): never below it on a touch screen, and desktop density with a pointer.
    public func minimumHeight(on input: OuroInput, target: CGFloat) -> CGFloat {
        switch (self, input) {
        case (.sm, .touch): max(44, target)
        case (.md, .touch): max(50, target)
        case (.lg, .touch): max(56, target)
        case (.sm, .pointer): 28
        case (.md, .pointer): 32
        case (.lg, .pointer): 40
        }
    }

    /// The height the button is drawn at, which grows with the text: on a touch screen a small button is a 34-point
    /// capsule centred in its 44-point target, Apple's small-control proportion; the others are drawn at their full
    /// target, 50 and 56 points, the proportions of iOS 26's prominent buttons.
    public func visualHeight(on input: OuroInput, target: CGFloat) -> CGFloat {
        self == .sm && input == .touch ? 34 : minimumHeight(on: input, target: target)
    }

    /// Padding at the label's sides: generous, so a capsule's ends have room to round.
    public var horizontalPadding: CGFloat {
        switch self { case .sm: 14; case .md: 20; case .lg: 24 }
    }

    /// The padding a `variant` takes: none for `plain`, whose words sit on the layout margin as the system's borderless
    /// buttons' do (its target still reaches 44 points), the size's own otherwise.
    public func horizontalPadding(for variant: OuroButtonVariant) -> CGFloat { variant == .plain ? 0 : horizontalPadding }

    /// An icon beside the words, a step smaller than them so it never outweighs them.
    var iconFont: Font {
        switch self {
        case .sm: .footnote.weight(.semibold)
        case .md, .lg: .subheadline.weight(.semibold)
        }
    }

    /// Semibold, as Apple's prominent buttons are; a regular weight reads as a link rather than a control.
    var font: Font {
        switch self {
        case .sm: .subheadline.weight(.semibold)
        case .md, .lg: .body.weight(.semibold)
        }
    }
}

/// A button's outline: `pill`, a capsule, the default, as Apple's own buttons are from iOS 26 and Spoonjoy's and
/// Gatefold's are; or `rounded`, the theme's `lg` radius, web's look.
public enum OuroButtonShape: String, CaseIterable, Sendable { case rounded, pill }

/// The resolved colours of a button, for one tone, variant and theme as seen. `surface` is what the label sits on:
/// the fill, or the page (`background`) when the variant has none. Its label reads at 5:1 on it (7:1 under
/// increased contrast) in every theme; core claim `contrast.text`.
public struct OuroButtonPalette: Sendable {
    public var label: Color.Resolved
    public var fill: Color.Resolved?
    public var border: Color.Resolved?
    public var surface: Color.Resolved

    /// `isEnabled: false` gives the disabled look, the same for every tone and variant: a muted fill with an outline
    /// and a label still reading at the target, rather than web's half opacity, which Xcode's audit fails.
    public init(tone: OuroTone, variant: OuroButtonVariant, style: OuroHXStyle, isEnabled: Bool = true) {
        let c = style.colors
        guard isEnabled else {
            // Every variant looks the same disabled: a muted chip with an outline and a label that still reads. Some
            // themes' tones are close to their muted grey, so the outline and fill, not the colour alone, say it.
            let muted = OuroInk.r(c.muted)
            fill = muted
            surface = muted
            border = OuroColor.push(OuroInk.r(c.border), against: muted, to: style.contrast == .increased ? OuroColor.increasedLineContrast : OuroButtonMetrics.disabledOutlineContrast)
            label = OuroInk.readable(OuroInk.r(c.mutedForeground), on: muted, style)
            return
        }
        let background = OuroInk.r(c.background)
        let (toneFill, toneLabel) = tone.fill(c)
        let fill = OuroInk.r(toneFill)
        // Secondary's own colour is a pale fill, so as text it reads as the page's foreground.
        let toneText = tone == .secondary ? OuroInk.r(c.foreground) : fill
        switch variant {
        case .solid:
            // The label first; where even white or black falls short, the fill moves away from it.
            // Secondary's pale fill takes a step of the page's foreground, so solid reads stronger than soft.
            let base = tone == .secondary ? OuroInk.tint(OuroInk.r(c.foreground), over: fill, OuroButtonMetrics.secondarySolidStep(scheme: style.scheme)) : fill
            let text = OuroInk.readable(OuroInk.r(toneLabel), on: base, style)
            let shown = OuroColor.contrastRatio(text, base) >= OuroInk.target(style) ? base : OuroColor.push(base, against: text, to: OuroInk.target(style))
            self.fill = shown
            surface = shown
            label = text
            border = nil
        case .soft:
            // A little stronger in dark, where a faint tint over near-black reads as mud.
            let tinted = tone == .secondary ? fill : OuroInk.tint(fill, over: background, OuroButtonMetrics.softTint(scheme: style.scheme))
            self.fill = tinted
            surface = tinted
            label = OuroInk.readable(toneText, on: tinted, style)
            border = nil
        case .outline:
            self.fill = nil
            surface = background
            label = OuroInk.readable(toneText, on: background, style)
            // In its tone at 50% over the page, so an outline row reads as its tones; secondary keeps the border. Under
            // increased contrast, the full tone, raised to 3:1, so the line stays its colour rather than going grey.
            let increased = style.contrast == .increased
            // Secondary's is the page's foreground at 25%, a neutral that still reads beside the tones.
            let neutral = OuroInk.tint(OuroInk.r(c.foreground), over: background, OuroButtonMetrics.neutralOutlineTint)
            let line = tone == .secondary ? (increased ? OuroInk.r(c.border) : neutral) : (increased ? fill : OuroInk.tint(fill, over: background, OuroButtonMetrics.outlineTint))
            border = OuroColor.push(line, against: background, to: style.contrast == .increased ? OuroColor.increasedLineContrast : 1)
        case .plain:
            self.fill = nil
            surface = background
            label = OuroInk.readable(toneText, on: background, style)
            border = nil
        case .glass:
            // Glass shows the page through it, so the label is measured against the page.
            self.fill = nil
            surface = background
            label = OuroInk.readable(tone == .primary ? OuroInk.r(c.foreground) : toneText, on: background, style)
            border = nil
        }
    }
}

/// Metrics and motion every ``OuroButton`` shares, as data.
public enum OuroButtonMetrics {
    /// How strongly a disabled button's outline reads on its muted fill (3:1 under increased contrast): enough to show
    /// the chip where a theme's tone is close to its muted grey.
    public static let disabledOutlineContrast = 1.5

    /// Core's press scale while pressed, or none under Reduce Motion.
    public static func pressScale(isPressed: Bool, reduceMotion: Bool) -> Double {
        OuroMotion.pressScale(isPressed: isPressed, reduceMotion: reduceMotion)
    }

    /// A pill's end radius for a button `height` points tall: half of it, a capsule, at every text size, up to 44
    /// points, so a label wrapped onto several lines becomes a rounded rectangle rather than an oval.
    public static func pillRadius(height: CGFloat) -> CGFloat { min(height / 2, 44) }

    /// How much of its tone a soft fill washes over the page: 14% in light, 26% in dark, where less reads as mud.
    public static func softTint(scheme: ColorScheme) -> Double { scheme == .dark ? 0.26 : 0.14 }

    /// How much of its tone an outline is drawn with over the page.
    public static let outlineTint = 0.5
    /// An outline's width: a point, or two under increased contrast.
    public static func outlineWidth(contrast: ColorSchemeContrast) -> CGFloat { contrast == .increased ? 2 : 1 }
    /// How much of the page's foreground secondary's solid fill takes over its pale colour: more in dark, where the
    /// step reads smaller.
    public static func secondarySolidStep(scheme: ColorScheme) -> Double { scheme == .dark ? 0.12 : 0.07 }
    /// How much of the page's foreground secondary's outline is drawn with.
    public static let neutralOutlineTint = 0.25

}

/// Ouro HX's button look for any SwiftUI `Button`: `.buttonStyle(.ouro(.soft, tone: .destructive))`.
///
/// It keeps every size at least 44 points tall on a touch screen, lets its label wrap at large text sizes instead of
/// truncating, shrinks to core's press scale (not under Reduce Motion), and takes its colours from the theme.
public struct OuroButtonStyle: ButtonStyle {
    public var variant: OuroButtonVariant
    public var tone: OuroTone
    public var size: OuroButtonSize
    public var shape: OuroButtonShape
    public var fullWidth: Bool

    public init(_ variant: OuroButtonVariant = .solid, tone: OuroTone = .primary, size: OuroButtonSize = .md, shape: OuroButtonShape = .pill, fullWidth: Bool = false) {
        self.variant = variant
        self.tone = tone
        self.size = size
        self.shape = shape
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        ButtonBody(style: self, configuration: configuration)
    }

    /// The tone drawn for a button with `role`: a destructive role draws in the destructive tone unless a tone other
    /// than primary was asked for, so `Button("Delete", role: .destructive) {}.buttonStyle(.ouro())` reads as one.
    public func resolvedTone(for role: ButtonRole?) -> OuroTone {
        role == .destructive && tone == .primary ? .destructive : tone
    }

    private struct ButtonBody: View {
        let style: OuroButtonStyle
        let configuration: Configuration
        @Environment(\.ouroTheme) private var theme
        @Environment(\.colorScheme) private var scheme
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var environmentEnabled
        @Environment(\.ouroButtonLoading) private var loading
        @Environment(\.ouroTouchTarget) private var touchTarget
        /// A loading button is disabled but keeps its tone: it is busy, not unavailable.
        private var isEnabled: Bool { environmentEnabled || loading }
        @Environment(\.ouroButtonFillsWidth) private var fillsWidth
        @Environment(\.ouroButtonOwnsLabel) private var ownsLabel

        var body: some View {
            let palette = OuroButtonPalette(tone: style.resolvedTone(for: configuration.role), variant: style.variant, style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast), isEnabled: isEnabled)
            let pressed = configuration.isPressed
            let visual = style.size.visualHeight(on: .current, target: touchTarget)
            let pressable = style.size.minimumHeight(on: .current, target: touchTarget)
            // A pill is a capsule at every height, its ends half the height it is drawn (taller at large text sizes),
            // up to 44 points: a label wrapped onto several lines becomes a rounded rectangle, not an oval. Circular
            // ends, a true capsule: a continuous corner at half the height reads slightly square.
            let shape = style.shape == .pill ? AnyShape(PillShape()) : AnyShape(RoundedRectangle(cornerRadius: theme.radius(.lg), style: .continuous))
            configuration.label
                // Ouro's icon-and-words spacing on an OuroButton's own label only, so a plain `Button` styled
                // `.ouro()` keeps a label style set around it (`.iconOnly`, `.titleOnly`).
                .modifier(OuroLabelIfOwned(owned: ownsLabel, iconFont: style.size.iconFont))
                .font(style.size.font)
                .multilineTextAlignment(.center)
                // Wraps instead of truncating at every text size (core claim `text.reflows`).
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color(palette.label))
                .padding(.horizontal, style.size.horizontalPadding(for: style.variant))
                .padding(.vertical, 7)
                .frame(maxWidth: style.fullWidth || fillsWidth ? .infinity : nil, minHeight: visual)
                .frame(minWidth: OuroInput.current == .touch ? max(touchTarget, OuroButtonSize.minimumTarget(on: .touch)) : OuroButtonSize.minimumTarget(on: .pointer))
                .background { background(palette, shape: shape, pressed: pressed) }
                .modifier(GlassIfNeeded(enabled: style.variant == .glass, interactive: isEnabled, shape: shape))
                .scaleEffect(OuroButtonMetrics.pressScale(isPressed: pressed, reduceMotion: reduceMotion))
                // Springs both ways: a quick one as the finger lands, a softer one as it lifts, which picks up from
                // wherever the press had got to rather than restarting.
                .animation(OuroMotion.animation(pressed ? .pressIn : .pressOut, reduceMotion: reduceMotion), value: pressed)
                // The target reaches past a small capsule to the full 44 points, and the hit area is the whole of it.
                .padding(.vertical, max(0, (pressable - visual) / 2))
                .contentShape(Rectangle())
        }

        @ViewBuilder
        private func background(_ p: OuroButtonPalette, shape: AnyShape, pressed: Bool) -> some View {
            let layer = Color(p.label).opacity(pressed ? 0.12 : 0)
            let w = OuroButtonMetrics.outlineWidth(contrast: contrast)
            if let fill = p.fill {
                shape.fill(Color(fill)).overlay(shape.fill(layer)).overlay {
                    if let border = p.border { shape.stroke(Color(border), lineWidth: w).padding(w / 2) }
                }
            } else if let border = p.border {
                shape.stroke(Color(border), lineWidth: w).padding(w / 2).background(shape.fill(layer))
            } else {
                shape.fill(layer)
            }
        }
    }

    private struct GlassIfNeeded: ViewModifier {
        let enabled: Bool
        let interactive: Bool
        let shape: AnyShape

        func body(content: Content) -> some View {
            if !enabled {
                content
            } else if #available(iOS 26, macOS 26, visionOS 26, *) {
                content.glassEffect(.regular.interactive(interactive), in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        }
    }
}

extension EnvironmentValues {
    /// Set by ``OuroButton`` while `loading`, so its style keeps the tone rather than the disabled look.
    @Entry var ouroButtonLoading = false
    /// Set by ``OuroButton``, whose label takes Ouro's icon spacing; a plain `Button` keeps the label style around it.
    @Entry var ouroButtonOwnsLabel = false
}

private struct OuroLabelIfOwned: ViewModifier {
    let owned: Bool
    let iconFont: Font
    func body(content: Content) -> some View {
        if owned { content.labelStyle(ButtonLabel(iconFont: iconFont)) } else { content }
    }
}

extension ButtonStyle where Self == OuroButtonStyle {
    /// Ouro HX's button look: `.buttonStyle(.ouro())`, `.buttonStyle(.ouro(.glass, shape: .pill))`.
    public static func ouro(_ variant: OuroButtonVariant = .solid, tone: OuroTone = .primary, size: OuroButtonSize = .md, shape: OuroButtonShape = .pill, fullWidth: Bool = false) -> OuroButtonStyle {
        OuroButtonStyle(variant, tone: tone, size: size, shape: shape, fullWidth: fullWidth)
    }
}

/// Ouro HX's button: the obvious control for any action, web's `Button`.
///
/// ```swift
/// OuroButton("Save", systemImage: "checkmark", loading: saving) { save() }
/// OuroButton("Delete", tone: .destructive, variant: .soft) { delete() }
/// OuroButton("Add to list", variant: .glass, shape: .pill) { add() }
/// ```
///
/// Its VoiceOver label is its title, with the button trait. `loading` shows a spinner in place of the label, keeps
/// the width, disables the button and has VoiceOver say `loadingLabel`. `haptic` plays a moment on every press.
public struct OuroButton<Label: View>: View {
    private let action: () -> Void
    private let label: Label
    private let style: OuroButtonStyle
    private let role: ButtonRole?
    private let loading: Bool
    private let loadingLabel: String
    @Environment(\.isEnabled) private var outerEnabled
    private let haptic: OuroHapticMoment?
    @State private var presses = 0

    /// A button with any label.
    public init(
        tone: OuroTone = .primary,
        variant: OuroButtonVariant = .solid,
        size: OuroButtonSize = .md,
        shape: OuroButtonShape = .pill,
        fullWidth: Bool = false,
        role: ButtonRole? = nil,
        loading: Bool = false,
        loadingLabel: String = "Loading",
        haptic: OuroHapticMoment? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.label = label()
        self.style = OuroButtonStyle(variant, tone: tone, size: size, shape: shape, fullWidth: fullWidth)
        self.role = role
        self.loading = loading
        self.loadingLabel = loadingLabel
        self.haptic = haptic
    }

    public var body: some View {
        Button(role: role) {
            presses += 1
            action()
        } label: {
            label
                .opacity(loading ? 0 : 1)
                .overlay { if loading { ProgressView().accessibilityHidden(true) } }
        }
        .buttonStyle(style)
        .environment(\.ouroButtonOwnsLabel, true)
        // Busy, not unavailable, unless something around the button disabled it anyway.
        .environment(\.ouroButtonLoading, loading && outerEnabled)
        .disabled(loading)
        .accessibilityValue(loading ? Text(loadingLabel) : Text(""))
        .sensoryFeedback(trigger: presses) { _, _ in haptic?.sensoryFeedback }
        .onChange(of: loading) { _, now in
            if now { OuroAnnounce.post(loadingLabel, priority: .default) }
        }
    }
}

extension OuroButton where Label == SwiftUI.Label<Text, Image> {
    /// A button with a title and an SF Symbol before it. The symbol is decorative; VoiceOver says the title.
    public init(
        _ title: String,
        systemImage: String,
        tone: OuroTone = .primary,
        variant: OuroButtonVariant = .solid,
        size: OuroButtonSize = .md,
        shape: OuroButtonShape = .pill,
        fullWidth: Bool = false,
        role: ButtonRole? = nil,
        loading: Bool = false,
        loadingLabel: String = "Loading",
        haptic: OuroHapticMoment? = nil,
        action: @escaping () -> Void
    ) {
        self.init(tone: tone, variant: variant, size: size, shape: shape, fullWidth: fullWidth, role: role, loading: loading, loadingLabel: loadingLabel, haptic: haptic, action: action) {
            SwiftUI.Label(title, systemImage: systemImage)
        }
    }
}

extension OuroButton where Label == Text {
    /// A button with a title.
    public init(
        _ title: String,
        tone: OuroTone = .primary,
        variant: OuroButtonVariant = .solid,
        size: OuroButtonSize = .md,
        shape: OuroButtonShape = .pill,
        fullWidth: Bool = false,
        role: ButtonRole? = nil,
        loading: Bool = false,
        loadingLabel: String = "Loading",
        haptic: OuroHapticMoment? = nil,
        action: @escaping () -> Void
    ) {
        self.init(tone: tone, variant: variant, size: size, shape: shape, fullWidth: fullWidth, role: role, loading: loading, loadingLabel: loadingLabel, haptic: haptic, action: action) {
            Text(title)
        }
    }
}

extension EnvironmentValues {
    /// Whether ``OuroButton``s here span the width they are offered, as if `fullWidth` were set. ``OuroEmptyState``
    /// sets it for its action at the accessibility text sizes.
    @Entry public var ouroButtonFillsWidth = false
}

/// A capsule at the height it is drawn: ends of ``OuroButtonMetrics/pillRadius(height:)``.
struct PillShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: OuroButtonMetrics.pillRadius(height: rect.height), style: .circular).path(in: rect)
    }
}

/// A button's icon and words: 6 points apart, the icon a step smaller and centred on the words.
private struct ButtonLabel: LabelStyle {
    let iconFont: Font
    func makeBody(configuration: Configuration) -> some View {
        // On the first line's baseline, so a label wrapped at the accessibility sizes keeps its icon by its first word.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(iconFont)
            configuration.title
        }
    }
}
