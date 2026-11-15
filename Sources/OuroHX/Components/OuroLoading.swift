public import SwiftUI

// MARK: Skeleton

/// The outline of what is loading, as web's `shape`: `rect` a block (a picture, a chart), `text` lines of words,
/// `circle` an avatar, `row` an ``OuroItem`` row, `card` an ``OuroCard``.
public enum OuroSkeletonShape: String, CaseIterable, Sendable { case rect, text, circle, row, card }

/// The resolved colours of loading placeholders and progress as seen.
public struct OuroLoadingPalette: Sendable {
    /// A skeleton's fill: the theme's `muted`, raised to 1.3:1 on the page so a placeholder is seen in every theme.
    public var placeholder: Color.Resolved
    /// A progress bar's track.
    public var track: Color.Resolved
    /// The page.
    public var surface: Color.Resolved
    /// Words beside a spinner or a bar: 5:1 on the page (7:1 under increased contrast); core claim `contrast.text`.
    public var label: Color.Resolved
    public var value: Color.Resolved

    public init(style: OuroHXStyle) {
        let c = style.colors
        let page = OuroInk.r(c.background)
        surface = page
        placeholder = OuroColor.push(OuroInk.r(c.muted), against: page, to: OuroLoadingMetrics.placeholderContrast)
        track = placeholder
        label = OuroInk.readable(OuroInk.r(c.foreground), on: page, style)
        value = OuroInk.readable(OuroInk.r(c.mutedForeground), on: page, style)
    }

    /// A tone's fill on the track and the page: 3:1, so the part that is done can be seen (WCAG 1.4.11). `secondary` is
    /// the muted foreground, as on web.
    public func fill(_ tone: OuroTone, style: OuroHXStyle) -> Color.Resolved {
        OuroColor.push(OuroInk.r(tone == .secondary ? style.colors.mutedForeground : tone.fill(style.colors).fill), against: track, to: OuroColor.increasedLineContrast, alsoAgainst: surface)
    }
}

/// Metrics the loading components share, as data.
public enum OuroLoadingMetrics {
    public static let defaultSkeletonShape = OuroSkeletonShape.rect
    /// A placeholder is seen against the page, but stays quiet: 1.3:1.
    public static let placeholderContrast = 1.3
    /// How long a placeholder waits before it breathes, as web: a fast load never flickers.
    public static let breatheDelay: Double = 1
    /// One breath, in and out.
    public static let breatheDuration: Double = 1.6
    /// The last of several text lines is shorter, like a paragraph's: 60% of the width.
    public static let lastLineFraction: CGFloat = 0.6
    /// The default number of rows and cards.
    public static let defaultCount = 1

    /// Whether a placeholder breathes: never under Reduce Motion, when `shimmer` is off, or past the first few in a
    /// list, as web.
    public static func breathes(shimmer: Bool, reduceMotion: Bool) -> Bool { shimmer && !reduceMotion }

    /// A text line's height for each text style, so a line of placeholder is a line of the words it stands for.
    public static func lineHeight(_ font: Font.TextStyle) -> CGFloat {
        switch font {
        case .caption, .caption2, .footnote: 16
        case .subheadline, .callout: 20
        case .title3, .title2: 28
        case .title, .largeTitle: 36
        default: 22
        }
    }

    // MARK: Spinner

    public static let defaultSpinnerSize = OuroSpinnerSize.md
    /// Web's spinner sides: 16, 20 and 32 points.
    public static func spinnerSide(_ size: OuroSpinnerSize) -> CGFloat {
        switch size {
        case .sm: 16
        case .md: 20
        case .lg: 32
        }
    }
    /// What VoiceOver hears for a spinner or a bar whose value is unknown, as web's default.
    public static let loadingLabel = "Loading"

    // MARK: Progress

    public static let defaultProgressTone = OuroTone.primary
    /// Web's `h-2`: an 8-point bar.
    public static let barHeight: CGFloat = 8

    /// How far along, from 0 to 1, clamped; `nil` when the value isn't known.
    public static func fraction(_ value: Double?, min: Double, max: Double) -> Double? {
        guard let value, max > min else { return nil }
        return Swift.min(1, Swift.max(0, (value - min) / (max - min)))
    }

    /// The value as VoiceOver hears it and `showValue` writes it: a whole percentage, or "Loading" while unknown.
    public static func valueText(_ value: Double?, min: Double, max: Double, indeterminateText: String = loadingLabel) -> String {
        guard let f = fraction(value, min: min, max: max) else { return indeterminateText }
        return (f).formatted(.percent.precision(.fractionLength(0)))
    }
}

/// Ouro HX's skeleton: the outline of something that is loading, in the place it will arrive, web's `Skeleton`.
///
/// ```swift
/// OuroSkeleton(.text, lines: 3)
/// OuroSkeleton(.circle, side: 40)
/// OuroSkeleton(.row, count: 6)
/// OuroSkeleton().frame(height: 160)
/// ```
///
/// It holds still for a second, so a quick load never flickers, then breathes; under Reduce Motion it holds still.
/// VoiceOver hears one "Loading" for the group, not each line.
public struct OuroSkeleton: View {
    let shape: OuroSkeletonShape
    let lines: Int
    let count: Int
    let side: CGFloat
    let font: Font.TextStyle
    let shimmer: Bool
    let label: String
    @State private var breathing = false
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ shape: OuroSkeletonShape = OuroLoadingMetrics.defaultSkeletonShape,
        lines: Int = 1,
        count: Int = OuroLoadingMetrics.defaultCount,
        side: CGFloat = 40,
        font: Font.TextStyle = .body,
        shimmer: Bool = true,
        label: String = OuroLoadingMetrics.loadingLabel
    ) {
        self.shape = shape
        self.lines = max(1, lines)
        self.count = max(1, count)
        self.side = side
        self.font = font
        self.shimmer = shimmer
        self.label = label
    }

    public var body: some View {
        let palette = OuroLoadingPalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        let fill = Color(palette.placeholder)
        Group {
            switch shape {
            case .rect:
                RoundedRectangle(cornerRadius: theme.radius(.md), style: .continuous).fill(fill)
            case .circle:
                Circle().fill(fill).frame(width: side, height: side)
            case .text:
                textLines(fill)
            case .row:
                VStack(spacing: 0) { ForEach(0..<count, id: \.self) { _ in row(fill) } }
            case .card:
                VStack(spacing: 16) { ForEach(0..<count, id: \.self) { _ in card(fill) } }
            }
        }
        .opacity(breathing ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .task(id: OuroLoadingMetrics.breathes(shimmer: shimmer, reduceMotion: reduceMotion)) {
            guard OuroLoadingMetrics.breathes(shimmer: shimmer, reduceMotion: reduceMotion) else { breathing = false; return }
            try? await Task.sleep(for: .seconds(OuroLoadingMetrics.breatheDelay))
            withAnimation(.easeInOut(duration: OuroLoadingMetrics.breatheDuration / 2).repeatForever(autoreverses: true)) { breathing = true }
        }
    }

    private func textLines(_ fill: Color) -> some View {
        let height = OuroLoadingMetrics.lineHeight(font)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<lines, id: \.self) { i in
                GeometryReader { g in
                    Capsule().fill(fill)
                        .frame(width: g.size.width * (lines > 1 && i == lines - 1 ? OuroLoadingMetrics.lastLineFraction : 1), height: height * 0.6)
                        .frame(maxHeight: .infinity)
                }
                .frame(height: height)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The height of an ``OuroItem`` row with a 40-point picture: 12 above and below.
    private func row(_ fill: Color) -> some View {
        HStack(spacing: OuroItemMetrics.spacing) {
            RoundedRectangle(cornerRadius: theme.radius(.md), style: .continuous).fill(fill)
                .frame(width: OuroItemMetrics.mediaSide(.sm), height: OuroItemMetrics.mediaSide(.sm))
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(fill).frame(height: 12).frame(maxWidth: .infinity)
                Capsule().fill(fill).frame(height: 10).frame(maxWidth: 160)
            }
        }
        .padding(.vertical, OuroItemMetrics.verticalPadding(.md))
    }

    private func card(_ fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule().fill(fill).frame(width: 160, height: 14)
            Capsule().fill(fill).frame(height: 10)
            Capsule().fill(fill).frame(height: 10).frame(maxWidth: 220)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: theme.radius(OuroCardMetrics.radius), style: .continuous).strokeBorder(fill, lineWidth: 1))
    }
}

// MARK: Spinner

/// A spinner's size, as on web: 16, 20 and 32 points. `sm` matches running text.
public enum OuroSpinnerSize: String, CaseIterable, Sendable { case sm, md, lg }

/// Ouro HX's spinner: a small sign that something is under way, beside the words that say what, web's `Spinner`.
///
/// ```swift
/// HStack { OuroSpinner(label: "Saving"); Text("Saving…") }
/// ```
///
/// It is the system's activity indicator, so it pulses under Reduce Motion as iOS's does. VoiceOver hears `label`.
/// Where content will arrive, use ``OuroSkeleton``; when you know how far along the work is, ``OuroProgress``.
public struct OuroSpinner: View {
    let label: String
    let size: OuroSpinnerSize
    let tone: OuroTone?
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    public init(label: String = OuroLoadingMetrics.loadingLabel, size: OuroSpinnerSize = OuroLoadingMetrics.defaultSpinnerSize, tone: OuroTone? = nil) {
        self.label = label
        self.size = size
        self.tone = tone
    }

    public var body: some View {
        let style = OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast)
        let side = OuroLoadingMetrics.spinnerSide(size)
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(size == .lg ? .regular : .small)
            .tint(tone.map { Color(OuroLoadingPalette(style: style).fill($0, style: style)) })
            .frame(width: side, height: side)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            // Words, not a control: VoiceOver reads the label, and the accessibility audit doesn't ask a 14-point
            // status for a 44-point target.
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: Progress

/// Ouro HX's progress bar: how far along some work is, with its name above, web's `Progress`.
///
/// ```swift
/// OuroProgress("Uploading photos", value: 3, max: 8, showValue: true)
/// OuroProgress("Preparing your cookbook", value: nil)
/// ```
///
/// A `nil` value is indeterminate: a segment slides, or, under Reduce Motion, the track pulses. VoiceOver hears the
/// label and the value as a percentage, or "Loading".
public struct OuroProgress: View {
    let label: String
    let value: Double?
    let min: Double
    let max: Double
    let tone: OuroTone
    let hideLabel: Bool
    let showValue: Bool
    let indeterminateText: String
    @State private var phase: CGFloat = 0
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ label: String,
        value: Double?,
        min: Double = 0,
        max: Double = 100,
        tone: OuroTone = OuroLoadingMetrics.defaultProgressTone,
        hideLabel: Bool = false,
        showValue: Bool = false,
        indeterminateText: String = OuroLoadingMetrics.loadingLabel
    ) {
        self.label = label
        self.value = value
        self.min = min
        self.max = max
        self.tone = tone
        self.hideLabel = hideLabel
        self.showValue = showValue
        self.indeterminateText = indeterminateText
    }

    public var body: some View {
        let style = OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast)
        let palette = OuroLoadingPalette(style: style)
        let fraction = OuroLoadingMetrics.fraction(value, min: min, max: max)
        let text = OuroLoadingMetrics.valueText(value, min: min, max: max, indeterminateText: indeterminateText)
        VStack(alignment: .leading, spacing: 6) {
            if !hideLabel || showValue {
                HStack(alignment: .firstTextBaseline) {
                    if !hideLabel {
                        Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Color(palette.label))
                    }
                    Spacer(minLength: 8)
                    if showValue, fraction != nil {
                        Text(text).font(.subheadline.monospacedDigit()).foregroundStyle(Color(palette.value))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(palette.track))
                    if let fraction {
                        Capsule().fill(Color(palette.fill(tone, style: style)))
                            .frame(width: geo.size.width * fraction)
                            .animation(OuroMotion.animation(.base, reduceMotion: reduceMotion), value: fraction)
                    } else if reduceMotion {
                        Capsule().fill(Color(palette.fill(tone, style: style))).opacity(0.35)
                    } else {
                        Capsule().fill(Color(palette.fill(tone, style: style)))
                            .frame(width: geo.size.width * 0.35)
                            .offset(x: (geo.size.width * 1.35) * phase - geo.size.width * 0.35)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: OuroLoadingMetrics.barHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(text))
        .accessibilityAddTraits(.updatesFrequently)
        .task(id: fraction == nil && !reduceMotion) {
            guard fraction == nil, !reduceMotion else { return }
            phase = 0
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }
}
