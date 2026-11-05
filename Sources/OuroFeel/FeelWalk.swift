#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
public import OuroFeelCore
public import XCTest

/// A place a walk starts from: a name, and how to get there from a fresh launch.
@MainActor
public struct FeelEntry {
    public let name: String
    let open: @MainActor (XCUIApplication) -> Void

    public init(_ name: String, open: @escaping @MainActor (XCUIApplication) -> Void) {
        self.name = name
        self.open = open
    }

    /// The screen the app launches to.
    public static let launch = FeelEntry("launch") { _ in }

    /// Taps the tab (or any button) labelled or identified `key` first.
    public static func tab(_ key: String) -> FeelEntry {
        FeelEntry(key) { app in
            let button = app.buttons[key].firstMatch
            if button.waitForExistence(timeout: 5) { button.tap() }
        }
    }
}

/// Which controls a walk may tap to find new screens: cells and links by default, which reach pushed screens. Add
/// `.button` to reach sheets and covers too. It never taps one whose label or identifier holds a word in `avoid`
/// (identifiers split at case changes and punctuation, see ``FeelSafety``), so a walk does not delete, sign out or pay;
/// it never taps a back control, a menu button, or anything inside a tab bar, segmented control, picker or menu, which
/// switch what a screen shows rather than open a new one. Buttons that change data without such a word (Save, Add) can
/// still be tapped when `.button` is followed: launch the walk into a fixture state that is safe to change, or use `prefixes`.
public struct FeelFollow: Sendable {
    public var types: Set<XCUIElement.ElementType>
    /// Identifier prefixes to follow as well, whatever their type (for example `"recipe."`).
    public var prefixes: [String]
    public var avoid: [String]

    public init(types: Set<XCUIElement.ElementType> = [.cell, .link], prefixes: [String] = [],
                avoid: [String] = FeelFollow.dangerous) {
        self.types = types
        self.prefixes = prefixes
        self.avoid = avoid
    }

    public static let dangerous = FeelSafety.dangerous
    public static let `default` = FeelFollow()

    func allows(type: XCUIElement.ElementType, key: String, label: String) -> Bool {
        if FeelSafety.isDangerous(key, label, avoid: avoid) { return false }
        return types.contains(type) || prefixes.contains { key.hasPrefix($0) }
    }
}

/// An overlay to check: how to open it, its identifier, and an item to pick in it.
@MainActor
public struct FeelOverlay {
    public let name: String
    public let overlay: String
    public let pick: String?
    let open: @MainActor (XCUIApplication) -> Void

    /// `open` brings the overlay up (usually a tap on its button); `overlay` is the identifier (or label) of its
    /// container; `pick` is an item inside it that should dismiss it, as a compact sidebar's rows should.
    public init(_ name: String, overlay: String, pick: String? = nil, open: @escaping @MainActor (XCUIApplication) -> Void) {
        self.name = name
        self.overlay = overlay
        self.pick = pick
        self.open = open
    }

    /// Opens with a tap on the button labelled or identified `button`.
    public static func button(_ button: String, overlay: String, pick: String? = nil) -> FeelOverlay {
        FeelOverlay(button, overlay: overlay, pick: pick) { app in
            let b = app.buttons[button].firstMatch
            if b.waitForExistence(timeout: 5) { b.tap() }
        }
    }
}

extension OuroFeel {
    /// Controls that switch what a screen shows; a walk follows neither them nor anything inside them.
    static let switcherTypes: Set<XCUIElement.ElementType> = [.tabBar, .segmentedControl, .picker, .menu, .menuBar,
                                                             .menuButton, .popUpButton]
    /// A screen's identity for the walk: the navigation bars and the followable and back controls on it.
    func signature(_ follow: FeelFollow) -> String {
        guard let root = try? app.snapshot() else { return "" }
        var parts: [String] = []
        func walk(_ node: any XCUIElementSnapshot) {
            let key = Self.key(node)
            if node.elementType == .navigationBar || (node.elementType == .button && Self.isBack(node))
                || follow.allows(type: node.elementType, key: key, label: node.label) {
                parts.append("\(node.elementType.rawValue):\(key)")
            }
            node.children.forEach(walk)
        }
        walk(root)
        return parts.sorted().joined(separator: "|")
    }

    static func holdsSwitcher(_ node: any XCUIElementSnapshot) -> Bool {
        node.children.contains { switcherTypes.contains($0.elementType) || holdsSwitcher($0) }
    }

    /// The titles of the navigation bars on screen.
    func barTitles() -> [String] {
        guard let root = try? app.snapshot() else { return [] }
        var titles: [String] = []
        func walk(_ node: any XCUIElementSnapshot) {
            if node.elementType == .navigationBar { titles.append(Self.key(node)) }
            node.children.forEach(walk)
        }
        walk(root)
        return titles
    }

    static func isBack(_ node: any XCUIElementSnapshot) -> Bool {
        FeelWayBack.saysBack(node.identifier, node.label)
    }

    /// The followable controls on screen, in order, by key. Back, close, done, cancel and dismiss controls are never
    /// followed, so following buttons (`FeelFollow(types: [.button])`) does not walk back out of the screen.
    func followable(_ follow: FeelFollow) -> [String] {
        guard let root = try? app.snapshot() else { return [] }
        let window = root.children.first { $0.elementType == .window }?.frame ?? root.frame
        var keys: [String] = []
        func walk(_ node: any XCUIElementSnapshot, switcher: Bool) {
            let key = Self.key(node)
            // Never the screen's own way back (following it would walk backwards), and never a control that switches
            // what this screen shows (a tab, a segment, a menu), which is not a new screen to find a way back from.
            if !switcher, !key.isEmpty, node.isEnabled, node.frame.intersects(window), !Self.isBack(node),
               !Self.switcherTypes.contains(node.elementType), !(node.elementType == .cell && Self.holdsSwitcher(node)),
               follow.allows(type: node.elementType, key: key, label: node.label), !keys.contains(key) {
                keys.append(key)
            }
            let inside = switcher || Self.switcherTypes.contains(node.elementType)
            for child in node.children { walk(child, switcher: inside) }
        }
        walk(root, switcher: false)
        return keys
    }

    func element(_ key: String) -> XCUIElement {
        let byID = app.descendants(matching: .any).matching(identifier: key).firstMatch
        return byID.exists ? byID : app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", key)).firstMatch
    }

    /// The visible back control: a navigation bar's leading button, or any button whose label or identifier says
    /// back, close, done, cancel or dismiss as a whole word (``FeelWayBack/saysBack(_:)``), inside the window.
    func backAffordance() -> XCUIElement? {
        let window = app.windows.firstMatch.frame
        let bar = app.navigationBars.firstMatch
        if bar.exists {
            let leading = bar.buttons.allElementsBoundByIndex.filter { $0.frame.minX < window.minX + 120 && window.contains($0.frame) }
            if let first = leading.first { return first }
        }
        guard let root = try? app.snapshot() else { return nil }
        var found: String?
        func walk(_ node: any XCUIElementSnapshot) {
            if found != nil { return }
            if node.elementType == .button, node.isEnabled, window.contains(node.frame), Self.isBack(node) {
                found = Self.key(node)
                return
            }
            node.children.forEach(walk)
        }
        walk(root)
        return found.map(element)
    }

    /// From the leading edge at the navigation bar's height (or near the top), where no list row sits, so a missing
    /// pop gesture never turns into a full swipe across a row and fires its swipe action.
    func edgeSwipe() {
        let w = app.windows.firstMatch.frame
        let bar = app.navigationBars.firstMatch
        let y = bar.exists && w.contains(bar.frame) ? bar.frame.midY : w.minY + min(100, w.height * 0.12)
        point(w.minX + 1, y).press(forDuration: 0.05, thenDragTo: point(w.minX + w.width * 0.7, y), withVelocity: .default, thenHoldForDuration: 0)
    }

    func swipeDown() {
        let w = app.windows.firstMatch.frame
        let from = point(w.midX, w.minY + w.height * 0.12)
        from.press(forDuration: 0.05, thenDragTo: point(w.midX, w.maxY - 10), withVelocity: .fast, thenHoldForDuration: 0)
    }

    /// Relaunches, opens the entry and taps along `path`; true if every step was there.
    func replay(_ entry: FeelEntry, _ path: [String]) -> Bool {
        app.terminate()
        app.launch()
        entry.open(app)
        pause(1)
        for key in path {
            let e = element(key)
            guard e.waitForExistence(timeout: timeout) else { return false }
            e.tap()
            pause(0.8)
        }
        return true
    }

    // MARK: The way back

    /// Walks the app from each entry point: taps every followable control (cells and links by default; see
    /// ``FeelFollow``) up to `depth` taps deep, and on every new screen it reaches checks the way back: a visible back
    /// control that returns, and a gesture (an edge swipe, else a swipe down) that returns. With `alsoInsideWindow`
    /// it also checks every reached screen's controls lie inside the window. It relaunches between screens it cannot
    /// leave, so give it a launch state that is safe to repeat.
    public func wayBack(from entries: [FeelEntry] = [.launch], follow: FeelFollow = .default, depth: Int = 2,
                        limit: Int = 40, alsoInsideWindow: Bool = true) -> FeelResult {
        var screens: [FeelDestination] = []
        var layouts: [FeelResult] = []
        var visited = Set<String>()
        for entry in entries {
            _ = replay(entry, [])
            visit(entry, path: [], depth: depth, limit: limit, follow: follow, screens: &screens, layouts: &layouts,
                  visited: &visited, check: alsoInsideWindow)
        }
        var result = FeelWayBack.evaluate(screens)
        let outside = layouts.filter { !$0.detections.isEmpty }
        let unchecked = layouts.filter { $0.detections.isEmpty && !$0.passed }
        if !outside.isEmpty {
            result.passed = false
            result.findings += outside.flatMap(\.findings)
            result.summary += "; \(outside.count) screens have controls outside the window"
        }
        if !unchecked.isEmpty {
            result.passed = false
            result.findings += unchecked.flatMap(\.findings)
            result.summary += "; \(unchecked.count) screens could not be checked for the window"
        }
        return result
    }

    private func visit(_ entry: FeelEntry, path: [String], depth: Int, limit: Int, follow: FeelFollow,
                       screens: inout [FeelDestination], layouts: inout [FeelResult], visited: inout Set<String>, check: Bool) {
        let here = signature(follow)
        let bars = barTitles()
        visited.insert(here)
        let keys = followable(follow)
        for key in keys {
            guard screens.count < limit else { return }
            if signature(follow) != here, !replay(entry, path) { return }
            let target = element(key)
            guard target.exists else { continue }
            target.tap()
            pause(0.8)
            let there = signature(follow)
            guard there != here, !visited.contains(there) else {
                if there != here { _ = replay(entry, path) }
                continue
            }
            // A menu that opened, edit mode, a row that expanded: this screen changed in place, so there is no new
            // screen to leave. Up to eight of its other controls are enough to tell.
            let others = keys.filter { $0 != key }.prefix(8)
            let stillThere = others.filter { let e = element($0); return e.exists && e.isHittable }.count
            if !FeelWayBack.isNewScreen(barsBefore: bars, barsAfter: barTitles(), stillThere: stillThere, of: others.count) {
                _ = replay(entry, path)
                continue
            }
            let name = [entry.name] + path + [key]
            if check {
                let (window, found) = controls()
                layouts.append(FeelLayout.check(found, window: window, pose: name.joined(separator: " › ")))
            }
            if depth > 1 {
                visit(entry, path: path + [key], depth: depth - 1, limit: limit, follow: follow, screens: &screens,
                      layouts: &layouts, visited: &visited, check: check)
                if signature(follow) != there { _ = replay(entry, path + [key]) }
            }
            // The gesture first, then (back on this screen) the visible control.
            var gesture: String?
            edgeSwipe()
            if wait(2, until: { signature(follow) == here }) {
                gesture = "edge swipe"
            } else {
                swipeDown()
                if wait(2, until: { signature(follow) == here }) { gesture = "swipe down" }
            }
            if gesture != nil {
                target.tap()
                pause(0.8)
                if signature(follow) != there { _ = replay(entry, path + [key]) }
            }
            let back = backAffordance()
            var label: String?
            var returns = false
            if let back {
                label = back.label.isEmpty ? back.identifier : back.label
                back.tap()
                returns = wait(2) { signature(follow) == here }
            }
            screens.append(FeelDestination(path: name, affordance: label, affordanceReturns: returns, gesture: gesture))
            if signature(follow) != here { _ = replay(entry, path) }
        }
    }

    // MARK: Overlay dismissal

    /// Opens each overlay, taps outside it (it should go), opens it again and picks its item (it should go).
    public func overlays(_ overlays: [FeelOverlay]) -> FeelResult {
        var trials: [FeelOverlayTrial] = []
        for overlay in overlays {
            func shown() -> Bool {
                let c = element(overlay.overlay)
                return c.exists && c.frame.intersects(app.windows.firstMatch.frame) && c.frame.width > 0
            }
            overlay.open(app)
            guard wait(timeout, until: shown) else {
                trials.append(FeelOverlayTrial(name: overlay.name, appeared: false))
                continue
            }
            let frame = element(overlay.overlay).frame, w = app.windows.firstMatch.frame
            let outside = [CGPoint(x: w.maxX - 20, y: w.midY), CGPoint(x: w.minX + 20, y: w.midY),
                           CGPoint(x: w.midX, y: w.maxY - 60), CGPoint(x: w.midX, y: w.minY + 80)]
                .first { !frame.insetBy(dx: -8, dy: -8).contains($0) }
            var outsideDismisses: Bool?
            if let p = outside {
                point(p.x, p.y).tap()
                outsideDismisses = wait(2) { !shown() }
            }
            var pickDismisses: Bool?
            if let pick = overlay.pick {
                if !(shown() || { overlay.open(app); return wait(timeout, until: shown) }()) {
                    pickDismisses = false  // it would not open again, so the pick was never tried
                } else {
                    let item = element(pick)
                    if item.waitForExistence(timeout: timeout) {
                        item.tap()
                        pickDismisses = wait(2) { !shown() }
                    } else {
                        pickDismisses = false
                    }
                }
            }
            trials.append(FeelOverlayTrial(name: overlay.name, appeared: true, outsideDismisses: outsideDismisses, pickDismisses: pickDismisses))
            if shown() { point(w.maxX - 20, w.midY).tap() }
        }
        return FeelOverlays.evaluate(trials)
    }
}
#endif
