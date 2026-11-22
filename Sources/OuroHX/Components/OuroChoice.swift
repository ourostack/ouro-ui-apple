public import SwiftUI

// MARK: Shared

/// Metrics ``OuroSegmentedControl`` and ``OuroCheckbox`` share, as data.
public enum OuroChoiceMetrics {
    /// A segment's height: 44 points to touch (core claim `target.touch`), web's 36 with a pointer.
    public static func segmentHeight(_ input: OuroInput) -> CGFloat { input == .touch ? 44 : 36 }
    /// The track's inset around the thumb: web's `p-0.5`. Above and below, it sits inside each segment, so a segment's
    /// target is the track's whole height, 44 points to touch, though the thumb is drawn 2 points in.
    public static let trackInset: CGFloat = 2
    /// A segment's side padding: web's `px-3`.
    public static let segmentPadding: CGFloat = 12
    /// How far the muted segment text is mixed toward the foreground, as web's 80/20 mix, for contrast on the track.
    public static let segmentTextMix = 0.2
    /// How far the dark thumb is mixed toward the foreground from the track, as web's 16%.
    public static let darkThumbMix = 0.16
    /// The track's corner for segments `height` points tall: web's `rounded-ouro-control`, the theme's control radius
    /// (``OuroTheme/controlCorner``) at most half a segment's height, so Cookbook's track is a squircle capsule and
    /// Pearl's keeps its 18-point squircle. Stacked at the accessibility sizes, it still stops at half one segment.
    public static func trackCorner(theme: OuroTheme, height: CGFloat) -> CGFloat {
        min(CGFloat(theme.controlCorner), height / 2)
    }
    /// The thumb's corner for segments `height` points tall: web's `rounded-ouro-control-md`, the theme's control
    /// radius or its `md` step, at most half the thumb's own height (the segment less the track's inset above and
    /// below), so Cookbook's thumb is a capsule inside the capsule track.
    public static func thumbCorner(theme: OuroTheme, height: CGFloat) -> CGFloat {
        min(CGFloat(theme.controlRadius ?? theme.radius(.md)), (height - trackInset * 2) / 2)
    }

    /// The box's side: web's 20 points to touch, 16 with a pointer.
    public static func boxSide(_ input: OuroInput) -> CGFloat { input == .touch ? 20 : 16 }

    /// How far along each edge an iOS continuous corner reaches, in multiples of its radius.
    public static let continuousCornerReach: CGFloat = 1.528
    /// The box's continuous corner radius: web's check radius (the theme's `sm`), clamped to half the side as CSS
    /// clamps it, then sized so the continuous corner reaches as far along each edge as web's `corner-shape: squircle`
    /// does (exactly the radius). At the theme's radius itself a continuous corner on a 20-point box closes into a
    /// circle; web's box is a squircle.
    public static func boxRadius(themeRadius: CGFloat, side: CGFloat) -> CGFloat {
        min(themeRadius, side / 2) / continuousCornerReach
    }
    /// A checkbox row is at least 44 points tall to touch, the box's whole row its target.
    public static func rowMinHeight(_ input: OuroInput) -> CGFloat { input == .touch ? 44 : 24 }
    /// Web's `gap-3` between the box and its words.
    public static let boxGap: CGFloat = 12
    /// The tick, on a 16-point grid, as web's SVG path `M3.5 8.5 6.5 11.5 12.5 4.5`.
    public static let tick: [CGPoint] = [CGPoint(x: 3.5, y: 8.5), CGPoint(x: 6.5, y: 11.5), CGPoint(x: 12.5, y: 4.5)]

    /// At the accessibility text sizes segments stack, one above the next, so every label keeps its words.
    public static func stacksSegments(at size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }

    /// What VoiceOver says a checkbox is: checked, not checked or mixed, as web's `aria-checked`.
    public static func checkboxValue(isOn: Bool, indeterminate: Bool) -> String {
        indeterminate ? "Mixed" : isOn ? "Checked" : "Not checked"
    }

    /// The checkbox's spoken name: its label, then required when it is, as on web.
    public static func checkboxName(_ label: String, required: Bool) -> String { required ? "\(label), required" : label }

    /// The hint: the error first, then the description, as web's `aria-describedby` order.
    public static func hint(error: String?, description: String?) -> String {
        [error, description].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The tick draws once the box has filled, over core's `draw` duration after `fast`; under Reduce Motion it fades.
    public static func tickDraws(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// The dash a mixed box shows in place of the tick: web's SVG path `M4 8h8`, on the tick's grid and with its caps.
    public static let dash: [CGPoint] = [CGPoint(x: 4, y: 8), CGPoint(x: 12, y: 8)]

    /// What the box shows: the dash when mixed, otherwise the tick (drawn or not).
    public enum Glyph: Sendable { case tick, dash }
    public static func glyph(indeterminate: Bool) -> Glyph { indeterminate ? .dash : .tick }

    /// The tick's and the dash's stroke: web's `strokeWidth` 2 on the 16-point grid, scaled with the box, so 2.5 points
    /// on the 20-point box to touch and 2 on the 16-point one.
    public static func strokeWidth(side: CGFloat) -> CGFloat { 2 * side / 16 }

    /// CSS's `ease`, which web cross-fades the box's fill, edge and colour on.
    public static let cssEase = OuroCubicBezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    /// The fill, the edge and the hover edge cross-fade over core's `fast` duration on CSS `ease`, as web's box does.
    /// Reduce Motion keeps it: a colour change does not move.
    public static let boxFade = OuroMotion.Step.curve(cssEase, duration: OuroTokens.Duration.fast)

    /// How the tick moves when the box changes, as data.
    public struct TickMotion: Equatable, Sendable {
        public let ease: OuroCubicBezier
        public let duration: Double
        /// Seconds after the change before the tick moves: on checking, the time the fill takes.
        public let delay: Double
        /// Whether it draws along its path (`trim`), rather than fading.
        public let draws: Bool

        /// The animation, on ``OuroMotion/clock`` when one is installed, the delay counted on that clock too.
        public var animation: Animation? {
            let base: Animation = ease.animation(duration: duration).delay(delay)
            return OuroMotion.clocked(base, on: OuroMotion.clock) as Animation
        }
    }

    /// Web's tick motion. Checking draws it along its path over `draw`, ease out, once the fill has had `fast`;
    /// unchecking takes it back over `fast`, ease out, at once. Under Reduce Motion nothing draws: the whole tick fades
    /// in or out over `fast`, ease out.
    public static func tickMotion(checking: Bool, reduceMotion: Bool) -> TickMotion {
        typealias D = OuroTokens.Duration
        let out = OuroTokens.Ease.out
        if reduceMotion { return TickMotion(ease: out, duration: D.fast, delay: 0, draws: false) }
        return checking ? TickMotion(ease: out, duration: D.draw, delay: D.fast, draws: true)
            : TickMotion(ease: out, duration: D.fast, delay: 0, draws: true)
    }

    /// Where the tick rests: how much of its path shows (`trim`'s end) and its opacity. It draws in and out, or under
    /// Reduce Motion is always whole and fades.
    public static func tick(isOn: Bool, reduceMotion: Bool) -> (trim: CGFloat, opacity: Double) {
        reduceMotion ? (1, isOn ? 1 : 0) : (isOn ? 1 : 0, 1)
    }

    /// The box's edge: destructive when invalid, the fill when checked or mixed, the foreground under a pointer
    /// (web's `pointer-fine:hover:border-foreground`), else the muted edge.
    public static func edge(_ palette: OuroCheckboxPalette, filled: Bool, invalid: Bool, hovering: Bool) -> Color.Resolved {
        invalid ? palette.invalidEdge : filled ? palette.fill : hovering ? palette.hoverEdge : palette.edge
    }

    /// Web's focus ring: 2 points wide, 2 points out from the box (`outline-2 outline-offset-2`).
    public static let focusRingWidth: CGFloat = 2
    public static let focusRingOffset: CGFloat = 2
}

// MARK: Segmented control

/// One segment of an ``OuroSegmentedControl``: its value, its one short word, and whether it can be pressed.
public struct OuroSegment<Value: Hashable>: Identifiable {
    public let value: Value
    public let label: String
    public let disabled: Bool
    public var id: Value { value }

    public init(_ label: String, value: Value, disabled: Bool = false) {
        self.label = label
        self.value = value
        self.disabled = disabled
    }
}

/// The resolved colours of a segmented control: the pressed segment's words on the thumb and the others' on the track
/// read at 5:1 (7:1 under increased contrast), core claim `contrast.text`; under increased contrast the thumb gets an
/// edge at 3:1 on the track, so which segment is pressed never rests on a shadow.
public struct OuroSegmentedControlPalette: Sendable {
    public var track: Color.Resolved
    public var thumb: Color.Resolved
    public var thumbEdge: Color.Resolved?
    public var selected: Color.Resolved
    public var unselected: Color.Resolved
    public var label: Color.Resolved

    public init(style: OuroHXStyle) {
        let c = style.colors
        let page = OuroInk.r(c.background)
        let fg = OuroInk.r(c.foreground)
        track = OuroInk.r(c.muted)
        thumb = style.scheme == .dark ? OuroColor.mix(track, fg, OuroChoiceMetrics.darkThumbMix) : page
        thumbEdge = style.contrast == .increased ? OuroColor.push(OuroInk.r(c.border), against: track, to: OuroColor.increasedLineContrast) : nil
        selected = OuroInk.readable(fg, on: thumb, style)
        unselected = OuroInk.readable(OuroColor.mix(OuroInk.r(c.mutedForeground), fg, OuroChoiceMetrics.segmentTextMix), on: track, style)
        label = OuroInk.readable(fg, on: page, style)
    }
}

/// Ouro HX's segmented control: a row of equal segments with a raised thumb that slides to the pressed one, for
/// switching how one view shows its content in place, such as list or grid, web's `SegmentedControl`.
///
/// ```swift
/// @State private var view = "list"
/// OuroSegmentedControl("View", selection: $view, hideLabel: true, items: [
///     OuroSegment("List", value: "list"),
///     OuroSegment("Grid", value: "grid"),
/// ])
/// ```
///
/// Exactly one segment is pressed. Segments are 44 points tall to touch and as wide as the longest label; the thumb
/// slides on the theme's spring, or crossfades under Reduce Motion, and a selection tick plays. VoiceOver hears the
/// label, then each segment as a button, the pressed one selected. At the accessibility sizes the segments stack.
/// Use a `TabView` instead when each choice has its own content, and links when each is its own page.
public struct OuroSegmentedControl<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let items: [OuroSegment<Value>]
    let hideLabel: Bool
    let fullWidth: Bool
    @Namespace private var thumbSpace
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init(_ label: String, selection: Binding<Value>, hideLabel: Bool = false, fullWidth: Bool = false, items: [OuroSegment<Value>]) {
        self.label = label
        self._selection = selection
        self.items = items
        self.hideLabel = hideLabel
        self.fullWidth = fullWidth
    }

    public var body: some View {
        let palette = OuroSegmentedControlPalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        let stacked = OuroChoiceMetrics.stacksSegments(at: typeSize)
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        VStack(alignment: .leading, spacing: 8) {
            if !hideLabel {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(palette.label))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            layout {
                ForEach(items) { item in segment(item, palette) }
            }
            .padding(.horizontal, OuroChoiceMetrics.trackInset)
            .background(RoundedRectangle(cornerRadius: OuroChoiceMetrics.trackCorner(theme: theme, height: OuroChoiceMetrics.segmentHeight(.current)), style: .continuous).fill(Color(palette.track)))
            .fixedSize(horizontal: !fullWidth && !stacked, vertical: false)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(label))
        }
        .ouroHaptic(.selected, trigger: selection)
    }

    private func segment(_ item: OuroSegment<Value>, _ palette: OuroSegmentedControlPalette) -> some View {
        let on = item.value == selection
        let thumbCorner = OuroChoiceMetrics.thumbCorner(theme: theme, height: OuroChoiceMetrics.segmentHeight(.current))
        return Button {
            guard !on else { return }
            withAnimation(OuroMotion.animation(.layout, reduceMotion: reduceMotion)) { selection = item.value }
        } label: {
            Text(item.label)
                .font(OuroInput.current == .touch ? .body.weight(.medium) : .subheadline.weight(.medium))
                .lineLimit(OuroChoiceMetrics.stacksSegments(at: typeSize) ? nil : 1)
                .foregroundStyle(Color(on ? palette.selected : palette.unselected))
                .padding(.horizontal, OuroChoiceMetrics.segmentPadding)
                .frame(maxWidth: .infinity, minHeight: OuroChoiceMetrics.segmentHeight(.current) - OuroChoiceMetrics.trackInset * 2)
                .padding(.vertical, OuroChoiceMetrics.trackInset)
                .background {
                    if on {
                        RoundedRectangle(cornerRadius: thumbCorner, style: .continuous)
                            .fill(Color(palette.thumb))
                            .overlay {
                                if let edge = palette.thumbEdge {
                                    RoundedRectangle(cornerRadius: thumbCorner, style: .continuous).strokeBorder(Color(edge), lineWidth: 1)
                                }
                            }
                            .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.12), radius: 1.5, y: 1)
                            .padding(.vertical, OuroChoiceMetrics.trackInset)
                            .matchedGeometryEffect(id: "thumb", in: thumbSpace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(OuroSegmentPress())
        .disabled(item.disabled)
        .opacity(item.disabled || !isEnabled ? 0.5 : 1)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct OuroSegmentPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(OuroMotion.pressScale(isPressed: configuration.isPressed, reduceMotion: reduceMotion))
            .animation(OuroMotion.animation(configuration.isPressed ? .pressIn : .pressOut, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

// MARK: Checkbox

/// The resolved colours of a checkbox: its label, description and error read at 5:1 on the page (7:1 under increased
/// contrast), core claim `contrast.text`; its empty box's edge reads at 3:1, so it can be found (WCAG 1.4.11), and the
/// tick reads at 3:1 on the filled box.
public struct OuroCheckboxPalette: Sendable {
    public var label: Color.Resolved
    public var description: Color.Resolved
    public var error: Color.Resolved
    public var edge: Color.Resolved
    public var invalidEdge: Color.Resolved
    public var fill: Color.Resolved
    public var tick: Color.Resolved
    public var surface: Color.Resolved
    /// The empty box's edge under a pointer: the foreground.
    public var hoverEdge: Color.Resolved
    /// The keyboard focus ring.
    public var ring: Color.Resolved

    public init(style: OuroHXStyle) {
        let c = style.colors
        let page = OuroInk.r(c.background)
        let line = style.contrast == .increased ? OuroColor.increasedLineContrast : 3
        surface = page
        label = OuroInk.readable(OuroInk.r(c.foreground), on: page, style)
        description = OuroInk.readable(OuroInk.r(c.mutedForeground), on: page, style)
        error = OuroInk.readable(OuroInk.r(c.destructive), on: page, style)
        edge = OuroColor.push(OuroInk.r(c.mutedForeground), against: page, to: line)
        invalidEdge = OuroColor.push(OuroInk.r(c.destructive), against: page, to: line)
        hoverEdge = OuroColor.push(OuroInk.r(c.foreground), against: page, to: line)
        fill = OuroColor.push(OuroInk.r(c.primary), against: page, to: line)
        // The tick is a graphic, so WCAG 1.4.11's 3:1 on the fill, not text's 4.5.
        tick = OuroColor.push(OuroInk.r(c.primaryForeground), against: fill, to: line)
        ring = OuroColor.push(OuroInk.r(c.ring), against: page, to: line)
    }
}

/// Ouro HX's checkbox: a box and what checking it means, web's `Checkbox`.
///
/// ```swift
/// @State private var agreed = false
/// OuroCheckbox("I agree to the terms", isOn: $agreed, required: true)
/// OuroCheckbox("Select all", isOn: $all, indeterminate: some && !all)
/// OuroCheckbox("Email me new recipes", isOn: $email, description: "One a week, on Sundays.")
/// ```
///
/// The whole row is its target, at least 44 points tall to touch. Checking fills the box, then draws the tick along
/// its path (it fades under Reduce Motion), with a selection tick to feel; the box presses in under the finger, takes
/// the foreground for its edge under a pointer and shows a ring with keyboard focus (``OuroCheckboxMark``). VoiceOver hears the label (with required),
/// the state (checked, not checked or mixed) and the error and description as its hint. `indeterminate` shows a dash
/// and is controlled: clear it where you set `isOn`. Disable it with `.disabled(_:)`.
public struct OuroCheckbox: View {
    let label: String
    @Binding var isOn: Bool
    let description: String?
    let error: String?
    let required: Bool
    let indeterminate: Bool
    let hideLabel: Bool
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled

    public init(_ label: String, isOn: Binding<Bool>, description: String? = nil, error: String? = nil, required: Bool = false, indeterminate: Bool = false, hideLabel: Bool = false) {
        self.label = label
        self._isOn = isOn
        self.description = description
        self.error = error
        self.required = required
        self.indeterminate = indeterminate
        self.hideLabel = hideLabel
    }

    private var invalid: Bool { !(error ?? "").isEmpty }

    public var body: some View {
        let palette = OuroCheckboxPalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: OuroChoiceMetrics.boxGap) {
                // Web's `mt-0.5`: the box sits on the label's first line.
                OuroCheckboxMark(isOn: isOn, indeterminate: indeterminate, invalid: invalid)
                    .padding(.top, hideLabel ? 0 : 2)
                if !hideLabel {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(label).foregroundStyle(Color(palette.label))
                            if required { Text("*").foregroundStyle(Color(palette.error)) }
                        }
                        .font(.body)
                        if let description, !description.isEmpty {
                            Text(description).font(.subheadline).foregroundStyle(Color(palette.description))
                        }
                        if let error, !error.isEmpty {
                            Text(error).font(.subheadline).foregroundStyle(Color(palette.error))
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: OuroChoiceMetrics.rowMinHeight(.current))
            .contentShape(Rectangle())
        }
        .buttonStyle(OuroCheckboxPressStyle())
        .focusEffectDisabled()
        .opacity(isEnabled ? 1 : 0.5)
        .animation(OuroChoiceMetrics.boxFade.animation, value: isEnabled)
        .ouroHaptic(.checked, trigger: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(OuroChoiceMetrics.checkboxName(label, required: required)))
        .accessibilityValue(Text(OuroChoiceMetrics.checkboxValue(isOn: isOn, indeterminate: indeterminate)))
        .accessibilityHint(Text(OuroChoiceMetrics.hint(error: error, description: description)))
        .accessibilityAddTraits(.isToggle)
    }
}

/// Ouro HX's checkbox box on its own, web's `Checkbox` box: for a row an app lays out itself, such as a checklist's.
/// It fills, then draws its tick along its path; unchecking takes the tick back. Under Reduce Motion nothing draws and
/// the tick fades. It presses in with the row when the row's button style is ``OuroCheckboxPressStyle`` (or the row
/// sets `ouroCheckboxPressed`), takes the foreground for its edge under a pointer, and shows a ring when it has keyboard
/// focus. Its colours come from the theme: the primary fill, its foreground for the tick. It is decoration to
/// VoiceOver, so the row says its state (``OuroChoiceMetrics/checkboxValue(isOn:indeterminate:)``).
///
/// ```swift
/// Button { item.checked.toggle() } label: {
///     HStack { OuroCheckboxMark(isOn: item.checked); Text(item.name) }
/// }
/// .buttonStyle(OuroCheckboxPressStyle())
/// ```
public struct OuroCheckboxMark: View {
    let isOn: Bool
    let indeterminate: Bool
    let invalid: Bool
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.ouroCheckboxPressed) private var pressed
    @State private var hovering = false

    public init(isOn: Bool, indeterminate: Bool = false, invalid: Bool = false) {
        self.isOn = isOn
        self.indeterminate = indeterminate
        self.invalid = invalid
    }

    public var body: some View {
        let palette = OuroCheckboxPalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        let side = OuroChoiceMetrics.boxSide(.current)
        let filled = isOn || indeterminate
        let radius = OuroChoiceMetrics.boxRadius(themeRadius: theme.radius(.sm), side: side)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let edge = OuroChoiceMetrics.edge(palette, filled: filled, invalid: invalid, hovering: hovering && isEnabled)
        let tick = OuroChoiceMetrics.tick(isOn: isOn, reduceMotion: reduceMotion)
        let stroke = StrokeStyle(lineWidth: OuroChoiceMetrics.strokeWidth(side: side), lineCap: .round, lineJoin: .round)
        let ring = OuroChoiceMetrics.focusRingOffset + OuroChoiceMetrics.focusRingWidth / 2
        ZStack {
            shape.fill(filled ? Color(palette.fill) : .clear)
            shape.strokeBorder(Color(edge), lineWidth: 1)
            switch OuroChoiceMetrics.glyph(indeterminate: indeterminate) {
            case .dash:
                // Web shows and hides the dash at once (`hidden`/`block`); only the fill under it fades.
                OuroGridPath(points: OuroChoiceMetrics.dash)
                    .stroke(Color(palette.tick), style: stroke)
                    .transition(.identity)
            case .tick:
                OuroGridPath(points: OuroChoiceMetrics.tick)
                    .trim(from: 0, to: tick.trim)
                    .stroke(Color(palette.tick), style: stroke)
                    .opacity(tick.opacity)
                    .animation(OuroChoiceMetrics.tickMotion(checking: isOn, reduceMotion: reduceMotion).animation, value: isOn)
                    .transition(.identity)
            }
        }
        .frame(width: side, height: side)
        .animation(OuroChoiceMetrics.boxFade.animation, value: filled)
        .animation(OuroChoiceMetrics.boxFade.animation, value: hovering)
        // Web's focus ring: `outline-2 outline-offset-2` in the ring colour, following the box's corner.
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: radius + ring, style: .continuous)
                    .stroke(Color(palette.ring), lineWidth: OuroChoiceMetrics.focusRingWidth)
                    .padding(-ring)
            }
        }
        // The box presses in, not its row: web's `active:scale-(--ouro-press-scale)` on the box.
        .scaleEffect(OuroMotion.pressScale(isPressed: pressed && isEnabled, reduceMotion: reduceMotion))
        .animation(OuroMotion.animation(pressed ? .pressIn : .pressOut, reduceMotion: reduceMotion), value: pressed)
        .onHover { hovering = $0 }
        .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    /// Whether the row an ``OuroCheckboxMark`` sits in is pressed, so the box presses in. ``OuroCheckboxPressStyle`` sets
    /// it; a row with its own button style can set it from its configuration.
    @Entry public var ouroCheckboxPressed = false
}

/// A checkbox row's button style: the row itself does not move, and the ``OuroCheckboxMark`` in it presses in, as web's
/// box does. The system's focus effect gives way to the box's own ring.
public struct OuroCheckboxPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.ouroCheckboxPressed, configuration.isPressed)
    }
}

/// A line through points on the box's 16-point grid, as web's SVG paths, scaled to the box.
private struct OuroGridPath: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        var p = Path()
        for (i, point) in points.enumerated() {
            let at = CGPoint(x: rect.minX + point.x * s, y: rect.minY + point.y * s)
            if i == 0 { p.move(to: at) } else { p.addLine(to: at) }
        }
        return p
    }
}
