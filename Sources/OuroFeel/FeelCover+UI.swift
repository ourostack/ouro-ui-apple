#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
public import CoreGraphics
public import OuroFeelCore
public import XCTest

extension OuroFeel {
    // MARK: Covered content

    /// Covered content: in each pose, none of the `chrome` (identifiers or labels of headers, bars and buttons that
    /// float over the page) covers any of the content, and none sits under the status bar. The content is every
    /// element named in `content`, or, when it is empty, every static text and image on screen that is not chrome or
    /// inside it; with `within`, only those inside the element of that identifier or label (a reader's page, so a test
    /// probe or a toast elsewhere is not counted). Content with no identifier is named in the report by a fingerprint
    /// of its words, never the words (a book's text stays out of reports). Content outside the window is left to
    /// ``insideWindow(poses:also:)``. A chrome element that is not on screen could not be checked, so name only chrome
    /// that shows in every pose you pass. Before each pose it waits, up to ``readyTimeout`` for the whole call, for
    /// content in the window (and for ``ready`` when set); content that never comes fails as "never became ready", and
    /// is never scored. Chrome inside named content (a page holding its running head) is still chrome.
    ///
    /// The default content suits a reader: every text counts, so on a list whose rows scroll under a translucent bar
    /// you name as chrome, a row passing under it would count as covered. There, name the content or use `within`.
    ///
    /// The status bar is read from the system (on iOS) only when it lies along the top of the app's window, as it does
    /// whenever it shows; when it is hidden or turned with the device, the report notes it was not checked.
    public func uncovered(by chrome: [String], content: [String] = [], within: String? = nil,
                          poses: [FeelPose] = [.current]) -> FeelResult {
        var results: [FeelResult] = []
        let deadline = readyDeadline()
        for pose in poses {
            pose.apply(self)
            // Measure until the measure itself found content on screen: the wait reads exactly what is scored.
            var measured: FeelResult?
            let never = awaitReady(check: FeelGenre.insideWindow.rawValue, what: within ?? content.first, pose: pose.name,
                                   until: deadline) {
                let read = uncoveredMeasure(by: chrome, content: content, within: within, pose: pose.name)
                measured = read.result
                return FeelReadyLook(content: read.content, signal: readySignal, why: read.why)
            }
            results.append(never ?? measured!)
        }
        #if os(iOS)
        if poses.contains(where: { $0.orientation != nil }) { FeelPose.portrait.apply(self) }
        #endif
        return results.count == 1 ? results[0] : FeelCover.combine(results)
    }

    func uncoveredNow(by chrome: [String], content: [String], within: String?, pose: String) -> FeelResult {
        uncoveredMeasure(by: chrome, content: content, within: within, pose: pose).result
    }

    /// The covered-content measure, and how much of the content it scores (visible in the window, not chrome) it found.
    func uncoveredMeasure(by chrome: [String], content: [String], within: String?, pose: String)
        -> (result: FeelResult, content: Int, why: String?) {
        guard let root = try? app.snapshot() else {
            return (FeelCover.check(content: [], chrome: [], window: .zero, pose: pose), 0, "the accessibility snapshot failed")
        }
        let window = Self.mainWindow(root)
        let chromeKeys = Set(chrome), contentKeys = Set(content)
        var bars: [FeelElement] = [], items: [FeelElement] = []
        var foundWithin = within == nil
        func walk(_ node: any XCUIElementSnapshot, inside: Bool) {
            let type = node.elementType, identifier = node.identifier, label = node.label
            let entering = !inside && within.map { identifier == $0 || label == $0 } == true
            if entering { foundWithin = true }
            let inside = inside || entering
            if chromeKeys.contains(identifier) || chromeKeys.contains(label) {
                // Chrome and everything inside it (a header's own words) is chrome.
                bars.append(FeelElement(key: chromeKeys.contains(identifier) ? identifier : label, type: Self.kind(type),
                                        frame: node.frame))
                return
            }
            if inside, contentKeys.isEmpty ? (type == .staticText || type == .image) && !label.isEmpty
                : (contentKeys.contains(identifier) || contentKeys.contains(label)) {
                let key = identifier.isEmpty ? "words \(FeelPlace.fingerprint(label))" : identifier
                items.append(FeelElement(key: key, type: Self.kind(type), frame: node.frame))
                // Keep walking: named content can hold chrome (a page with its running head inside).
            }
            for child in node.children { walk(child, inside: inside) }
        }
        walk(root, inside: within == nil)
        var keepClear: [FeelElement] = []
        var note: FeelFinding?
        #if os(iOS)
        if let bar = statusBar(window: window) {
            keepClear.append(FeelElement(key: "status bar", type: "status bar", frame: bar))
        } else {
            note = .note("the status bar was hidden or not along the window's top in \(pose), so chrome under it was not checked")
        }
        #endif
        var result = FeelCover.check(content: items, chrome: bars, keepClear: keepClear, window: window, pose: pose,
                                     expected: chrome)
        if let note { result.findings.append(note) }
        var missing = Set(content).subtracting(items.map(\.key)).sorted()
        if let within, !foundWithin { missing.append(within) }
        if !missing.isEmpty {
            result = FeelResult.judged(check: result.check, passing: result.summary, failing: { _ in result.summary },
                                       measures: result.measures,
                                       findings: result.findings + missing.map { .couldNotCheck("\"\($0)\" was not on screen in \(pose)") })
        }
        let shown = items.filter { FeelCover.visible($0.frame, in: window) }.count
        let why: String? = shown > 0 ? nil
            : within.map { foundWithin ? "\"\($0)\" was on screen but held no text or image in the window" : "\"\($0)\" was not on screen" }
        return (result, shown, why)
    }

    #if os(iOS)
    /// The status bar's frame in the app's coordinates, when it shows along the top of the window.
    func statusBar(window: CGRect) -> CGRect? {
        let candidates = [app.statusBars.firstMatch, XCUIApplication(bundleIdentifier: "com.apple.springboard").statusBars.firstMatch]
        for bar in candidates where bar.exists {
            let f = bar.frame
            // A status bar reported in another orientation's coordinates (SpringBoard's, with the app turned) is not
            // along this window's top, and judging against it would be wrong.
            if f.height > 0, f.height < window.height * 0.2, abs(f.minY - window.minY) <= 1, abs(f.width - window.width) <= 1 {
                return f
            }
        }
        return nil
    }
    #endif

    static func kind(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .staticText: "text"
        case .image: "image"
        case .other: "element"
        default: name(type)
        }
    }
}
#endif
