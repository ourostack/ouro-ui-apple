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

    /// The button's minimum height: 44, 44 and 48 on a touch screen (web's `h-11` and `h-12` on phones), 28, 32 and
    /// 40 with a pointer.
    public func minimumHeight(on input: OuroInput) -> CGFloat {
        minimumHeight(on: input, target: Self.minimumTarget(on: .touch))
    }

    /// The minimum height when the touch target is `target` points, as inside an `.ouroSheet`
    /// (``OuroSheetMetrics/touchTarget``): never below it on a touch screen, and web's heights with a pointer.
    public func minimumHeight(on input: OuroInput, target: CGFloat) -> CGFloat {
        switch (self, input) {
        case (.sm, .touch), (.md, .touch): max(44, target)
        case (.lg, .touch): max(48, target)
        case (.sm, .pointer): 28
        case (.md, .pointer): 32
        case (.lg, .pointer): 40
        }
    }

    /// Padding at the label's sides: web's `px-3`, `px-4` and `px-5`.
    public var horizontalPadding: CGFloat {
        switch self { case .sm: 12; case .md: 16; case .lg: 20 }
    }

    var font: Font {
        switch self {
        case .sm: .subheadline.weight(.medium)
        case .md: .body.weight(.medium)
        case .lg: .body.weight(.semibold)
        }
    }
}

/// A button's outline: `rounded` (the theme's `lg` radius, web's look) or `pill`, a capsule, as Spoonjoy's and
/// Gatefold's buttons are.
public enum OuroButtonShape: String, CaseIterable, Sendable { case rounded, pill }

/// The resolved colours of a button, for one tone, variant and theme as seen. `surface` is what the label sits on:
/// the fill, or the page (`background`) when the variant has none. Its label reads at 4.5:1 on it (7:1 under
/// increased contrast) in every theme; core claim `contrast.text`.
public struct OuroButtonPalette: Sendable {
    public var label: Color.Resolved
    public var fill: Color.Resolved?
    public var border: Color.Resolved?
    public var surface: Color.Resolved

    public init(tone: OuroTone, variant: OuroButtonVariant, style: OuroHXStyle) {
        let c = style.colors
        let background = OuroInk.r(c.background)
        let (toneFill, toneLabel) = tone.fill(c)
        let fill = OuroInk.r(toneFill)
        // Secondary's own colour is a pale fill, so as text it reads as the page's foreground.
        let toneText = tone == .secondary ? OuroInk.r(c.foreground) : fill
        switch variant {
        case .solid:
            self.fill = fill
            surface = fill
            label = OuroInk.readable(OuroInk.r(toneLabel), on: fill, style)
            border = nil
        case .soft:
            let tinted = tone == .secondary ? fill : OuroInk.tint(fill, over: background, 0.14)
            self.fill = tinted
            surface = tinted
            label = OuroInk.readable(toneText, on: tinted, style)
            border = nil
        case .outline:
            self.fill = nil
            surface = background
            label = OuroInk.readable(toneText, on: background, style)
            border = OuroColor.push(OuroInk.r(c.border), against: background, to: style.contrast == .increased ? OuroColor.increasedLineContrast : 1)
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
    /// Core's press scale while pressed, or none under Reduce Motion.
    public static func pressScale(isPressed: Bool, reduceMotion: Bool) -> Double {
        OuroMotion.pressScale(isPressed: isPressed, reduceMotion: reduceMotion)
    }

    /// A disabled button's opacity, as on web.
    public static let disabledOpacity = 0.5
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

    public init(_ variant: OuroButtonVariant = .solid, tone: OuroTone = .primary, size: OuroButtonSize = .md, shape: OuroButtonShape = .rounded, fullWidth: Bool = false) {
        self.variant = variant
        self.tone = tone
        self.size = size
        self.shape = shape
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        ButtonBody(style: self, configuration: configuration)
    }

    private struct ButtonBody: View {
        let style: OuroButtonStyle
        let configuration: Configuration
        @Environment(\.ouroTheme) private var theme
        @Environment(\.colorScheme) private var scheme
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.ouroTouchTarget) private var touchTarget

        var body: some View {
            let palette = OuroButtonPalette(tone: style.tone, variant: style.variant, style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
            let shape = style.shape == .pill ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: theme.radius(.lg), style: .continuous))
            let pressed = configuration.isPressed
            configuration.label
                .font(style.size.font)
                .multilineTextAlignment(.center)
                // Wraps instead of truncating at every text size (core claim `text.reflows`).
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color(palette.label))
                .padding(.horizontal, style.size.horizontalPadding)
                .padding(.vertical, 8)
                .frame(maxWidth: style.fullWidth ? .infinity : nil, minHeight: style.size.minimumHeight(on: .current, target: touchTarget))
                .frame(minWidth: OuroInput.current == .touch ? max(touchTarget, OuroButtonSize.minimumTarget(on: .touch)) : OuroButtonSize.minimumTarget(on: .pointer))
                .background { background(palette, shape: shape, pressed: pressed) }
                .modifier(GlassIfNeeded(enabled: style.variant == .glass, shape: shape))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : OuroButtonMetrics.disabledOpacity)
                .scaleEffect(OuroButtonMetrics.pressScale(isPressed: pressed, reduceMotion: reduceMotion))
                .animation(OuroMotion.animation(.press, reduceMotion: reduceMotion), value: pressed)
        }

        @ViewBuilder
        private func background(_ p: OuroButtonPalette, shape: AnyShape, pressed: Bool) -> some View {
            let layer = Color(p.label).opacity(pressed ? 0.12 : 0)
            if let fill = p.fill {
                shape.fill(Color(fill)).overlay(shape.fill(layer))
            } else if let border = p.border {
                shape.stroke(Color(border), lineWidth: 1).padding(0.5).background(shape.fill(layer))
            } else {
                shape.fill(layer)
            }
        }
    }

    private struct GlassIfNeeded: ViewModifier {
        let enabled: Bool
        let shape: AnyShape

        func body(content: Content) -> some View {
            if !enabled {
                content
            } else if #available(iOS 26, macOS 26, visionOS 26, *) {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        }
    }
}

extension ButtonStyle where Self == OuroButtonStyle {
    /// Ouro HX's button look: `.buttonStyle(.ouro())`, `.buttonStyle(.ouro(.glass, shape: .pill))`.
    public static func ouro(_ variant: OuroButtonVariant = .solid, tone: OuroTone = .primary, size: OuroButtonSize = .md, shape: OuroButtonShape = .rounded, fullWidth: Bool = false) -> OuroButtonStyle {
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
    private let haptic: OuroHapticMoment?
    @State private var presses = 0

    /// A button with any label.
    public init(
        tone: OuroTone = .primary,
        variant: OuroButtonVariant = .solid,
        size: OuroButtonSize = .md,
        shape: OuroButtonShape = .rounded,
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
        shape: OuroButtonShape = .rounded,
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
        shape: OuroButtonShape = .rounded,
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
