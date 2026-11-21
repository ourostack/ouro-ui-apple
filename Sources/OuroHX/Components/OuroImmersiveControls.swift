public import SwiftUI

/// Where controls shown over immersive content stand: a top bar and a bottom bar, each in the band the hardware already
/// takes, never on the content's own layout.
///
/// The top bar starts at the safe area's top, or a short gap below the screen's edge where there is none (the status
/// band beside a camera). The bottom bar rests on the home indicator, in the band it takes, or the same gap above the
/// edge where there is none. Each
/// bar spans the width between the sides, kept clear of whatever the system reports covered beside it (a camera or
/// sensor housing, from `reservedRegions(kind: .occlusion)` on iOS 27.1): a housing in a corner moves only the bar that
/// shares its height, so a bar lower down uses the width under it. A side's safe inset is kept unless an occlusion
/// that lies wholly outside the bar's band explains it. A housing across the middle of the top can't be cleared
/// sideways, so the top bar steps below it.
///
/// Pure data, so a test can check it without drawing. From Gatefold's reader (build 53: Ari, "use the right under the
/// camera"), and Apple Books, Photos and Safari, which lay their bars over content that holds still.
public struct OuroImmersiveControlsPlacement: Equatable, Sendable {
    /// The top bar's frame, in the container's points.
    public var top: CGRect
    /// The bottom bar's frame, in the container's points.
    public var bottom: CGRect

    public init(top: CGRect, bottom: CGRect) {
        self.top = top
        self.bottom = bottom
    }

    /// The bars' frames in a container `size` with `safeArea` and the system's `occlusions` (container points), for a
    /// top bar `topHeight` and a bottom bar `bottomHeight` tall.
    public static func resolve(size: CGSize, safeArea: EdgeInsets, occlusions: [CGRect] = [], topHeight: CGFloat,
                               bottomHeight: CGFloat) -> Self {
        typealias M = OuroImmersiveControlsMetrics
        let regions = occlusions.filter { $0.width > 0 && $0.height > 0 && $0.intersects(CGRect(origin: .zero, size: size)) }
        var topY = max(safeArea.top, M.edgeGap)
        // A housing across the middle of the top: no side clears it, so the bar goes below it. One the safe area already
        // holds (an iPad's status bar) is cleared by starting at the safe area's top.
        for region in regions where region.minX < size.width / 2 && region.maxX > size.width / 2 && region.minY < topY + topHeight
            && region.maxY < size.height / 2 && region.maxY > safeArea.top {
            topY = max(topY, region.maxY + M.edgeGap)
        }
        // The bottom bar rests on the home indicator, in the band the indicator takes, as the top bar stands in the status
        // band: the rest of the safe area's foot is the content's.
        var bottomMaxY = size.height - max(min(safeArea.bottom, M.homeIndicatorBand), M.edgeGap)
        for region in regions where region.minX < size.width / 2 && region.maxX > size.width / 2 && region.maxY > bottomMaxY - bottomHeight
            && region.minY > size.height / 2 && region.minY < size.height - safeArea.bottom {
            bottomMaxY = min(bottomMaxY, region.minY - M.edgeGap)
        }
        let topBand = topY...(topY + topHeight)
        let bottomBand = (bottomMaxY - bottomHeight)...bottomMaxY
        func frame(_ band: ClosedRange<CGFloat>) -> CGRect {
            let (leading, trailing) = sides(band, size: size, safeArea: safeArea, regions: regions)
            let x = leading + M.sideGap
            return CGRect(x: x, y: band.lowerBound, width: max(0, size.width - trailing - M.sideGap - x), height: band.upperBound - band.lowerBound)
        }
        return Self(top: frame(topBand), bottom: frame(bottomBand))
    }

    /// What each side keeps clear in `band`: its safe inset, unless only an occlusion outside the band explains it, and
    /// every occlusion that shares the band's height.
    private static func sides(_ band: ClosedRange<CGFloat>, size: CGSize, safeArea: EdgeInsets, regions: [CGRect]) -> (CGFloat, CGFloat) {
        let gap = OuroImmersiveControlsMetrics.edgeGap
        let beside = regions.filter { $0.minY < band.upperBound + gap && $0.maxY > band.lowerBound - gap }
        let elsewhere = regions.filter { !beside.contains($0) }
        var leading = safeArea.leading, trailing = safeArea.trailing
        // The inset is the housing's own when a housing fills it; away from that housing's height, the side is free.
        if leading > 0, !beside.contains(where: { $0.minX < leading }), elsewhere.contains(where: { $0.minX < 1 && $0.maxX >= leading - 1 }) {
            leading = 0
        }
        if trailing > 0, !beside.contains(where: { $0.maxX > size.width - trailing }),
           elsewhere.contains(where: { $0.maxX > size.width - 1 && $0.minX <= size.width - trailing + 1 }) {
            trailing = 0
        }
        for region in beside where !(region.minX < size.width / 2 && region.maxX > size.width / 2) {
            if region.midX > size.width / 2 {
                trailing = max(trailing, size.width - region.minX)
            } else {
                leading = max(leading, region.maxX)
            }
        }
        return (leading, trailing)
    }
}

/// The numbers controls over immersive content are placed with.
public enum OuroImmersiveControlsMetrics {
    /// From the screen's edge to a bar, where the safe area gives no band (a screen with no status bar), and from a
    /// housing to a bar beside it.
    public static let edgeGap: CGFloat = 8
    /// The band the home indicator takes at the screen's foot: the indicator, 5 points tall, and the 8 under it. The
    /// bottom bar rests on it, never under it; a screen with no indicator (no bottom inset) keeps ``edgeGap``.
    public static let homeIndicatorBand: CGFloat = 13
    /// From a bar's ends to the screen's side or a housing, as Apple's floating toolbars stand.
    public static let sideGap: CGFloat = 16
    /// How a bar comes and goes: it slides in from its own edge (the top bar from the top, the bottom bar from the
    /// foot) on core's spring, and crossfades under Reduce Motion.
    public static func appearance(_ edge: VerticalEdge, reduceMotion: Bool) -> OuroAppearance {
        OuroAppearance.choose(.move(edge: edge == .top ? .top : .bottom), reduceMotion: reduceMotion)
    }
}

private struct OuroImmersiveControlsModifier<Top: View, Bottom: View>: ViewModifier {
    let isPresented: Bool
    let safeArea: EdgeInsets?
    let occlusions: [CGRect]?
    let top: Top
    let bottom: Bottom
    @State private var topHeight: CGFloat = 44
    @State private var bottomHeight: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // An overlay never changes the content's layout: it is sized to the content and drawn over it.
        content.overlay {
            GeometryReader { proxy in
                let placement = OuroImmersiveControlsPlacement.resolve(
                    size: proxy.size, safeArea: safeArea ?? proxy.safeAreaInsets, occlusions: occlusions ?? Self.systemOcclusions(in: proxy),
                    topHeight: topHeight, bottomHeight: bottomHeight)
                ZStack(alignment: .topLeading) {
                    if isPresented {
                        bar(top, width: placement.top.width, height: $topHeight)
                            .offset(x: placement.top.minX, y: placement.top.minY)
                            .transition(OuroImmersiveControlsMetrics.appearance(.top, reduceMotion: reduceMotion).transition)
                        bar(bottom, width: placement.bottom.width, height: $bottomHeight)
                            .offset(x: placement.bottom.minX, y: placement.bottom.minY)
                            .transition(OuroImmersiveControlsMetrics.appearance(.bottom, reduceMotion: reduceMotion).transition)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .animation(OuroImmersiveControlsMetrics.appearance(.top, reduceMotion: reduceMotion).step(reduceMotion: reduceMotion).animation,
                           value: isPresented)
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func bar(_ content: some View, width: CGFloat, height: Binding<CGFloat>) -> some View {
        Group {
            if #available(iOS 26, macOS 26, visionOS 26, *) {
                // One container per bar, so its pieces of glass blend and morph as the system's toolbars do.
                GlassEffectContainer { content }
            } else {
                content
            }
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height.wrappedValue = $0 }
    }

    /// What the system says is covered (a camera or sensor housing), in the proxy's points. The occlusion API comes
    /// with the iOS 27.1 SDK (SwiftUICore 8.0.85, as ``OuroFoldReader``); before it, nothing.
    static func systemOcclusions(in proxy: GeometryProxy) -> [CGRect] {
        #if canImport(SwiftUICore, _version: 8.0.85)
        if #available(iOS 27.1, macOS 27.1, *) {
            return proxy.reservedRegions(kind: .occlusion, options: .includeInactive).map(\.frame)
        }
        #endif
        return []
    }
}

extension View {
    /// Controls shown over immersive content (a book's page, a photo, a video, a map): a `top` bar and a `bottom` bar
    /// laid over this view, which never moves, scales or reflows for them.
    ///
    /// Each bar stands in the band the hardware already takes, the status band beside the camera at the top and the
    /// home indicator's band at the foot, clear of any sensor housing beside it (``OuroImmersiveControlsPlacement``).
    /// They come and go with Ouro's motion, a crossfade under Reduce Motion, and each bar is one glass container, so
    /// draw its pieces with Liquid Glass in squircle shapes (`Capsule(style: .continuous)`). Nothing is drawn behind
    /// them and nothing over the content: keep words out of the bands if no line may sit under a bar, as a book's
    /// margins do. Touches outside the bars reach the content.
    ///
    /// ```swift
    /// PhotoView(photo)
    ///     .ouroImmersiveControls(isPresented: showsControls) {
    ///         HStack { closeButton; Spacer(); shareButton }
    ///     } bottom: {
    ///         HStack { editButton; Spacer(); deleteButton }
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - safeArea: The screen's safe area around this view; nil reads this view's own. Pass it when a view above
    ///     this one ignores the safe area, as an edge-to-edge page does: below that, a view reads no insets at all.
    ///   - occlusions: What covers the screen, in this view's points; nil reads the system's report.
    public func ouroImmersiveControls<Top: View, Bottom: View>(
        isPresented: Bool, safeArea: EdgeInsets? = nil, occlusions: [CGRect]? = nil, @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) -> some View {
        modifier(OuroImmersiveControlsModifier(isPresented: isPresented, safeArea: safeArea, occlusions: occlusions, top: top(),
                                               bottom: bottom()))
    }
}
