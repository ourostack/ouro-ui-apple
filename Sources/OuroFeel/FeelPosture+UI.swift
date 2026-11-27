#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
public import CoreGraphics
import Foundation
public import OuroFeelCore
public import XCTest

extension OuroFeel {
    // MARK: Reading what you read

    /// The window, what you read and the elements named in `find`, from one accessibility snapshot. The content is every
    /// static text and image with words (or the elements named in `content`), inside the element named `within` when
    /// given, never inside anything named in `excluding` (chrome, a fold marker, a notice), and by default never inside a
    /// navigation bar, toolbar, tab bar or status bar (their titles are chrome, and sit across a fold). Content with no
    /// identifier is keyed by a fingerprint of its words, never the words.
    func reading(content: [String] = [], within: String? = nil, excluding: [String] = [], find: [String] = [])
        -> (window: CGRect, content: [FeelElement], found: [String: FeelElement], within: CGRect?) {
        guard let root = try? app.snapshot() else { return (.zero, [], [:], nil) }
        let window = Self.mainWindow(root)
        let contentKeys = Set(content), skip = Set(excluding), wanted = Set(find)
        var items: [FeelElement] = [], found: [String: FeelElement] = [:]
        var withinFrame: CGRect?
        func walk(_ node: any XCUIElementSnapshot, inside: Bool, inBar: Bool) {
            // Read once, up front: a closure that captures the snapshot fails a Release build.
            let type = node.elementType, identifier = node.identifier, label = node.label, frame = node.frame
            let inBar = inBar || Self.bars.contains(type)
            let name = wanted.contains(identifier) ? identifier : wanted.contains(label) ? label : nil
            if let name, found[name] == nil { found[name] = FeelElement(key: name, type: Self.kind(type), frame: frame) }
            if skip.contains(identifier) || skip.contains(label) { return }
            var entering = false
            if !inside, let within, identifier == within || label == within {
                entering = true
                withinFrame = frame
            }
            let inside = inside || entering
            let isContent = contentKeys.isEmpty ? (type == .staticText || type == .image) && !label.isEmpty && !inBar
                : contentKeys.contains(identifier) || contentKeys.contains(label)
            if inside, isContent, frame.width > 0, frame.height > 0 {
                items.append(FeelElement(key: identifier.isEmpty ? "words \(FeelPlace.fingerprint(label))" : identifier,
                                         type: Self.kind(type), frame: frame))
            }
            for child in node.children { walk(child, inside: inside, inBar: inBar) }
        }
        walk(root, inside: within == nil, inBar: false)
        return (window, items, found, withinFrame)
    }

    /// Bars whose words are chrome, not what you read.
    static let bars: Set<XCUIElement.ElementType> = [.navigationBar, .toolbar, .tabBar, .statusBar]

    /// `result` as could not check for each element named in `content` or `within` that was not on screen, as
    /// ``uncovered(by:content:within:poses:)`` reports them.
    func missing(_ result: FeelResult, content: [String], within: String?, read: (content: [FeelElement], within: CGRect?),
                 in place: String) -> FeelResult {
        var missing = Set(content).subtracting(read.content.map(\.key)).sorted()
        if let within, read.within == nil { missing.append(within) }
        guard !missing.isEmpty else { return result }
        var marked = FeelResult.judged(check: result.check, passing: result.summary, failing: { _ in result.summary },
                                       measures: result.measures,
                                       findings: result.findings + missing.map { .couldNotCheck("\"\($0)\" was not on screen in \(place)") })
        marked.environment = result.environment
        return marked
    }

    // MARK: Content clears the fold

    /// Content clears the fold (posture changes re-lay out in place): no text or image you read runs across the fold,
    /// and with `spread`, a fold that runs top to bottom (a device held open like a book) has content on each side.
    ///
    /// The fold is the frame of the element whose identifier or label is `fold`, which the app puts over its hinge (a
    /// clear, accessibility-only view at OuroHX's `OuroFoldRegion.frame`), so the check runs wherever the app knows its
    /// fold: an iPhone Duo driven through Device Hub, or a fixture or preview that declares one. With no such element on
    /// screen it could not check. Run it once in each fold posture, naming it in `posture`. `content` and `within` pick
    /// what you read as ``uncovered(by:content:within:poses:)`` does.
    public func clearsTheFold(_ fold: String = "ouro.fold", content: [String] = [], within: String? = nil,
                              spread: Bool = false, posture: String = "this posture") -> FeelResult {
        let read = reading(content: content, within: within, excluding: [fold], find: [fold])
        var result = FeelFold.check(content: read.content, fold: read.found[fold]?.frame, window: read.window, spread: spread,
                                    posture: posture)
        result.environment = environment
        return missing(result, content: content, within: within, read: (read.content, read.within), in: posture)
    }

    /// ``clearsTheFold(_:content:within:spread:posture:)`` with the fold's frame given, in the window's coordinates (a
    /// fold the test knows, such as OuroHXTesting's `OuroDuoHinge` reading).
    public func clearsTheFold(at fold: CGRect, content: [String] = [], within: String? = nil, spread: Bool = false,
                              posture: String = "this posture") -> FeelResult {
        let read = reading(content: content, within: within)
        var result = FeelFold.check(content: read.content, fold: fold, window: read.window, spread: spread, posture: posture)
        result.environment = environment
        return missing(result, content: content, within: within, read: (read.content, read.within), in: posture)
    }

    // MARK: A turn lays out like a fresh launch

    /// A turn lays out like a fresh launch (posture changes re-lay out in place): `within` seconds after each pose in
    /// `after`, the identified elements on screen are where a fresh launch in that pose puts them, with none left over
    /// and none missing.
    ///
    /// For each pose it turns the device, waits `within` seconds (3 by default) and reads every element with an
    /// identifier (or those named in `keys`), then terminates the app and launches it again in the same pose with the
    /// same arguments, runs `reopen` to bring it back to the same screen if the launch does not, waits as long again, and
    /// reads the same. Elements in a scroll view move with its scroll, so run it on a screen as it opens, or name the page
    /// and its chrome in `keys`. Anything named in `ignoring` is left out: a pill or toast shown only on launch (a
    /// "Back to where you were"). A turn that leaves the window's shape as it was (a portrait-only app, a platform with
    /// nothing to turn) could not be checked. The app ends relaunched in portrait.
    public func laysOutFresh(after poses: [FeelPose] = FeelPose.turnAndBack, within: TimeInterval = 3,
                             keys: [String] = [], ignoring: [String] = [], reopen: ((OuroFeel) -> Void)? = nil) -> FeelResult {
        var results: [FeelResult] = []
        for pose in poses {
            results.append(laysOutFreshNow(named: "turning to \(pose.name)", within: within, keys: keys, ignoring: ignoring,
                                           reopen: reopen, mustTurn: true) { pose.apply($0) })
        }
        #if os(iOS)
        if poses.contains(where: { $0.orientation != nil }) { FeelPose.portrait.apply(self) }
        #endif
        var result = FeelRelayout.combine(results)
        result.environment = environment
        return result
    }

    /// ``laysOutFresh(after:within:keys:ignoring:reopen:)`` for a change the test makes itself (folding or unfolding an iPhone
    /// Duo through OuroHXTesting's `OuroDuoHinge`), named `change` in the report. The fresh launch is in whatever posture
    /// the change left the device in.
    public func laysOutFresh(named change: String, within: TimeInterval = 3, keys: [String] = [], ignoring: [String] = [],
                             reopen: ((OuroFeel) -> Void)? = nil, change act: (OuroFeel) -> Void) -> FeelResult {
        var result = laysOutFreshNow(named: change, within: within, keys: keys, ignoring: ignoring, reopen: reopen,
                                     mustTurn: false, change: act)
        result.environment = environment
        return result
    }

    func laysOutFreshNow(named change: String, within: TimeInterval, keys: [String], ignoring: [String],
                         reopen: ((OuroFeel) -> Void)?, mustTurn: Bool, change act: (OuroFeel) -> Void) -> FeelResult {
        let before = windowFrame
        let started = Date()
        act(self)
        pause(max(0, within - Date().timeIntervalSince(started)))
        let waited = Date().timeIntervalSince(started)
        let turned = layout(keys: keys, ignoring: ignoring)
        pause(0.5)
        let settled = layout(keys: keys, ignoring: ignoring).elements == turned.elements
        app.terminate()
        app.launch()
        reopen?(self)
        pause(within)
        let fresh = layout(keys: keys, ignoring: ignoring)
        return FeelRelayout.compare(turned: turned.elements, fresh: fresh.elements, turnedWindow: turned.window,
                                    freshWindow: fresh.window, change: change, waited: waited, settled: settled,
                                    beforeWindow: mustTurn ? before : nil)
    }

    /// Every element with an identifier (or named in `keys`) inside the window, by its frame, but those in `ignoring`.
    func layout(keys: [String], ignoring: [String] = []) -> (window: CGRect, elements: [FeelElement]) {
        guard let root = try? app.snapshot() else { return (.zero, []) }
        let window = Self.mainWindow(root)
        let wanted = Set(keys), skip = Set(ignoring)
        var found: [FeelElement] = []
        func walk(_ node: any XCUIElementSnapshot) {
            let type = node.elementType, identifier = node.identifier, label = node.label, frame = node.frame
            if skip.contains(identifier) || skip.contains(label) { return }
            let named = wanted.isEmpty ? !identifier.isEmpty : wanted.contains(identifier) || wanted.contains(label)
            if named, type != .application, type != .window, FeelCover.visibleForUI(frame, in: window) {
                let key = wanted.contains(label) && !wanted.contains(identifier) ? label : Self.key(node)
                found.append(FeelElement(key: key, type: Self.kind(type), frame: frame))
            }
            for child in node.children { walk(child) }
        }
        walk(root)
        return (window, found.sorted { ($0.key, $0.frame.minY, $0.frame.minX) < ($1.key, $1.frame.minY, $1.frame.minX) })
    }

    // MARK: Your place survives a turn

    /// Your place survives a turn (your place is yours): through each turn in `turns`, the first words
    /// on screen after it are within a line of the first words before it.
    ///
    /// Before every turn but the first it runs `between`, which by default drags the content up by half the window,
    /// slowly, so the place moves on as a reader's would (Gatefold lost its place only on a turn after a scroll); a
    /// scroll that moved nothing on screen leaves that turn untried, and says so. The words are read by `read` (the app's
    /// own report of its visible text, such as `reader.visibleText`), or by default from every text any of which shows
    /// in the window, or inside `within`, in reading order (``FeelTurnPlace/reading(_:in:)``), so the reading starts at
    /// the same top edge in each orientation, status bar or none; bars' words are left out. A line is `line` words, or by
    /// default as many words as the first text read holds, at most 15. A turn that left the window's shape as it was
    /// (a portrait-only app, a platform with nothing to turn) could not be checked. Only fingerprints of the words go in
    /// the report. The app ends in portrait.
    public func placeSurvivesTurns(_ turns: [FeelPose] = FeelPose.turns,
                                   within: String? = nil, line: Int? = nil, between: ((OuroFeel) -> Void)? = nil,
                                   read: (() -> String)? = nil) -> FeelResult {
        var reads: [FeelTurnRead] = []
        func words() -> (words: [String], line: Int) {
            if let read {
                let text = steady(read)
                let first = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? text
                return (FeelTurnPlace.words(text), FeelTurnPlace.words(first).count)
            }
            let text = steady { self.visibleLines(within: within).joined(separator: "\n") }
            let first = text.split(separator: "\n").first.map(String.init) ?? ""
            return (FeelTurnPlace.words(text), FeelTurnPlace.words(first).count)
        }
        for (i, pose) in turns.enumerated() {
            if i > 0 {
                if let between { between(self) } else { scrollOn(within: within) }
            }
            let before = words()
            let shape = windowFrame
            pose.apply(self)
            let turned = windowFrame
            let after = words()
            let measured = min(15, max(before.line, after.line))
            let moved = i == 0 || reads.last.map { $0.after != before.words } ?? true
            let changed = abs(shape.width - turned.width) > FeelCover.tolerance || abs(shape.height - turned.height) > FeelCover.tolerance
            reads.append(FeelTurnRead(turn: pose.name, before: before.words, after: after.words, line: line ?? max(1, measured),
                                      scrolledFirst: i > 0, scrollMoved: moved, shapeChanged: changed))
        }
        #if os(iOS)
        if turns.contains(where: { $0.orientation != nil }) { FeelPose.portrait.apply(self) }
        #endif
        var result = FeelTurnPlace.judge(reads)
        result.environment = environment
        return result
    }

    /// The labels of every text any of which shows in the window, or inside `within`, in reading order, from the same
    /// top edge in every orientation (``FeelTurnPlace/reading(_:in:)``). Bars' words are left out.
    func visibleLines(within: String?) -> [String] {
        guard let root = try? app.snapshot() else { return [] }
        var clear = Self.mainWindow(root)
        var lines: [(frame: CGRect, text: String)] = []
        func walk(_ node: any XCUIElementSnapshot, inside: Bool) {
            let type = node.elementType, identifier = node.identifier, label = node.label, frame = node.frame
            if Self.bars.contains(type) { return }
            var inside = inside
            if !inside, let within, identifier == within || label == within {
                inside = true
                clear = clear.intersection(frame)
            }
            if inside, type == .staticText, !label.isEmpty, frame.width > 0 { lines.append((frame, label)) }
            for child in node.children { walk(child, inside: inside) }
        }
        walk(root, inside: within == nil)
        return clear.isNull ? [] : FeelTurnPlace.reading(lines, in: clear)
    }

    /// Drags the content up by half the window, slowly and with a hold, so it moves on without a fling.
    func scrollOn(within: String?) {
        var area = windowFrame
        if let within, let found = reading(within: within).within { area = area.intersection(found) }
        guard !area.isNull, area.height > 0 else { return }
        point(area.midX, area.minY + area.height * 0.75)
            .press(forDuration: 0.1, thenDragTo: point(area.midX, area.minY + area.height * 0.25), withVelocity: .slow,
                   thenHoldForDuration: 0.3)
        pause(1)
    }
}

extension FeelCover {
    /// ``visible(_:in:)`` for the UI module.
    static func visibleForUI(_ frame: CGRect, in window: CGRect) -> Bool {
        let shown = frame.intersection(window)
        return !shown.isNull && shown.width > tolerance && shown.height > tolerance
    }
}
#endif
