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
    /// The end of a sheet's content, scrolled to when the keyboard comes up at the accessibility sizes.
    static let endIdentifier = "ouro.sheet.end"

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
    ///   the accessibility sizes the whole sheet scrolls, title and actions too, and while the keyboard is up its end
    ///   (the field being typed in and the actions) stays in view.
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
    /// The room the sheet shows: its height less what the keyboard and safe areas inset.
    @State private var shown: CGFloat = 0

    /// Header, body and actions row, measured as laid out.
    private var fittedHeight: CGFloat { max(160, header + bodyHeight + footerHeight + 16) }
    /// At the accessibility sizes the whole sheet scrolls, title and actions too, not only its body.
    private var wholeSheetScrolls: Bool { typeSize.isAccessibilitySize }
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
                if let description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(Color(p.description))
                        .fixedSize(horizontal: false, vertical: true)
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
        // squeezed or pushed past the top of the screen; as the keyboard arrives, the end comes into view: the field
        // being typed in and the actions under it (VoiceOver still reads the words above first). Below those sizes the
        // title and actions stay put and only the body scrolls. The same views either way, only what scrolls changes,
        // so nothing is rebuilt when the text size changes.
        ScrollViewReader { proxy in
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
                    Color.clear.frame(height: 0).id(OuroSheetMetrics.endIdentifier)
                }
                // Below the accessibility sizes, exactly the room the sheet shows, above the keyboard when it is up: the
                // title and actions stay put and the body scrolls between them.
                .frame(height: wholeSheetScrolls || shown == 0 ? nil : shown)
            }
            .scrollDisabled(!wholeSheetScrolls)
            .scrollBounceBehavior(.basedOnSize)
            // At the accessibility sizes, as the room changes (the keyboard arriving), the end stays in view: the field
            // being typed in and the actions under it. Below them the outer view doesn't scroll, so this does nothing.
            .defaultScrollAnchor(.top, for: .initialOffset)
            .defaultScrollAnchor(wholeSheetScrolls ? .bottom : nil, for: .sizeChanges)
            // A scroll view keeps its size as the keyboard arrives and insets its content instead; the room shown is its
            // height less those insets.
            .onScrollGeometryChange(for: CGFloat.self) { g in
                max(0, g.containerSize.height - g.contentInsets.top - g.contentInsets.bottom)
            } action: { _, h in shown = h }
            // iOS 27 keeps the offset as the keyboard's inset arrives and as the content's size changes, where iOS 26
            // holds the end in view by the anchor above. So the end is scrolled to as the keyboard arrives, and again
            // when the room or content changes size (a taller keyboard, text wrapping) if the end was in view before:
            // someone who scrolled up to read stays where they are.
            .onScrollGeometryChange(for: KeyboardRoom.self) { g in
                let room = g.containerSize.height - g.contentInsets.bottom
                return KeyboardRoom(up: g.contentInsets.bottom > OuroSheetMetrics.keyboardInset,
                                    content: g.contentSize.height.rounded(), room: room.rounded(),
                                    atEnd: g.contentOffset.y + room >= g.contentSize.height - 1)
            } action: { was, now in
                guard now.up, wholeSheetScrolls else { return }
                let arrived = !was.up
                let resized = was.content != now.content || was.room != now.room
                guard arrived || (resized && was.atEnd) else { return }
                Task { @MainActor in
                    withAnimation(OuroMotion.animation(.smooth, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(OuroSheetMetrics.endIdentifier, anchor: .bottom)
                    }
                }
            }
        }
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
private struct KeyboardRoom: Equatable {
    var up: Bool
    var content: CGFloat
    var room: CGFloat
    /// Whether the end of the content is in view.
    var atEnd: Bool
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
