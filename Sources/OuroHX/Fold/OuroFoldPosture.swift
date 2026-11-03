public import CoreGraphics

/// The hinge of a foldable, as SwiftUI's `onHingeChange` reports it (iOS 27.1). From Gatefold's `HingeState`.
public enum OuroHinge: Equatable, Sendable {
    /// No hinge, or an OS or SDK that cannot say.
    case none
    case closed
    /// Bent: 0° is shut, 180° flat.
    case partiallyOpen(angleDegrees: Double)
    case fullyOpen

    public var angleDegrees: Double? {
        if case let .partiallyOpen(angle) = self { return angle }
        return nil
    }

    /// 0 (flat) to 1 (bent to 90° or more): how deep a spine shadow should be. Effect only, never layout. From
    /// Gatefold's spine shadow.
    public var bend: Double {
        guard let angle = angleDegrees else { return 0 }
        return min(1, max(0, (180 - angle) / 90))
    }
}

/// A `.division` reserved region (iOS 27.1): where the screen folds, in the container's coordinates.
public struct OuroFoldRegion: Equatable, Sendable {
    public var frame: CGRect
    /// iOS marks the iPhone Duo's fold inactive while it lies open flat; it still marks where two pages meet.
    public var isActive: Bool

    public init(frame: CGRect, isActive: Bool) {
        self.frame = frame
        self.isActive = isActive
    }

    /// Taller than wide: the screen is held like a book.
    public var isVertical: Bool { frame.height > frame.width }
}

/// Two panes and the fold between them.
public struct OuroFoldSplit: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// The system reported the fold.
        case hardware
        /// The hinge is bent but no region came: the split falls at the middle, where the Duo folds.
        case screenMiddle
    }

    /// The top pane (tabletop) or the leading pane (book).
    public var first: CGRect
    /// The band nothing tappable or readable may sit on, margins included.
    public var fold: CGRect
    /// The bottom pane (tabletop) or the trailing pane (book).
    public var second: CGRect
    public var source: Source

    public init(first: CGRect, fold: CGRect, second: CGRect, source: Source) {
        self.first = first
        self.fold = fold
        self.second = second
        self.source = source
    }
}

/// How a container should lay out for the way a foldable is held. Generalized from Spoonjoy's `TabletopLayout` and
/// `FoldRegionChoice` and Gatefold's `ReaderLayoutResolver`; pure, so every posture is unit tested.
public enum OuroFoldPosture: Equatable, Sendable {
    /// No fold to lay out around.
    case single
    /// Folded shut (the cover screen).
    case closed
    /// Held tall and bent like a small laptop, or open with an active horizontal fold: content above, controls below.
    case tabletop(OuroFoldSplit)
    /// Held wide with a vertical fold, active or not: two facing pages.
    case book(OuroFoldSplit)

    public var tabletop: OuroFoldSplit? { if case let .tabletop(split) = self { split } else { nil } }
    public var book: OuroFoldSplit? { if case let .book(split) = self { split } else { nil } }

    /// The numbers the resolution uses. The defaults are Spoonjoy's, which shipped on the iPhone Duo.
    public struct Rules: Equatable, Sendable {
        /// The shortest a pane may be; below it the posture falls back to one page.
        public var minimumPaneLength: Double = 260
        /// Clear space on each side of the fold's centre line. A reported fold wider than this keeps its width.
        public var foldMargin: Double = 24
        /// The bends that stand up as a tabletop. Spoonjoy's bands: under 60° is too shallow to stand on, and from 150°
        /// the screen lies flat. Spoonjoy's 140° to 150° gap, which it left to the hinge status, counts as a tabletop here.
        public var tabletopAngles: Range<Double> = 60..<150

        public init() {}
        public static let standard = Rules()
    }

    /// The posture for a container of `size`, given the hinge and the `.division` regions the system reports
    /// (queried with `.includeInactive`).
    public static func resolve(size: CGSize, hinge: OuroHinge, regions: [OuroFoldRegion], rules: Rules = .standard) -> OuroFoldPosture {
        if hinge == .closed { return .closed }
        let bounds = CGRect(origin: .zero, size: size)
        // A region can be reported for another window or screen; a zero-width fold still counts when it lies inside.
        let inside = regions.filter { bounds.intersects($0.frame.insetBy(dx: -0.5, dy: -0.5)) }
        let ordered = inside.filter(\.isActive) + inside.filter { !$0.isActive }

        if size.width > size.height,
           let fold = ordered.first(where: { $0.isVertical && $0.frame.height >= size.height / 2 }) {
            return split(bounds, along: .vertical, at: fold.frame.midX, thickness: fold.frame.width, source: .hardware, rules).map(Self.book) ?? .single
        }
        if size.height > size.width {
            let bent = hinge.angleDegrees.map(rules.tabletopAngles.contains) ?? false
            // Bent, the fold's real position wins even when the region is inactive (the Duo reports it inactive
            // whether flat or half open, Gatefold found). Not bent, only an active fold splits the screen.
            if let fold = ordered.first(where: { ($0.isActive || bent) && !$0.isVertical && $0.frame.width >= size.width / 2 }) {
                return split(bounds, along: .horizontal, at: fold.frame.midY, thickness: fold.frame.height, source: .hardware, rules).map(Self.tabletop) ?? .single
            }
            if bent {
                return split(bounds, along: .horizontal, at: bounds.midY, thickness: 0, source: .screenMiddle, rules).map(Self.tabletop) ?? .single
            }
        }
        return .single
    }

    enum Axis { case horizontal, vertical }

    static func split(_ bounds: CGRect, along axis: Axis, at centre: CGFloat, thickness: CGFloat, source: OuroFoldSplit.Source, _ rules: Rules) -> OuroFoldSplit? {
        let band = max(thickness, rules.foldMargin * 2)
        let length = axis == .horizontal ? bounds.height : bounds.width
        let start = max(0, centre - band / 2)
        let end = min(length, centre + band / 2)
        guard start >= rules.minimumPaneLength, length - end >= rules.minimumPaneLength else { return nil }
        switch axis {
        case .horizontal:
            return .init(first: CGRect(x: 0, y: 0, width: bounds.width, height: start),
                         fold: CGRect(x: 0, y: start, width: bounds.width, height: end - start),
                         second: CGRect(x: 0, y: end, width: bounds.width, height: length - end), source: source)
        case .vertical:
            return .init(first: CGRect(x: 0, y: 0, width: start, height: bounds.height),
                         fold: CGRect(x: start, y: 0, width: end - start, height: bounds.height),
                         second: CGRect(x: end, y: 0, width: length - end, height: bounds.height), source: source)
        }
    }
}
