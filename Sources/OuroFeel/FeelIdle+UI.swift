#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
public import CoreGraphics
public import OuroFeelCore
public import XCTest

extension OuroFeel {
    // MARK: Still while idle

    /// Still while idle (part of the flicker genre): in each pose, with no input for `seconds`, no enabled control and
    /// nothing named in `watch` (identifiers or labels of chrome that is no control: a running head, a page number)
    /// appears, goes or moves, and the status bar neither shows nor hides. Looks at the screen as often as accessibility
    /// snapshots allow (at most every `every` seconds). Call it once the screen has landed. A screen that flips its
    /// chrome several times a second, as Gatefold's reader did on the open iPhone Duo, fails on the first few looks.
    public func stillWhileIdle(for seconds: TimeInterval = 3, every: TimeInterval = 0.1, watch: [String] = [],
                               poses: [FeelPose] = [.current]) -> FeelResult {
        var results: [FeelResult] = []
        let deadline = readyDeadline()
        for pose in poses {
            pose.apply(self)
            // Wait on the check's own look: something it watches on screen, and the app's signal if given. The look
            // that finds it ready is the watch's first, so a screen already there costs no extra look.
            var first: (sample: FeelIdleSample, at: Double)?
            if let never = awaitReady(check: FeelGenre.flicker.rawValue, what: nil, pose: pose.name, until: deadline, look: {
                let at = Date().timeIntervalSinceReferenceDate
                let sample = idleSample(at: 0, watch: Set(watch))
                first = (sample, at)
                return FeelReadyLook(content: sample.elements.count, signal: readySignal)
            }) {
                results.append(never)
                continue
            }
            let samples = FeelIdle.watch(for: seconds, every: every, now: { Date().timeIntervalSinceReferenceDate },
                                         first: first, look: { self.idleSample(at: $0, watch: Set(watch)) },
                                         pause: { self.pause($0) })
            results.append(FeelIdle.check(samples, pose: pose.name))
        }
        #if os(iOS)
        if poses.contains(where: { $0.orientation != nil }) { FeelPose.portrait.apply(self) }
        #endif
        guard results.count > 1 else { return results.first ?? FeelIdle.check([], pose: "no pose") }
        let failed = results.filter { !$0.passed }.count
        let changes = results.reduce(0) { $0 + ($1.measures["changes"] ?? 0) }
        return FeelResult.judged(check: FeelGenre.flicker.rawValue,
                                 passing: "still while idle in \(results.count) poses",
                                 failing: { _ in "not still while idle in \(failed) of \(results.count) poses" },
                                 measures: ["poses": Double(results.count), "changes": changes],
                                 findings: results.flatMap(\.findings))
    }

    func idleSample(at: Double, watch: Set<String>) -> FeelIdleSample {
        var elements: [String: CGRect] = [:]
        var window = CGRect.zero
        if let root = try? app.snapshot() {
            window = Self.mainWindow(root)
            func walk(_ node: any XCUIElementSnapshot) {
                // Read once, up front: `&&` and `||` take their right side as a closure, and a closure that captures
                // the snapshot fails a Release build ("sending 'node' risks causing data races").
                let type = node.elementType, identifier = node.identifier, label = node.label, enabled = node.isEnabled
                // The status bar is the system's, read on its own below; what is in it is not the app's to keep still.
                if type == .statusBar { return }
                let named = watch.contains(identifier) || watch.contains(label)
                if named || (Self.controlTypes.contains(type) && enabled) {
                    var key = named && !watch.contains(identifier) ? label : Self.key(node)
                    if key.isEmpty { key = FeelIdle.unnamed(Self.name(type)) }
                    // Two controls with one name (two "Close" buttons) are told apart by order.
                    if elements[key] != nil {
                        var n = 2
                        while elements["\(key) #\(n)"] != nil { n += 1 }
                        key = "\(key) #\(n)"
                    }
                    if node.frame.width > 0 && node.frame.height > 0 { elements[key] = node.frame }
                }
                for child in node.children { walk(child) }
            }
            walk(root)
        }
        return FeelIdleSample(at: at, elements: elements, statusBar: statusBarShows()).shown(in: window)
    }

    /// Whether the status bar shows now; nil where there is none to read.
    func statusBarShows() -> Bool? {
        #if os(iOS)
        for bar in [app.statusBars.firstMatch, XCUIApplication(bundleIdentifier: "com.apple.springboard").statusBars.firstMatch] {
            if bar.exists {
                let f = bar.frame
                return f.width > 0 && f.height > 0
            }
        }
        return false
        #else
        return nil
        #endif
    }
}
#endif
