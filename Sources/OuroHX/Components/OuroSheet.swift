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
    /// How large iOS 26 and later draw a sheet below its full height: 96%, measured in the gallery's UI tests (a
    /// 44-point button reads 42.2 points on screen).
    public static let drawnScale: CGFloat = 0.96
    /// The touch target inside a sheet, in layout points: 46, so that drawn at ``drawnScale`` it is still 44.
    /// `.ouroSheet` sets it as `ouroTouchTarget` for its content, so ``OuroButton``s there grow to match.
    public static let touchTarget: CGFloat = 46
    /// The close button's target, in layout points (44 as drawn).
    public static let closeTarget: CGFloat = touchTarget
    /// The close button's drawn disc, inside its target: 34 points, as on Apple's own sheets.
    public static let closeDisc: CGFloat = 30

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
    /// - The body scrolls when it is taller than the sheet; `footer` is the actions row, full width, primary last.
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
    @State private var header: CGFloat = 60
    @State private var bodyHeight: CGFloat = 200
    @State private var footerHeight: CGFloat = 0

    /// Header, body and actions row, measured as laid out.
    private var fittedHeight: CGFloat { max(160, header + bodyHeight + footerHeight + 16) }
    @State private var visible = false

    var body: some View {
        let p = OuroSheetPalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.bold))
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
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(p.closeMark))
                        .frame(width: OuroSheetMetrics.closeDisc, height: OuroSheetMetrics.closeDisc)
                        .modifier(CloseDisc(fill: Color(p.closeFill)))
                        .frame(width: OuroSheetMetrics.closeTarget, height: OuroSheetMetrics.closeTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.ouroPress)
                .accessibilityLabel(closeLabel)
                .accessibilityIdentifier(OuroSheetMetrics.closeIdentifier)
                .padding(.trailing, -10)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { header = $0 }
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            // A sheet without detents fits its content: header, body and actions row, measured as laid out.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, h in bodyHeight = h }
            if Footer.self != EmptyView.self {
                VStack(spacing: 10) { footer() }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
            }
        }
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
        .presentationDragIndicator(.visible)
        // Toasts sent while the sheet is open show above it, not behind it.
        .modifier(OuroToastHost())
        .modifier(SheetBackground(surface: Color(p.surface)))
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

/// The theme's surface behind the sheet, on iOS 26 too: the sheet's text and the components in it are made readable
/// on that surface (`contrast.text`), and a theme's surface is not the system sheet's glass. iOS 26 still floats a
/// partial sheet and rounds it.
private struct SheetBackground: ViewModifier {
    let surface: Color
    func body(content: Content) -> some View {
        content.presentationBackground(surface)
    }
}
