public import CoreGraphics

/// The axes a viewport scrolls on.
public struct FeelAxes: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let horizontal = FeelAxes(rawValue: 1)
    public static let vertical = FeelAxes(rawValue: 2)
    public static let both: FeelAxes = [.horizontal, .vertical]

    /// The axes this one leaves fixed.
    public var fixed: FeelAxes { FeelAxes.both.subtracting(self) }

    var words: String {
        switch self {
        case .horizontal: "scrolls sideways only"
        case .vertical: "scrolls up and down only"
        case .both: "scrolls both ways"
        default: "does not scroll"
        }
    }
}

/// One axis, for a drag.
public enum FeelAxis: String, Codable, Sendable {
    case horizontal, vertical

    var axes: FeelAxes { self == .horizontal ? .horizontal : .vertical }
    var way: String { self == .horizontal ? "sideways" : "up and down" }
}

/// A viewport as the accessibility tree reported it: a scroll view, a web view or the window, and the content drawn
/// in it (not in a viewport inside it).
public struct FeelViewportRead: Codable, Equatable, Sendable {
    public var key: String
    /// "scroll view", "web view", "list" or "window".
    public var kind: String
    public var frame: CGRect
    public var scrolls: FeelAxes
    /// Whether `scrolls` was guessed (accessibility does not say which way a scroll view scrolls) rather than declared.
    public var inferred: Bool
    public var content: [FeelElement]

    public init(key: String, kind: String, frame: CGRect, scrolls: FeelAxes, inferred: Bool, content: [FeelElement]) {
        self.key = key
        self.kind = kind
        self.frame = frame
        self.scrolls = scrolls
        self.inferred = inferred
        self.content = content
    }

    var name: String { kind == "window" ? "the window" : "\(kind) \"\(key)\"" }
}

/// One drag across a viewport on an axis it does not scroll, and where its content was before, while the finger was
/// down, and once it had lifted.
public struct FeelDrag: Codable, Equatable, Sendable {
    public var viewport: String
    public var axis: FeelAxis
    public var before: [String: CGRect]
    public var during: [[String: CGRect]]
    public var after: [String: CGRect]

    public init(viewport: String, axis: FeelAxis, before: [String: CGRect], during: [[String: CGRect]], after: [String: CGRect]) {
        self.viewport = viewport
        self.axis = axis
        self.before = before
        self.during = during
        self.after = after
    }
}

/// Viewport holds still, under the content is the canvas: no scroll view, web view or window pans on an axis it does
/// not scroll, and no content is wider or taller than its viewport on an axis that is fixed.
///
/// From Gatefold, 2026-11-27: the reading page could be dragged sideways, cutting off the text's left edge, while
/// every check passed (Ari: "being able to mess with viewport is very much something ouro feel should be catching").
/// Two readings judge it. Content past a viewport's edge on a fixed axis is a page wider than its window, which a
/// finger can pan, or which is simply cut off. A drag along a fixed axis that moves the content, even if it springs
/// back once the finger lifts, is the pan itself.
public enum FeelViewport {
    /// A point of slack for rounding at a viewport's edge.
    public static let tolerance: CGFloat = 1
    /// Content that moves more than this along a fixed axis during a drag has panned.
    public static let panTolerance: CGFloat = 2

    /// Content past the viewport's edges on its fixed axes, one finding per viewport and side.
    ///
    /// Images are left to the drag: a cover filled to its frame and cropped, or a hero that stretches as the page is
    /// pulled, reports a frame wider than the page while nothing can be panned (Spoonjoy's recipe cover, 2026-11-27).
    /// If such an image does pan, the drag across it says so.
    public static func overflow(_ viewport: FeelViewportRead, pose: String) -> [FeelFinding] {
        let fixed = viewport.scrolls.fixed
        guard !fixed.isEmpty else { return [] }
        let v = viewport.frame
        var findings: [FeelFinding] = []
        func side(_ name: String, _ axis: FeelAxis, _ past: (CGRect) -> CGFloat) {
            guard fixed.contains(axis.axes) else { return }
            let over = viewport.content.filter { $0.frame.width > 0 && $0.frame.height > 0 && $0.type != "image" }
                .map { ($0, past($0.frame)) }.filter { $0.1 > tolerance }
            guard let worst = over.max(by: { $0.1 < $1.1 }) else { return }
            let others = over.count > 1 ? " and \(over.count - 1) more" : ""
            findings.append(FeelFinding(
                what: "\(worst.0.type) \"\(worst.0.key)\"\(others) run\(over.count > 1 ? "" : "s") "
                    + "\(FeelResult.number(worst.1.rounded())) pt past the \(name) of \(viewport.name), which "
                    + "\(viewport.scrolls.words), in \(pose): content wider or taller than its viewport on a fixed "
                    + "axis can be panned there, or is cut off",
                inferred: viewport.inferred))
        }
        side("leading side", .horizontal) { v.minX - $0.minX }
        side("trailing side", .horizontal) { $0.maxX - v.maxX }
        side("top", .vertical) { v.minY - $0.minY }
        side("bottom", .vertical) { $0.maxY - v.maxY }
        return findings
    }

    /// The drag's verdict: nil when the content held still along the drag's axis.
    ///
    /// Content pans as a whole, so a frame has moved only as far as both of its edges moved the same way. A text that
    /// grew or shrank (its words changed as the page loaded: Spoonjoy's Chefs, 2026-11-27) moves one edge, not both.
    public static func panned(_ drag: FeelDrag, in viewport: FeelViewportRead, pose: String) -> FeelFinding? {
        func along(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let (low, high) = drag.axis == .horizontal ? (b.minX - a.minX, b.maxX - a.maxX) : (b.minY - a.minY, b.maxY - a.maxY)
            return low * high > 0 ? min(abs(low), abs(high)) : 0
        }
        var most: CGFloat = 0, stays: CGFloat = 0
        for (key, start) in drag.before {
            for sample in drag.during { if let f = sample[key] { most = max(most, along(start, f)) } }
            if let f = drag.after[key] { stays = max(stays, along(start, f)) }
        }
        most = max(most, stays)
        guard most > panTolerance else { return nil }
        let how = stays > panTolerance
            ? "and left it \(FeelResult.number(stays.rounded())) pt off once the finger lifted"
            : "while the finger was down, then it sprang back"
        return FeelFinding(
            what: "a drag \(drag.axis == .horizontal ? "across" : "up") \(viewport.name), which \(viewport.scrolls.words), "
                + "moved its content \(FeelResult.number(most.rounded())) pt \(drag.axis.way) \(how), in \(pose)",
            inferred: viewport.inferred)
    }

    /// Whether the drag changed what is on screen (a page turn, a new screen) rather than moving it: most of what it
    /// watched was gone once the finger lifted.
    public static func changedScreen(_ drag: FeelDrag) -> Bool {
        !drag.before.isEmpty && drag.before.keys.filter { drag.after[$0] == nil }.count * 2 > drag.before.count
    }

    /// One pose: every viewport's overflow, and every drag. `undragged` names each viewport and fixed axis no drag
    /// could cross (too small, or covered by the viewports and controls inside it): each is said in a note, and when it
    /// is the largest viewport and nothing was dragged at all, the drags could not be checked.
    public static func check(_ viewports: [FeelViewportRead], drags: [FeelDrag], undragged: [String: [FeelAxis]] = [:],
                             pose: String) -> FeelResult {
        var findings: [FeelFinding] = []
        for viewport in viewports { findings += overflow(viewport, pose: pose) }
        for viewport in viewports {
            guard let axes = undragged[viewport.key], !axes.isEmpty else { continue }
            findings.append(.note("no drag \(axes.map(\.way).joined(separator: " or ")) could cross \(viewport.name) in \(pose) "
                + "(too small, or covered by what is inside it), so only its overflow was judged", inferred: false))
        }
        let largest = viewports.filter { $0.kind != "window" }.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            ?? viewports.first
        if drags.isEmpty, let largest, let axes = undragged[largest.key], !axes.isEmpty {
            findings.append(.couldNotCheck("no drag could cross \(largest.name), the largest viewport, in \(pose), so whether it pans was not seen"))
        }
        var judged = 0
        for drag in drags {
            guard let viewport = viewports.first(where: { $0.key == drag.viewport }) else { continue }
            if drag.before.isEmpty {
                findings.append(.couldNotCheck("nothing in \(viewport.name) could be watched during a drag \(drag.axis.way) in \(pose)"))
                continue
            }
            if changedScreen(drag) {
                findings.append(.note("a drag \(drag.axis.way) across \(viewport.name) changed what was on screen (a page "
                    + "turn or a new screen) in \(pose), so it was taken as a gesture of the app's, not a pan"
                    + (viewport.inferred ? "; if it pages that way, say so with scrolling:" : ""), inferred: true))
                continue
            }
            judged += 1
            if let finding = panned(drag, in: viewport, pose: pose) { findings.append(finding) }
        }
        let content = viewports.reduce(0) { $0 + $1.content.count }
        if content == 0 { findings.append(.couldNotCheck("no content was on screen in \(pose)")) }
        let guessed = viewports.filter { $0.inferred }.map(\.name)
        if !guessed.isEmpty {
            findings.append(.note("accessibility does not say which way a scroll view scrolls, so " + guessed.joined(separator: ", ")
                + " \(guessed.count == 1 ? "was" : "were") taken by \(guessed.count == 1 ? "its" : "their") content's "
                + "shape; declare a pager or carousel with scrolling:", inferred: true))
        }
        let found = findings.filter { !$0.unchecked && !$0.note }.count
        return FeelResult.judged(check: FeelCheck.viewportHolds.name,
                                 passing: "\(viewports.count) viewports hold still in \(pose) (\(judged) drags on fixed axes)",
                                 failing: { _ in "\(found == 1 ? "a viewport" : "viewports") \(found == 1 ? "moves" : "move") on a fixed axis in \(pose)" },
                                 measures: ["viewports": Double(viewports.count), "drags": Double(judged), "content": Double(content)],
                                 findings: findings)
    }

    /// Several poses as one result: it passes only if every pose does.
    public static func combine(_ results: [FeelResult]) -> FeelResult {
        guard results.count > 1 else { return results.first ?? check([], drags: [], pose: "no pose") }
        let failed = results.filter { !$0.passed }.count
        return FeelResult.judged(check: FeelCheck.viewportHolds.name,
                                 passing: "every viewport holds still in \(results.count) poses",
                                 failing: { _ in "viewports move on a fixed axis in \(failed) of \(results.count) poses" },
                                 measures: ["poses": Double(results.count),
                                            "drags": results.reduce(0) { $0 + ($1.measures["drags"] ?? 0) }],
                                 findings: results.flatMap(\.findings), environment: results.first?.environment)
    }

    /// Which way a viewport scrolls, guessed from its content's shape: content that runs past its sides and nowhere
    /// past its top or bottom is a carousel or pager, which scrolls sideways, so long as each piece past the sides is a
    /// card or a page (no wider than the viewport). A line wider than its viewport is never a card: that viewport
    /// scrolls up and down, and the line is what pans. Anything else scrolls up and down; so do a web page and a list.
    public static func guessAxes(kind: String, frame: CGRect, content: [CGRect]) -> FeelAxes {
        if kind == "web view" || kind == "list" { return .vertical }
        let past = content.filter { $0.minX < frame.minX - tolerance || $0.maxX > frame.maxX + tolerance }
        let down = content.contains { $0.minY < frame.minY - tolerance || $0.maxY > frame.maxY + tolerance }
        let cards = !past.isEmpty && !past.contains { $0.width > frame.width + tolerance }
        return cards && !down ? .horizontal : .vertical
    }

    /// The axes to drag along at a point: those every viewport around it leaves fixed (a carousel in a list leaves
    /// none: the list scrolls the way the carousel doesn't).
    public static func fixedAt(_ chain: [FeelAxes]) -> FeelAxes {
        chain.reduce(FeelAxes.both) { $0.intersection($1.fixed) }
    }
}
