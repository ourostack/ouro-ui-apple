#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
public import CoreGraphics
import Foundation
public import OuroFeelCore
public import XCTest

extension OuroFeel {
    // MARK: Viewport holds still

    /// Viewport holds still (the content is the canvas): in each pose, no scroll view, web view or the window pans on
    /// an axis it does not scroll, and no content is wider or taller than its viewport on an axis that is fixed.
    ///
    /// It reads every viewport on screen and what is drawn in it, then drags across each one along every axis that it
    /// and every viewport around it leave fixed (leftward, from three quarters of the way across to under a third,
    /// and upward, so the drag is never the system's back swipe or a sheet's pull down), watching a few of its texts
    /// while the finger is down and once it has lifted. Content that moved along the drag's axis panned, even if it
    /// sprang back. A drag never starts in a viewport inside the one it judges (a carousel in a list), on a switch,
    /// slider or field, and it leaves a list row's own content out, since a row slides to show its swipe actions on
    /// purpose. A drag that changed what was on screen (a page turn) is noted as the app's own gesture, not judged.
    ///
    /// Accessibility does not say which way a scroll view scrolls. A web view and a list scroll up and down; another
    /// scroll view scrolls sideways when its content runs past its sides and nowhere past its top or bottom (a carousel,
    /// a pager), and up and down otherwise. Declare a viewport that the guess gets wrong (a pager whose next page is
    /// not in the tree) by identifier or label in `scrolling`; findings on a guessed axis are marked as inference.
    /// Run it on a screen at rest, with no sheet up: a sheet's drag moves it on purpose.
    public func viewportHolds(scrolling: [String: FeelAxes] = [:], poses: [FeelPose] = FeelPose.roundTrip) -> FeelResult {
        var results: [FeelResult] = []
        for pose in poses {
            pose.apply(self)
            results.append(viewportHoldsNow(scrolling: scrolling, pose: pose.name))
        }
        #if os(iOS)
        if poses.contains(where: { $0.orientation != nil }) { FeelPose.portrait.apply(self) }
        #endif
        var result = FeelViewport.combine(results)
        result.environment = environment
        return result
    }

    func viewportHoldsNow(scrolling: [String: FeelAxes], pose: String) -> FeelResult {
        let screen = viewports(scrolling: scrolling)
        var drags: [FeelDrag] = []
        for node in screen.nodes {
            let fixed = FeelViewport.fixedAt(node.chain)
            for axis in [FeelAxis.horizontal, .vertical] where fixed.contains(axis == .horizontal ? .horizontal : .vertical) {
                guard let (from, to, start) = dragPath(node, axis: axis, screen: screen) else { continue }
                let anchors = dragAnchors(node, avoiding: start, screen: screen)
                drags.append(drag(node.read.key, axis: axis, from: from, to: to, anchors: anchors))
            }
        }
        return FeelViewport.check(screen.nodes.map(\.read), drags: drags, pose: pose)
    }

    /// A viewport on screen, with what a drag across it needs.
    struct ViewportNode {
        var read: FeelViewportRead
        /// The axes each viewport from the outermost to this one scrolls.
        var chain: [FeelAxes]
        var anchors: [ViewportAnchor]
        var depth: Int
        var parent: Int
    }

    /// Something a drag watches, and how to find it again.
    struct ViewportAnchor {
        var key: String
        var type: XCUIElement.ElementType
        var query: String
        var byIdentifier: Bool
        var frame: CGRect
        var cell: CGRect?
    }

    struct ViewportScreen {
        var window: CGRect
        var nodes: [ViewportNode]
        /// Controls a drag must not start on: switches, sliders, fields.
        var avoid: [CGRect]
        /// How many times each anchor's query matches on screen; only unique ones are watched.
        var counts: [String: Int]
    }

    static let dragAvoid: Set<XCUIElement.ElementType> = [
        .switch, .toggle, .slider, .stepper, .segmentedControl, .picker, .pickerWheel, .datePicker, .textField,
        .secureTextField, .searchField, .textView,
    ]

    /// Every viewport on screen (the window first, then each scroll view and web view) and the content drawn in it.
    func viewports(scrolling: [String: FeelAxes]) -> ViewportScreen {
        guard let root = try? app.snapshot() else { return ViewportScreen(window: .zero, nodes: [], avoid: [], counts: [:]) }
        let window = Self.mainWindow(root)
        var nodes = [ViewportNode(read: FeelViewportRead(key: "window", kind: "window", frame: window, scrolls: .none,
                                                         inferred: false, content: []),
                                  chain: [.none], anchors: [], depth: 0, parent: 0)]
        var nested: [Int: [CGRect]] = [:]
        var avoid: [CGRect] = [], counts: [String: Int] = [:]
        var unnamed: [String: Int] = [:]
        func walk(_ node: any XCUIElementSnapshot, in index: Int, cell: CGRect?) {
            let type = node.elementType, identifier = node.identifier, label = node.label, frame = node.frame
            let enabled = node.isEnabled
            if type == .keyboard { return }
            if Self.dragAvoid.contains(type) { avoid.append(frame) }
            var current = index, cell = cell
            if Self.scrollTypes.contains(type), frame.width > 0, frame.height > 0 {
                let kind = type == .webView ? "web view" : (type == .table || type == .collectionView) && Self.isList(node) ? "list" : "scroll view"
                var key = identifier.isEmpty ? label : identifier
                if key.isEmpty {
                    unnamed[kind, default: 0] += 1
                    key = "\(kind) \(unnamed[kind]!)"
                }
                let declared = scrolling[identifier] ?? scrolling[label]
                nested[index, default: []].append(frame)
                nodes.append(ViewportNode(read: FeelViewportRead(key: key, kind: kind, frame: frame, scrolls: declared ?? .vertical,
                                                                 inferred: declared == nil, content: []),
                                          chain: nodes[index].chain + [declared ?? .vertical], anchors: [],
                                          depth: nodes[index].depth + 1, parent: index))
                current = nodes.count - 1
                if declared == nil, kind == "list" { nodes[current].read.inferred = false }
            } else if type == .cell {
                cell = frame
            }
            let content = type == .staticText || type == .image || (Self.controlTypes.contains(type) && type != .cell && enabled)
            if content, frame.width > 0, frame.height > 0, !(type != .staticText && identifier.isEmpty && label.isEmpty) {
                let shown = identifier.isEmpty ? (type == .staticText ? "words \(FeelPlace.fingerprint(label))" : label) : identifier
                let query = identifier.isEmpty ? label : identifier
                nodes[current].read.content.append(FeelElement(key: shown, type: Self.kind(type), frame: frame))
                if !query.isEmpty {
                    counts[query, default: 0] += 1
                    nodes[current].anchors.append(ViewportAnchor(key: shown, type: type, query: query,
                                                                 byIdentifier: !identifier.isEmpty, frame: frame, cell: cell))
                }
            }
            for child in node.children { walk(child, in: current, cell: cell) }
        }
        walk(root, in: 0, cell: nil)
        // Guess each undeclared scroll view's axes from its content, its nested viewports included.
        for i in nodes.indices where i > 0 && nodes[i].read.inferred {
            let r = nodes[i].read
            let shapes = r.content.map(\.frame) + (nested[i] ?? [])
            let axes = FeelViewport.guessAxes(kind: r.kind, frame: r.frame, content: shapes)
            nodes[i].read.scrolls = axes
            nodes[i].chain[nodes[i].chain.count - 1] = axes
        }
        // A nested viewport's chain was built before its parent's guess: rebuild each from its parent's. Parents come
        // before children in `nodes`, so one pass in order is enough.
        for i in nodes.indices where i > 0 { nodes[i].chain = nodes[nodes[i].parent].chain + [nodes[i].read.scrolls] }
        return ViewportScreen(window: window, nodes: nodes, avoid: avoid, counts: counts)
    }

    /// A table or collection view whose children are rows (cells), read as a list that scrolls up and down; a
    /// collection view laid out as a sideways row of cells (a carousel) is not.
    static func isList(_ node: any XCUIElementSnapshot) -> Bool {
        let cells = node.children.filter { $0.elementType == .cell }.map(\.frame)
        guard cells.count >= 2 else { return node.elementType == .table }
        let side = cells.dropFirst().contains { abs($0.minY - cells[0].minY) < 1 && abs($0.minX - cells[0].minX) > 1 }
        return !side
    }

    /// Where a drag along `axis` across `node` goes, and the point it starts at; nil when no part of the viewport is
    /// clear of the viewports inside it, the controls a drag would move, and the window's edges.
    func dragPath(_ node: ViewportNode, axis: FeelAxis, screen: ViewportScreen)
        -> (XCUICoordinate, XCUICoordinate, CGPoint)? {
        let visible = node.read.frame.intersection(screen.window)
        guard !visible.isNull, visible.width >= 120, visible.height >= 120 else { return nil }
        // The viewports deeper than this one under a point: a drag there would judge them, not this one.
        let deeper = screen.nodes.filter { $0.depth > node.depth }.map(\.read.frame)
        func clear(_ p: CGPoint) -> Bool {
            visible.contains(p) && !deeper.contains { $0.contains(p) } && !screen.avoid.contains { $0.contains(p) }
        }
        for share in [0.5, 0.35, 0.65, 0.25, 0.75] as [CGFloat] {
            let a: CGPoint, b: CGPoint
            if axis == .horizontal {
                let y = visible.minY + visible.height * share
                a = CGPoint(x: visible.minX + visible.width * 0.75, y: y)
                b = CGPoint(x: visible.minX + visible.width * 0.3, y: y)
            } else {
                let x = visible.minX + visible.width * share
                a = CGPoint(x: x, y: visible.minY + visible.height * 0.7)
                b = CGPoint(x: x, y: visible.minY + visible.height * 0.3)
            }
            if clear(a), clear(b) { return (point(a.x, a.y), point(b.x, b.y), a) }
        }
        return nil
    }

    /// Up to four of the viewport's own texts (never the list row the drag starts on), spread through it, and two of
    /// the window's (a page that pans as a whole moves its chrome too), each one only the screen has.
    func dragAnchors(_ node: ViewportNode, avoiding start: CGPoint, screen: ViewportScreen) -> [ViewportAnchor] {
        func pick(_ from: [ViewportAnchor], _ n: Int) -> [ViewportAnchor] {
            let usable = from.filter { a in
                screen.counts[a.query] == 1 && screen.window.intersects(a.frame) && !(a.cell?.contains(start) ?? false)
            }
            guard usable.count > n else { return usable }
            return (0..<n).map { usable[$0 * (usable.count - 1) / max(n - 1, 1)] }
        }
        var anchors = pick(node.anchors, 4)
        if node.depth > 0, let window = screen.nodes.first { anchors += pick(window.anchors, 2) }
        return anchors
    }

    func anchorFrame(_ a: ViewportAnchor) -> CGRect? {
        let predicate = a.byIdentifier ? NSPredicate(format: "identifier == %@", a.query) : NSPredicate(format: "label == %@", a.query)
        return (try? app.descendants(matching: a.type).matching(predicate).firstMatch.snapshot())?.frame
    }

    /// Drags from `from` to `to`, slowly with a hold, reading the anchors every tenth of a second while the finger is
    /// down (XCUITest's drag keeps the main run loop turning) and once more after it lifts.
    func drag(_ viewport: String, axis: FeelAxis, from: XCUICoordinate, to: XCUICoordinate, anchors: [ViewportAnchor]) -> FeelDrag {
        var before: [String: CGRect] = [:]
        for a in anchors { before[a.key] = anchorFrame(a) }
        let seen = FeelSamples()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [self] _ in
            MainActor.assumeIsolated {
                guard !seen.busy else { return }
                seen.busy = true
                var sample: [String: CGRect] = [:]
                for a in anchors where before[a.key] != nil { sample[a.key] = anchorFrame(a) }
                seen.during.append(sample)
                seen.busy = false
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        from.press(forDuration: 0.2, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.6)
        timer.invalidate()
        pause(0.8)
        var after: [String: CGRect] = [:]
        for a in anchors where before[a.key] != nil { after[a.key] = anchorFrame(a) }
        return FeelDrag(viewport: viewport, axis: axis, before: before, during: seen.during, after: after)
    }

    // MARK: Chrome floats over content

    /// Chrome floats over content (the content is the canvas): in each pose, each piece of `chrome` (identifiers or
    /// labels of glass controls, pills, bars that float over the page) sits over the content's viewport rather than
    /// beside it, so the content runs underneath instead of giving up room; and once the content is brought to its end,
    /// its last line lies wholly inside the viewport and under none of the chrome.
    ///
    /// `over` names the viewport (a reader's page, a scroll view); by default it is the largest scroll view or web
    /// view on screen. The content is every text and image inside it that is not chrome, or the elements named in
    /// `content`. Content with no identifier is named by a fingerprint of its words, never the words. `toEnd` brings
    /// the content to its end (turning to a book's last page, say); by default the check swipes up the viewport until
    /// its last line holds still, up to 15 times. Name only chrome that shows at rest: chrome not on screen could not
    /// be checked.
    public func chromeFloats(_ chrome: [String], over viewport: String? = nil, content: [String] = [],
                             toEnd: ((OuroFeel) -> Void)? = nil, poses: [FeelPose] = [.current]) -> FeelResult {
        var results: [FeelResult] = []
        for pose in poses {
            pose.apply(self)
            results.append(chromeFloatsNow(chrome, over: viewport, content: content, toEnd: toEnd, pose: pose.name))
        }
        #if os(iOS)
        if poses.contains(where: { $0.orientation != nil }) { FeelPose.portrait.apply(self) }
        #endif
        var result = FeelFloat.combine(results)
        result.environment = environment
        return result
    }

    func chromeFloatsNow(_ chrome: [String], over key: String?, content: [String], toEnd: ((OuroFeel) -> Void)?,
                         pose: String) -> FeelResult {
        let rest = floatRead(chrome, over: key, content: content)
        var reachedEnd = true
        if let toEnd {
            toEnd(self)
            pause(1)
        } else if let v = rest.viewport {
            reachedEnd = false
            let visible = v.frame.intersection(rest.window)
            var last = endMark(rest.content), steady = 0
            for _ in 0..<15 where !visible.isNull {
                point(visible.midX, visible.minY + visible.height * 0.75)
                    .press(forDuration: 0.05, thenDragTo: point(visible.midX, visible.minY + visible.height * 0.15),
                           withVelocity: .fast, thenHoldForDuration: 0)
                pause(0.6)
                let now = endMark(floatRead(chrome, over: key, content: content).content)
                steady = now == last ? steady + 1 : 0
                last = now
                if steady >= 2 { reachedEnd = true; break }
            }
            pause(0.6)
        }
        let end = floatRead(chrome, over: key, content: content)
        return FeelFloat.check(viewport: rest.viewport, chrome: rest.chrome, end: end.content, endViewport: end.viewport?.frame,
                               endChrome: end.chrome, window: rest.window, reachedEnd: reachedEnd, expected: chrome, pose: pose)
    }

    /// The content's last line, as a mark that holds still once the content is at its end.
    func endMark(_ content: [FeelElement]) -> String {
        guard let last = content.max(by: { $0.frame.maxY < $1.frame.maxY }) else { return "" }
        return "\(last.key) \(Int(last.frame.maxY.rounded()))"
    }

    func floatRead(_ chrome: [String], over key: String?, content keys: [String])
        -> (window: CGRect, viewport: FeelElement?, chrome: [FeelElement], content: [FeelElement]) {
        guard let root = try? app.snapshot() else { return (.zero, nil, [], []) }
        let window = Self.mainWindow(root)
        let chromeKeys = Set(chrome), contentKeys = Set(keys)
        var bars: [String: FeelElement] = [:]
        var best: (any XCUIElementSnapshot)?
        func find(_ node: any XCUIElementSnapshot) {
            let type = node.elementType, identifier = node.identifier, label = node.label, frame = node.frame
            let name = chromeKeys.contains(identifier) ? identifier : chromeKeys.contains(label) ? label : nil
            if let name, bars[name] == nil { bars[name] = FeelElement(key: name, type: Self.kind(type), frame: frame) }
            if let key {
                if best == nil, identifier == key || label == key { best = node }
            } else if Self.scrollTypes.contains(type) {
                let area = frame.intersection(window)
                let bestArea = best.map { $0.frame.intersection(window) }
                if !area.isNull, bestArea.map({ $0.isNull || area.width * area.height > $0.width * $0.height }) ?? true { best = node }
            }
            for child in node.children { find(child) }
        }
        find(root)
        guard let best else { return (window, nil, Array(bars.values), []) }
        var items: [FeelElement] = []
        func collect(_ node: any XCUIElementSnapshot) {
            let type = node.elementType, identifier = node.identifier, label = node.label, frame = node.frame
            if chromeKeys.contains(identifier) || chromeKeys.contains(label) { return }
            let wanted = contentKeys.isEmpty ? (type == .staticText || type == .image) && !label.isEmpty
                : contentKeys.contains(identifier) || contentKeys.contains(label)
            if wanted, frame.width > 0, frame.height > 0 {
                items.append(FeelElement(key: identifier.isEmpty ? "words \(FeelPlace.fingerprint(label))" : identifier,
                                         type: Self.kind(type), frame: frame))
            }
            for child in node.children { collect(child) }
        }
        for child in best.children { collect(child) }
        let viewport = FeelElement(key: Self.key(best).isEmpty ? Self.name(best.elementType) : Self.key(best),
                                   type: Self.kind(best.elementType), frame: best.frame)
        return (window, viewport, chrome.compactMap { bars[$0] }, items)
    }

    // MARK: One action finishes the intent

    /// One action finishes the intent (your intent is the unit): a tap on `control` that starts slow work (a
    /// download, a load, a sign-in) ends with `done` on screen (an identifier or label), with no second tap.
    public func finishesIntent(_ control: XCUIElement, opens done: String, within: TimeInterval = 30,
                               quiet: TimeInterval = 3) -> FeelResult {
        let predicate = NSPredicate(format: "identifier == %@ OR label == %@", done, done)
        let target = app.descendants(matching: .any).matching(predicate).firstMatch
        return finishesIntent(control, named: "opening \"\(done)\"", within: within, quiet: quiet) { target.exists }
    }

    /// One action finishes the intent: one tap on `control`, then a wait of up to `within` seconds for `done`. The
    /// screen counts as busy while anything on it changes (words, values such as a progress figure, frames) or a
    /// spinner or progress bar shows; once it has held still for `quiet` seconds with the intent not done and the same
    /// control is back, the check taps it once more. If that second tap finishes the intent, the first tap's work
    /// was dropped when it ended, which fails. Launch into a state where the work is needed (the book not downloaded)
    /// and is safe to repeat.
    public func finishesIntent(_ control: XCUIElement, named intent: String? = nil, within: TimeInterval = 30,
                               quiet: TimeInterval = 3, done: () -> Bool) -> FeelResult {
        guard control.waitForExistence(timeout: timeout), let shot = try? control.snapshot() else {
            var r = FeelIntent.judge(FeelIntentTrail(intent: intent ?? "the tap's intent", control: "the control", within: within))
            r.findings = [.couldNotCheck("the control to tap was not on screen")]
            r.summary = "could not check: the control to tap was not on screen"
            return r
        }
        let key = Self.key(shot)
        var trail = FeelIntentTrail(intent: intent ?? "what a tap on \"\(key)\" starts", control: key, within: within)
        control.tap()
        let first = Date()
        var mark = screenMark(), changed = Date()
        while Date().timeIntervalSince(first) < within {
            if done() { trail.doneAfterFirst = Date().timeIntervalSince(first); break }
            pause(0.25)
            let now = screenMark()
            if now.busy || now.mark != mark.mark { changed = Date() }
            mark = now
            if Date().timeIntervalSince(changed) >= quiet {
                trail.settledAfter = changed.timeIntervalSince(first)
                break
            }
        }
        if trail.doneAfterFirst == nil, trail.settledAfter != nil {
            trail.controlBack = control.exists && control.isEnabled
            if trail.controlBack {
                trail.tappedTwice = true
                control.tap()
                let second = Date()
                while Date().timeIntervalSince(second) < within {
                    if done() { trail.doneAfterSecond = Date().timeIntervalSince(second); break }
                    pause(0.25)
                }
            }
        }
        var result = FeelIntent.judge(trail)
        result.environment = environment
        return result
    }

    /// A fingerprint of what is on screen (each element's type, name, value and frame), and whether a spinner or
    /// progress bar shows.
    func screenMark() -> (mark: Int, busy: Bool) {
        guard let root = try? app.snapshot() else { return (0, false) }
        var hasher = Hasher(), busy = false
        func walk(_ node: any XCUIElementSnapshot) {
            let type = node.elementType
            if type == .activityIndicator || type == .progressIndicator { busy = true }
            hasher.combine(type.rawValue)
            hasher.combine(node.identifier)
            hasher.combine(node.label)
            hasher.combine(node.value.map { "\($0)" } ?? "")
            let f = node.frame
            hasher.combine(Int(f.minX.rounded()))
            hasher.combine(Int(f.minY.rounded()))
            hasher.combine(Int(f.width.rounded()))
            hasher.combine(Int(f.height.rounded()))
            for child in node.children { walk(child) }
        }
        walk(root)
        return (hasher.finalize(), busy)
    }
}
#endif
