public import SwiftUI

// MARK: Separator

/// Which way a separator runs, as on web: `horizontal` spans its container's width between stacked content; `vertical`
/// stands as tall as its row between side-by-side items.
public enum OuroSeparatorOrientation: String, CaseIterable, Sendable { case horizontal, vertical }

/// The resolved colours of a separator: the line is the theme's border (3:1 on the page under increased contrast, as
/// every line is) or its tone; a label reads at 5:1 on the page (7:1 under increased contrast); core claim
/// `contrast.text`.
public struct OuroSeparatorPalette: Sendable {
    public var line: Color.Resolved
    public var label: Color.Resolved
    public var surface: Color.Resolved

    /// `tone` colours the line and the label, for an accent line such as where unread messages start. `secondary` is
    /// a surface, not a line colour, so it draws as no tone, as on web.
    public init(tone: OuroTone?, style: OuroHXStyle) {
        let c = style.colors
        let page = OuroInk.r(c.background)
        surface = page
        let accent: Color.Resolved? = switch tone {
        case .none, .secondary?: nil
        case let t?: OuroInk.r(t.fill(c).fill)
        }
        let base = accent ?? OuroInk.r(c.border)
        line = OuroColor.push(base, against: page, to: style.contrast == .increased ? OuroColor.increasedLineContrast : 1)
        label = OuroInk.readable(accent ?? OuroInk.r(c.mutedForeground), on: page, style)
    }
}

/// Metrics every ``OuroSeparator`` and ``OuroDescriptionList`` share, as data.
public enum OuroDisplayMetrics {
    public static let defaultOrientation = OuroSeparatorOrientation.horizontal

    /// Web's `h-px`: one point, two under increased contrast, as an outline.
    public static func lineWidth(contrast: ColorSchemeContrast) -> CGFloat { OuroButtonMetrics.outlineWidth(contrast: contrast) }

    /// Web's `gap-3` between a labelled separator's lines and its words.
    public static let labelGap: CGFloat = 12

    /// The width below which a description list stacks each term above its details: web's `sm` (28rem, 448 points)
    /// or `md` (32rem, 512). The list's own width decides, not the window's, so a list in a sheet stacks on an iPad too.
    public static func stackWidth(_ stackBelow: OuroDescriptionListBreakpoint) -> CGFloat {
        switch stackBelow {
        case .sm: 448
        case .md: 512
        }
    }

    /// Side by side, the terms' column is web's `min(40%, 14rem)`.
    public static let termColumnMaxWidth: CGFloat = 224
    public static let termColumnFraction: CGFloat = 0.4
    public static func termColumnWidth(listWidth: CGFloat) -> CGFloat { min(listWidth * termColumnFraction, termColumnMaxWidth) }

    /// Web's `py-3` around each pair side by side, `pt-3 pb-1` and `pb-3` stacked, and `gap-4` between the columns.
    public static let pairPadding: CGFloat = 12
    public static let stackedTermGap: CGFloat = 4
    public static let columnGap: CGFloat = 16

    /// At the accessibility text sizes a list always stacks, so the details keep the width.
    public static func alwaysStacks(at size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }

    /// What VoiceOver says for one pair: the term, then its details, as a reader hears web's `<dt>` and `<dd>`.
    public static func spokenPair(term: String, details: String) -> String { details.isEmpty ? term : "\(term), \(details)" }
}

/// Ouro HX's separator: a thin line between groups of content, horizontal or vertical, web's `Separator`.
///
/// ```swift
/// OuroSeparator()
/// HStack { OuroButton("Edit", variant: .plain) {}; OuroSeparator(.vertical); OuroButton("Share", variant: .plain) {} }
/// OuroSeparator(label: "or")
/// OuroSeparator(label: "New since you left · 2 messages", tone: .primary)
/// ```
///
/// A line is decoration to VoiceOver (Apple has no separator role, as SwiftUI's `Divider` has none), so it is hidden;
/// a label is read as text in its place, and only a horizontal line takes one. Use spacing instead where whitespace
/// alone separates the groups, and an ``OuroPageHeader`` at level 2 where the next group needs a name.
public struct OuroSeparator: View {
    let orientation: OuroSeparatorOrientation
    let label: String?
    let tone: OuroTone?
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    public init(_ orientation: OuroSeparatorOrientation = OuroDisplayMetrics.defaultOrientation, tone: OuroTone? = nil) {
        self.orientation = orientation
        self.label = nil
        self.tone = tone
    }

    /// A horizontal line with words in its middle, such as "or" between two ways to sign in.
    public init(label: String, tone: OuroTone? = nil) {
        self.orientation = .horizontal
        self.label = label
        self.tone = tone
    }

    public var body: some View {
        let palette = OuroSeparatorPalette(tone: tone, style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        let width = OuroDisplayMetrics.lineWidth(contrast: contrast)
        if let label {
            HStack(spacing: OuroDisplayMetrics.labelGap) {
                line(palette, width).frame(height: width).frame(maxWidth: .infinity)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Color(palette.label))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                line(palette, width).frame(height: width).frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        } else if orientation == .vertical {
            line(palette, width).frame(width: width).frame(maxHeight: .infinity)
        } else {
            line(palette, width).frame(height: width).frame(maxWidth: .infinity)
        }
    }

    private func line(_ palette: OuroSeparatorPalette, _ width: CGFloat) -> some View {
        Rectangle().fill(Color(palette.line)).accessibilityHidden(true)
    }
}

// MARK: Description list

/// Where a description list stops stacking, as on web: `sm` is 448 points of the list's own width, `md` 512.
public enum OuroDescriptionListBreakpoint: String, CaseIterable, Sendable { case sm, md }

/// One pair in an ``OuroDescriptionList``: what it is (`term`), and its value (`details`), as on web.
public struct OuroDescriptionItem {
    public let term: String
    let detailsText: String?
    let detailsView: AnyView?

    /// A term and its details as words: "Prep time", "20 minutes". VoiceOver hears them as one.
    public init(_ term: String, _ details: String) {
        self.term = term
        self.detailsText = details
        self.detailsView = nil
    }

    /// A term and details drawn as a view: a link, a badge, an avatar beside a name. Each part keeps its own element.
    public init(_ term: String, @ViewBuilder details: () -> some View) {
        self.term = term
        self.detailsText = nil
        self.detailsView = AnyView(details())
    }
}

/// The resolved colours of a description list: terms in the muted foreground and details in the foreground, each at
/// 5:1 on the page (7:1 under increased contrast); its lines as ``OuroSeparator``'s.
public struct OuroDescriptionListPalette: Sendable {
    public var term: Color.Resolved
    public var details: Color.Resolved
    public var line: Color.Resolved

    public init(style: OuroHXStyle) {
        let c = style.colors
        let page = OuroInk.r(c.background)
        term = OuroInk.readable(OuroInk.r(c.mutedForeground), on: page, style)
        details = OuroInk.readable(OuroInk.r(c.foreground), on: page, style)
        line = OuroSeparatorPalette(tone: nil, style: style).line
    }
}

/// Ouro HX's description list: one thing's details as pairs of a term and its value (a recipe's prep time and
/// servings, an account's email), web's `DescriptionList`.
///
/// ```swift
/// OuroDescriptionList([
///     OuroDescriptionItem("Prep time", "20 minutes"),
///     OuroDescriptionItem("Serves", "6"),
///     OuroDescriptionItem("Diet") { OuroBadge("Vegan", tone: .success, variant: .soft) },
/// ])
/// ```
///
/// Narrower than 448 points (its own width, as in a sheet or on an iPhone) each term sits above its details; from
/// there the terms form a column beside them, with a line between the pairs. At the accessibility text sizes it always
/// stacks. VoiceOver hears each pair as one: "Prep time, 20 minutes". Use ``OuroItemGroup`` instead for a list of
/// things a person opens or acts on.
public struct OuroDescriptionList: View {
    let items: [OuroDescriptionItem]
    let stackBelow: OuroDescriptionListBreakpoint
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ items: [OuroDescriptionItem], stackBelow: OuroDescriptionListBreakpoint = .sm) {
        self.items = items
        self.stackBelow = stackBelow
    }

    public var body: some View {
        let palette = OuroDescriptionListPalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        Group {
            if OuroDisplayMetrics.alwaysStacks(at: typeSize) {
                stacked(palette)
            } else {
                // The side-by-side layout asks for the breakpoint's width at least, so it is chosen only where the
                // list itself has that much room: web's container query.
                ViewThatFits(in: .horizontal) {
                    sideBySide(palette).frame(minWidth: OuroDisplayMetrics.stackWidth(stackBelow))
                    stacked(palette)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func stacked(_ palette: OuroDescriptionListPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { rule(palette) }
                VStack(alignment: .leading, spacing: OuroDisplayMetrics.stackedTermGap) {
                    term(item, palette)
                    details(item, palette)
                }
                .padding(.top, index == 0 ? 0 : OuroDisplayMetrics.pairPadding)
                .padding(.bottom, OuroDisplayMetrics.pairPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(PairElement(item: item))
            }
        }
    }

    private func sideBySide(_ palette: OuroDescriptionListPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { rule(palette) }
                PairRow {
                    term(item, palette)
                    details(item, palette)
                }
                .padding(.top, index == 0 ? 0 : OuroDisplayMetrics.pairPadding)
                .padding(.bottom, OuroDisplayMetrics.pairPadding)
                .modifier(PairElement(item: item))
            }
        }
    }

    private func rule(_ palette: OuroDescriptionListPalette) -> some View {
        Rectangle()
            .fill(Color(palette.line))
            .frame(height: OuroDisplayMetrics.lineWidth(contrast: contrast))
            .accessibilityHidden(true)
    }

    private func term(_ item: OuroDescriptionItem, _ palette: OuroDescriptionListPalette) -> some View {
        Text(item.term)
            .font(.body)
            .foregroundStyle(Color(palette.term))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func details(_ item: OuroDescriptionItem, _ palette: OuroDescriptionListPalette) -> some View {
        if let text = item.detailsText {
            Text(text)
                .font(.body)
                .foregroundStyle(Color(palette.details))
                .fixedSize(horizontal: false, vertical: true)
        } else if let view = item.detailsView {
            view.foregroundStyle(Color(palette.details))
        }
    }
}

/// A pair whose details are words is one element ("Prep time, 20 minutes"); one whose details are a view keeps each
/// part, so a link or a button in it stays its own control.
private struct PairElement: ViewModifier {
    let item: OuroDescriptionItem

    func body(content: Content) -> some View {
        if let text = item.detailsText {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(OuroDisplayMetrics.spokenPair(term: item.term, details: text)))
        } else {
            content.accessibilityElement(children: .contain)
        }
    }
}

/// A pair side by side: the term in web's `min(40%, 14rem)` column, the details in the rest, top-aligned.
private struct PairRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? OuroDisplayMetrics.stackWidth(.sm)
        let (t, d) = columns(width)
        let th = subviews[0].sizeThatFits(ProposedViewSize(width: t, height: nil)).height
        let dh = subviews[1].sizeThatFits(ProposedViewSize(width: d, height: nil)).height
        return CGSize(width: width, height: max(th, dh))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let (t, d) = columns(bounds.width)
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: t, height: nil))
        subviews[1].place(at: CGPoint(x: bounds.minX + t + OuroDisplayMetrics.columnGap, y: bounds.minY), proposal: ProposedViewSize(width: d, height: nil))
    }

    private func columns(_ width: CGFloat) -> (CGFloat, CGFloat) {
        let t = OuroDisplayMetrics.termColumnWidth(listWidth: width)
        return (t, max(0, width - t - OuroDisplayMetrics.columnGap))
    }
}
