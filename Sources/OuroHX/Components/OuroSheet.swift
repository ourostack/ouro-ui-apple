public import SwiftUI

/// The resolved colours of a sheet as seen: the page's background in light, the raised popover colour in dark (so a
/// sheet has an edge over a dimmed black page), with its words at 5:1 (7:1 under increased contrast).
public struct OuroSheetPalette: Sendable {
    public var title: Color.Resolved
    public var description: Color.Resolved
    public var surface: Color.Resolved
    /// The close button's disc: the theme's muted fill, a step off the surface.
    public var closeFill: Color.Resolved
    /// The close button's xmark, readable on its disc.
    public var closeMark: Color.Resolved

    public init(style: OuroHXStyle) {
        let c = style.colors
        surface = OuroInk.r(style.scheme == .dark ? c.popover : c.background)
        // Always a visible step off the surface, even where a theme's muted colour is the popover's.
        closeFill = OuroColor.push(OuroInk.r(c.muted), against: surface, to: 1.2)
        closeMark = OuroInk.readable(OuroInk.r(c.mutedForeground), on: closeFill, style)
        title = OuroInk.readable(OuroInk.r(c.foreground), on: surface, style)
        description = OuroInk.readable(OuroInk.r(c.mutedForeground), on: surface, style)
    }
}

/// Metrics and motion every Ouro sheet shares, as data.
public enum OuroSheetMetrics {
    /// How much of its words' colour a sheet's rim takes: a hairline in dark, so it doesn't melt into the dimmed
    /// page; none in light, where the page dims to grey around a white sheet.
    public static func rimOpacity(scheme: ColorScheme) -> Double { scheme == .dark ? 0.12 : 0 }
    /// The rim's width, in points.
    public static let rimWidth: CGFloat = 0.5
    /// How large iOS 26 and later draw a sheet below its full height: 96%, measured in the gallery's UI tests (a
    /// 44-point button reads 42.2 points on screen).
    public static let drawnScale: CGFloat = 0.96
    /// The touch target inside a sheet, in layout points: 46, so that drawn at ``drawnScale`` it is still 44.
    /// `.ouroSheet` sets it as `ouroTouchTarget` for its content, so ``OuroButton``s there grow to match.
    public static let touchTarget: CGFloat = 46
    /// The close button's target, in layout points (44 as drawn).
    public static let closeTarget: CGFloat = touchTarget
    /// The close button's drawn disc, inside its target: 44 points, the size of iOS 26's own sheet close button.
    public static let closeDisc: CGFloat = 44
    /// The close button's glyph: 17 points, semibold, fixed so it stays inside its disc at every text size.
    public static let closeGlyph: CGFloat = 17

    /// Whether a sheet shows its grabber: only with several heights to drag between. A sheet that fits its content,
    /// or has one detent, has none, as on Apple's own.
    public static func showsGrabber(detents: Set<PresentationDetent>?) -> Bool { (detents?.count ?? 0) > 1 }

    /// A bottom inset larger than this, in points, is the keyboard rather than the home indicator's safe area.
    static let keyboardInset: CGFloat = 100
    /// The room kept above a focused field as a whole-sheet scroll brings it into view, in points.
    public static let keyboardFieldMargin: CGFloat = 16

    /// Where a whole-sheet scroll goes as the keyboard comes up at the accessibility sizes, as a content offset: as
    /// far toward its end (the actions) as keeps the focused `field` (in content coordinates) in view, its top first
    /// when it can't all fit; the end with no field. `viewport` is the scroll view's height, the insets what the
    /// safe area and keyboard cover of it.
    ///
    /// Neither edge of the room shown cuts through words or the actions: the keyboard's edge never falls inside the
    /// `actions` row, and the top edge never inside the `header`'s words except at one of `stops` (the gaps between
    /// their lines). Where the first answer would, the nearest offset that cuts nothing and keeps the field in view
    /// wins, even past the end (the caller pads the content to reach it); where none does, the first answer stands.
    public static func keyboardOffset(field: CGRect?, actions: ClosedRange<CGFloat>? = nil,
                                      header: ClosedRange<CGFloat>? = nil, stops: [CGFloat] = [],
                                      contentHeight: CGFloat, viewport: CGFloat, topInset: CGFloat,
                                      bottomInset: CGFloat) -> CGFloat {
        let start = -topInset
        let end = max(start, contentHeight + bottomInset - viewport)
        guard let field else { return end }
        let room = viewport - topInset - bottomInset
        var y = max(start, min(end, field.minY - keyboardFieldMargin - topInset))
        // The room shown ends at the keyboard's edge; the field is above the actions, so stopping short keeps it in view.
        func cutsActions(_ y: CGFloat) -> Bool {
            guard let actions else { return false }
            let shownEnd = y + topInset + room
            return actions.lowerBound < shownEnd - 0.5 && actions.upperBound > shownEnd + 0.5
        }
        if cutsActions(y) { y = max(start, actions!.lowerBound - topInset - room) }
        func cutsHeader(_ y: CGFloat) -> Bool {
            guard let header else { return false }
            let top = y + topInset
            return header.lowerBound < top - 0.5 && header.upperBound > top + 0.5 && !stops.contains { abs($0 - top) <= 0.5 }
        }
        func fieldInView(_ y: CGFloat) -> Bool {
            let top = y + topInset
            return field.minY >= top - 0.5 && (field.maxY <= top + room + 0.5 || field.minY <= top + keyboardFieldMargin + 0.5)
        }
        guard cutsHeader(y) else { return y }
        var candidates = stops.map { $0 - topInset } + [start, field.minY - keyboardFieldMargin - topInset]
        if let header { candidates.append(header.upperBound - topInset) }
        if let actions { candidates += [actions.lowerBound - topInset - room, actions.upperBound - topInset - room] }
        let fits = candidates.filter { $0 >= start - 0.5 && !cutsHeader($0) && !cutsActions($0) && fieldInView($0) }
        return fits.min { abs($0 - y) < abs($1 - y) } ?? y
    }


    /// The accessibility identifier of every `.ouroSheet`'s content, which `OuroHXTesting`'s audit looks for.
    public static let accessibilityIdentifier = "ouro.sheet"

    /// The accessibility identifier of every `.ouroSheet`'s close button.
    public static let closeIdentifier = "ouro.sheet.close"

    /// Whether a sheet is drawn at ``drawnScale``, judged by its close button: drawn shorter than its layout size
    /// (``closeTarget``), as it is in a sheet below full height on iOS 26 and later, and never on macOS or before
    /// iOS 26. Xcode's audit reads the scaled text as "Text clipped"; `ouroAccessibilityAudit` excuses that inside
    /// such a sheet only.
    public static func isDrawnScaled(closeButtonHeight: CGFloat) -> Bool {
        closeButtonHeight > 0 && closeButtonHeight < closeTarget * (1 + drawnScale) / 2
    }

    /// A sheet slides up from the bottom, as the system's do. Under Reduce Motion it appears without sliding and its
    /// content crossfades in.
    public static func presentation(reduceMotion: Bool) -> OuroAppearance {
        .choose(.move(edge: .bottom), reduceMotion: reduceMotion)
    }

    /// The transaction a sheet opens and closes in, its close button included: without animation under Reduce Motion.
    public static func transaction(reduceMotion: Bool) -> Transaction {
        var t = Transaction()
        t.disablesAnimations = presentation(reduceMotion: reduceMotion) == .fade
        return t
    }
}

extension View {
    /// Presents a sheet with Ouro HX's header, body and actions row: web's `Sheet`.
    ///
    /// ```swift
    /// .ouroSheet(isPresented: $saving, title: "Save to cookbook") {
    ///     CookbookList()
    /// } footer: {
    ///     OuroButton("Save", fullWidth: true) { save(); saving = false }
    /// }
    /// ```
    ///
    /// - The title names the sheet for VoiceOver and is its heading; `hideTitle` hides it visually only.
    /// - Its close button, at the top, is 44 points as drawn and named `closeLabel`, so VoiceOver users can always close it.
    /// - Without `detents` the sheet fits its content (up to the screen); pass `[.medium, .large]` to let it rest
    ///   at half height and drag up.
    /// - iOS draws a sheet below full height at 96%, so controls inside are sized to 46 points (`ouroTouchTarget`);
    ///   size your own rows with `@Environment(\\.ouroTouchTarget)` to match.
    /// - The body scrolls when it is taller than the sheet; `footer` is the actions row, full width, primary last. At
    ///   the accessibility sizes the whole sheet scrolls, title and actions too, and while the keyboard is up the
    ///   field being typed in stays in view, and the actions under it when they fit, never cut by the keyboard's edge:
    ///   a field last, just above the actions, brings them into view; one higher up keeps its own place in sight. Once someone scrolls, the
    ///   sheet stays where they put it.
    /// - Under Reduce Motion it appears without sliding up, and its content crossfades in.
    public func ouroSheet<Content: View, Footer: View>(
        isPresented: Binding<Bool>,
        title: String,
        description: String? = nil,
        hideTitle: Bool = false,
        detents: Set<PresentationDetent>? = nil,
        closeLabel: String = "Close",
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) -> some View {
        modifier(OuroSheetModifier(isPresented: isPresented, title: title, description: description, hideTitle: hideTitle, detents: detents, closeLabel: closeLabel, onDismiss: onDismiss, sheetContent: content, footer: footer))
    }

    /// A sheet with no actions row.
    public func ouroSheet<Content: View>(
        isPresented: Binding<Bool>,
        title: String,
        description: String? = nil,
        hideTitle: Bool = false,
        detents: Set<PresentationDetent>? = nil,
        closeLabel: String = "Close",
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ouroSheet(isPresented: isPresented, title: title, description: description, hideTitle: hideTitle, detents: detents, closeLabel: closeLabel, onDismiss: onDismiss, content: content) { EmptyView() }
    }
}

private struct OuroSheetModifier<SheetContent: View, Footer: View>: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let description: String?
    let hideTitle: Bool
    let detents: Set<PresentationDetent>?
    let closeLabel: String
    let onDismiss: (() -> Void)?
    let sheetContent: () -> SheetContent
    let footer: () -> Footer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The presentation, mirrored from `isPresented` so that under Reduce Motion it can change without animation.
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onAppear { shown = isPresented }
            .onChange(of: isPresented) { _, now in
                guard now != shown else { return }
                withTransaction(OuroSheetMetrics.transaction(reduceMotion: reduceMotion)) { shown = now }
            }
            .onChange(of: shown) { _, now in if isPresented != now { isPresented = now } }
            .sheet(isPresented: $shown, onDismiss: onDismiss) {
                OuroSheetBody(title: title, description: description, hideTitle: hideTitle, detents: detents, closeLabel: closeLabel, close: { withTransaction(OuroSheetMetrics.transaction(reduceMotion: reduceMotion)) { shown = false } }, content: sheetContent, footer: footer)
                    .environment(\.ouroTouchTarget, OuroSheetMetrics.touchTarget)
            }
    }
}

struct OuroSheetBody<Content: View, Footer: View>: View {
    let title: String
    let description: String?
    let hideTitle: Bool
    let detents: Set<PresentationDetent>?
    let closeLabel: String
    let close: () -> Void
    let content: () -> Content
    let footer: () -> Footer
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var header: CGFloat = 60
    @State private var bodyHeight: CGFloat = 200
    @State private var footerHeight: CGFloat = 0
    /// The whole-sheet scroll's height and the insets on it, as the scroll view reports them.
    @State private var room = SheetRoom()
    /// How much of the sheet the keyboard really covers, measured with UIKit's keyboard layout guide.
    @State private var keyboardCover: CGFloat?
    /// The bottom inset with the keyboard down: the home indicator's safe area.
    @State private var restingBottom: CGFloat = 0
    /// The room the sheet shows: its height less what the keyboard and safe areas inset. With the keyboard up, iOS 27
    /// lifts a fitted sheet clear of it yet still insets the scroll by the keyboard's whole height (333 points over a
    /// 379-point sheet, which squeezed the body to nothing), so the keyboard's inset is capped at what it covers.
    private var shown: CGFloat {
        let bottom = room.bottom > OuroSheetMetrics.keyboardInset
            ? min(room.bottom, keyboardCover.map { max($0, restingBottom) } ?? room.bottom) : room.bottom
        return max(0, room.container - room.top - bottom)
    }
    /// Whether, with the keyboard up at the accessibility sizes, the whole-sheet scroll keeps the focused field (and
    /// the actions, when they fit) in view as sizes change: from the keyboard's arrival until someone scrolls.
    @State private var followsKeyboard = false
    /// Room after the actions, with the keyboard up, so the sheet can stop where neither edge cuts words.
    @State private var keyboardTail: CGFloat = 0
    #if os(iOS) || os(visionOS)
    @State private var scrollHost = OuroSheetScrollHost()
    #endif

    /// Header, body and actions row, measured as laid out.
    private var fittedHeight: CGFloat { max(160, header + bodyHeight + footerHeight + 16) }
    /// At the accessibility sizes the whole sheet scrolls, title and actions too, not only its body.
    private var wholeSheetScrolls: Bool { typeSize.isAccessibilitySize }

    private func stopFollowingKeyboard() {
        followsKeyboard = false
        keyboardTail = 0
        #if os(iOS) || os(visionOS)
        scrollHost.tail = 0
        #endif
    }
    @State private var visible = false

    /// The title, description and close button.
    private var headerRow: some View {
        let p = OuroSheetPalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(p.title))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .modifier(VisuallyHidden(hidden: hideTitle))
                    .background { lineProbe(.title) }
                if let description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(Color(p.description))
                        .fixedSize(horizontal: false, vertical: true)
                        .background { lineProbe(.detail) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: close) {
                // A round close button, a solid muted disc as on Apple's own opaque sheets (glass would not show on
                // an opaque surface); drawn smaller than its target, which stays the full size.
                // A fixed glyph: it stays inside its disc at every text size; the button's name is what VoiceOver
                // and Voice Control use.
                Image(systemName: "xmark")
                    .font(.system(size: OuroSheetMetrics.closeGlyph, weight: .semibold))
                    .foregroundStyle(Color(p.closeMark))
                    .frame(width: OuroSheetMetrics.closeDisc, height: OuroSheetMetrics.closeDisc)
                    .modifier(CloseDisc(fill: Color(p.closeFill)))
                    .frame(width: OuroSheetMetrics.closeTarget, height: OuroSheetMetrics.closeTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.ouroPress)
            .accessibilityLabel(closeLabel)
            .accessibilityIdentifier(OuroSheetMetrics.closeIdentifier)
            // The disc's edge 17 points in from the sheet's, where iOS 26 sets its own.
            .padding(.trailing, -4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { header = $0 }
    }

    /// A probe behind the title or description, through which the keyboard scroll keeps the top edge between lines.
    @ViewBuilder private func lineProbe(_ role: LineRole) -> some View {
        #if os(iOS) || os(visionOS)
        OuroSheetScrollProbe(host: scrollHost, role: role == .title ? .title : .detail)
        #endif
    }
    private enum LineRole { case title, detail }

    /// The caller's content, on the layout margins.
    private var bodyContent: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
    }

    /// The actions row, when there is a footer.
    @ViewBuilder private var actionsRow: some View {
        if Footer.self != EmptyView.self {
            VStack(spacing: 10) { footer() }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
    }

    /// The header, body and actions.
    @ViewBuilder private var layout: some View {
        #if os(macOS)
        // macOS has no accessibility text sizes or on-screen keyboard: the title and actions stay put, the body scrolls.
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            ScrollView { bodyContent }
                .scrollBounceBehavior(.basedOnSize)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, h in bodyHeight = h }
            actionsRow
        }
        #else
        // At the accessibility sizes the whole sheet scrolls, title and actions too, so with the keyboard up nothing is
        // squeezed or pushed past the top of the screen; as the keyboard arrives, the field being typed in comes into
        // view, and the actions under it too when they fit, never cut by the keyboard's edge (VoiceOver still reads the words above first). Below those sizes the
        // title and actions stay put and only the body scrolls. The same views either way, only what scrolls changes,
        // so nothing is rebuilt when the text size changes.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                ScrollView { bodyContent }
                    .scrollBounceBehavior(.basedOnSize)
                    // At its full height when the whole sheet scrolls.
                    .scrollDisabled(wholeSheetScrolls)
                    .fixedSize(horizontal: false, vertical: wholeSheetScrolls)
                    // A sheet without detents fits its content: header, body and actions row, measured as laid out.
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, h in bodyHeight = h }
                actionsRow
                    .background { OuroSheetScrollProbe(host: scrollHost, role: .actions) }
                if keyboardTail > 0 {
                    Color.clear.frame(height: keyboardTail).accessibilityHidden(true)
                        .background { OuroSheetScrollProbe(host: scrollHost, role: .tail) }
                }
            }
            // Below the accessibility sizes, exactly the room the sheet shows, above the keyboard when it is up: the
            // title and actions stay put and the body scrolls between them.
            .frame(height: wholeSheetScrolls || shown == 0 ? nil : shown)
            .background { OuroSheetScrollProbe(host: scrollHost) }
        }
        .scrollDisabled(!wholeSheetScrolls)
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.top, for: .initialOffset)
        // A scroll view keeps its size as the keyboard arrives and insets its content instead; the room shown is its
        // height less those insets.
        .onScrollGeometryChange(for: SheetRoom.self) { g in
            SheetRoom(container: g.containerSize.height, top: g.contentInsets.top, bottom: g.contentInsets.bottom)
        } action: { _, now in
            room = now
            if now.bottom <= OuroSheetMetrics.keyboardInset { restingBottom = now.bottom }
        }
        .background {
            OuroSheetKeyboardEdge { cover in
                keyboardCover = cover
                scrollHost.keyboardCover = cover
                // The keyboard's real cover can settle after its inset does: place the sheet again by it.
                if followsKeyboard, wholeSheetScrolls { scrollHost.keepFocusedFieldInView(animated: !reduceMotion) }
            }
        }
        // At the accessibility sizes, as the keyboard arrives, the whole sheet scrolls as far toward its actions as
        // keeps the field being typed in wholly in view (`OuroSheetMetrics.keyboardOffset`), and keeps doing so as the
        // room or content changes size (a taller keyboard, text wrapping) until someone scrolls it themselves. iOS 27
        // keeps the offset as the keyboard's inset arrives, and iOS 26's bottom anchor went to the end whatever field
        // had focus, so the sheet places itself.
        .onScrollGeometryChange(for: KeyboardRoom.self) { g in
            KeyboardRoom(up: g.contentInsets.bottom > OuroSheetMetrics.keyboardInset,
                         content: g.contentSize.height.rounded(), room: (g.containerSize.height - g.contentInsets.bottom).rounded())
        } action: { was, now in
            guard now.up, wholeSheetScrolls else { return stopFollowingKeyboard() }
            if !was.up { followsKeyboard = true }
            guard followsKeyboard else { return }
            Task { @MainActor in scrollHost.keepFocusedFieldInView(animated: !reduceMotion) }
        }
        // Back to an ordinary size with the keyboard still up: the sheet is fitted again, and a tail would squeeze it.
        .onChange(of: wholeSheetScrolls) { _, scrolls in if !scrolls { stopFollowingKeyboard() } }
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { followsKeyboard = false }
        }
        .onAppear { scrollHost.onTail = { keyboardTail = $0 } }
        #endif
    }

    var body: some View {
        let p = OuroSheetPalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        layout
        #if !os(macOS)
        // A container the audit helper can find; on macOS it would add a group VoiceOver has to enter, and nothing
        // there is scaled.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(OuroSheetMetrics.accessibilityIdentifier)
        #endif
        #if os(macOS)
        // macOS has no detents and sizes a sheet to its content's ideal size, which a ScrollView doesn't give.
        .frame(minWidth: 360, minHeight: min(fittedHeight, 640))
        #endif
        .presentationDetents(detents ?? [.height(fittedHeight)])
        .presentationDragIndicator(OuroSheetMetrics.showsGrabber(detents: detents) ? .visible : .hidden)
        // Toasts sent while the sheet is open show above it, not behind it.
        .modifier(OuroToastHost())
        .modifier(SheetBackground(surface: Color(p.surface), rim: Color(p.title).opacity(OuroSheetMetrics.rimOpacity(scheme: scheme))))
        .opacity(visible || !reduceMotion ? 1 : 0)
        .onAppear { withAnimation(OuroMotion.animation(.base, reduceMotion: reduceMotion)) { visible = true } }
    }
}

private struct VisuallyHidden: ViewModifier {
    let hidden: Bool
    func body(content: Content) -> some View {
        if hidden {
            content.frame(width: 1, height: 1).clipped().opacity(0.011)
        } else {
            content
        }
    }
}

/// The close button's disc: the theme's muted fill.
private struct CloseDisc: ViewModifier {
    let fill: Color
    func body(content: Content) -> some View {
        content.background(fill, in: Circle())
    }
}

/// Whether the keyboard is up, and the heights a sheet's whole-sheet scroll view keeps its end in view across.
/// A scroll view's height and its top and bottom insets.
private struct SheetRoom: Equatable {
    var container: CGFloat = 0
    var top: CGFloat = 0
    var bottom: CGFloat = 0
}

private struct KeyboardRoom: Equatable {
    var up: Bool
    var content: CGFloat
    var room: CGFloat
}

/// The theme's surface behind the sheet, on iOS 26 too: the sheet's text and the components in it are made readable
/// on that surface (`contrast.text`), and a theme's surface is not the system sheet's glass. iOS 26 still floats a
/// partial sheet and rounds it.
private struct SheetBackground: ViewModifier {
    let surface: Color
    let rim: Color
    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            // The sheet's own corners, from its container, so the rim follows the shape iOS draws; stroked double and clipped,
                // so the half inside shows.
            content.presentationBackground {
                surface.overlay { ConcentricRectangle().stroke(rim, lineWidth: OuroSheetMetrics.rimWidth * 2).clipShape(ConcentricRectangle()) }
            }
        } else {
            content.presentationBackground(surface)
        }
    }
}

#if os(iOS) || os(visionOS)
import UIKit

/// The UIKit scroll view under a sheet's whole-sheet `ScrollView`, found from a probe view inside its content.
@MainActor final class OuroSheetScrollHost {
    weak var probe: UIView?
    /// A probe in the actions row, so the keyboard's edge can be kept from cutting through it.
    weak var actions: UIView?
    /// Probes behind the title and the description, so the top edge can be kept to the gaps between their lines.
    weak var title: UIView?
    weak var detail: UIView?
    /// How much of the sheet the keyboard really covers (``OuroSheetKeyboardEdge``), when measured.
    var keyboardCover: CGFloat?
    /// The room added after the actions so the sheet can scroll to an offset past its end, and how to ask for it.
    var tail: CGFloat = 0
    var onTail: (CGFloat) -> Void = { _ in }
    /// A probe behind the tail, so the content is measured without the tail it has laid out, not the one asked for.
    weak var tailView: UIView?
    private var animates = true

    /// The tail has been laid out at a new height: place the sheet now that the content holds it.
    func tailLaidOut() {
        guard tail > 0 else { return }
        DispatchQueue.main.async { [weak self] in self.map { $0.keepFocusedFieldInView(animated: $0.animates) } }
    }

    /// Scrolls as far toward the end as keeps the focused field in view, cutting through neither words nor the actions
    /// (``OuroSheetMetrics/keyboardOffset``).
    func keepFocusedFieldInView(animated: Bool) {
        animates = animated
        guard let scroll = probe?.enclosingScrollView else { return }
        // A tail asked for but not laid out yet: wait for it (``tailLaidOut()``), as the content's size is stale.
        let laidTail = tailView.flatMap { $0.window == nil ? nil : $0.bounds.height } ?? 0
        guard abs(laidTail - tail) <= 0.5 else { return }
        let field = Self.firstResponder(in: scroll).map { $0.convert($0.bounds, to: scroll) }
        let inset = scroll.adjustedContentInset
        // The keyboard's inset, capped at what it covers: iOS 27 insets a sheet it has lifted clear of the keyboard.
        let bottom = min(inset.bottom, keyboardCover.map { max($0, scroll.safeAreaInsets.bottom) } ?? inset.bottom)
        let actionsFrame = actions.map { $0.convert($0.bounds, to: scroll) }
        // The header's words, and the gaps between their lines: each text's height over its font's line height.
        var words: CGRect?
        var stops: [CGFloat] = []
        for (view, style) in [(title, UIFont.TextStyle.title2), (detail, .subheadline)] {
            guard let view, view.bounds.height > 0 else { continue }
            let frame = view.convert(view.bounds, to: scroll)
            words = words.map { $0.union(frame) } ?? frame
            let line = UIFont.preferredFont(forTextStyle: style, compatibleWith: view.traitCollection).lineHeight
            let lines = max(1, (frame.height / line).rounded())
            stops += (0...Int(lines)).map { frame.minY + CGFloat($0) * frame.height / lines }
        }
        let content = scroll.contentSize.height - laidTail
        let viewport = scroll.bounds.height
        let y = OuroSheetMetrics.keyboardOffset(field: field, actions: actionsFrame.map { $0.minY...$0.maxY },
                                                header: words.map { $0.minY...$0.maxY }, stops: stops,
                                                contentHeight: content, viewport: viewport, topInset: inset.top,
                                                bottomInset: bottom)
        // Past the end, the content grows to hold it first, and the sheet comes back here once it has (SwiftUI put a
        // scroll begun before the content grew back at the top).
        let needed = max(0, (y - (content + bottom - viewport)).rounded(.up))
        if abs(needed - tail) > 0.5 {
            tail = needed
            onTail(needed)
            return
        }
        guard abs(scroll.contentOffset.y - y) > 0.5 else { return }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: animated)
    }

    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for sub in view.subviews { if let found = firstResponder(in: sub) { return found } }
        return nil
    }
}

private extension UIView {
    /// The nearest scroll view that scrolls, above this view.
    var enclosingScrollView: UIScrollView? {
        var view = superview
        while let v = view {
            if let scroll = v as? UIScrollView, scroll.isScrollEnabled, !(v is UITextView) { return scroll }
            view = v.superview
        }
        return nil
    }
}

/// An empty view in a sheet's scrolling content, through which its host finds the scroll view.
private struct OuroSheetScrollProbe: UIViewRepresentable {
    let host: OuroSheetScrollHost
    enum Role { case content, actions, title, detail, tail }
    /// What it sits behind: the whole content, the actions row, the title, the description or the keyboard's tail.
    var role = Role.content
    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        updateUIView(view, context: context)
        return view
    }
    func updateUIView(_ view: ProbeView, context: Context) {
        switch role {
        case .content: host.probe = view
        case .actions: host.actions = view
        case .title: host.title = view
        case .detail: host.detail = view
        case .tail:
            host.tailView = view
            view.onResize = { [weak host] in host?.tailLaidOut() }
        }
    }

    final class ProbeView: UIView {
        var onResize: (() -> Void)?
        private var height: CGFloat = 0
        override func layoutSubviews() {
            super.layoutSubviews()
            guard abs(bounds.height - height) > 0.5 else { return }
            height = bounds.height
            onResize?()
        }
    }
}
/// A view the size of the sheet's scroll view that measures how much of it the keyboard covers, with UIKit's keyboard
/// layout guide, which follows the keyboard and the sheet wherever either moves.
private struct OuroSheetKeyboardEdge: UIViewRepresentable {
    let onCover: (CGFloat) -> Void
    func makeUIView(context: Context) -> EdgeView { EdgeView() }
    func updateUIView(_ view: EdgeView, context: Context) { view.onCover = onCover }

    final class EdgeView: UIView {
        var onCover: (CGFloat) -> Void = { _ in }
        private let edge = UIView()
        private var last: CGFloat = -1

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            edge.isUserInteractionEnabled = false
            edge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(edge)
            NSLayoutConstraint.activate([
                edge.topAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
                edge.leadingAnchor.constraint(equalTo: leadingAnchor),
                edge.widthAnchor.constraint(equalToConstant: 1),
                edge.heightAnchor.constraint(equalToConstant: 1),
            ])
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            let cover = max(0, bounds.height - edge.frame.minY)
            guard abs(cover - last) > 0.5 else { return }
            last = cover
            DispatchQueue.main.async { [onCover] in onCover(cover) }
        }
    }
}
#endif
