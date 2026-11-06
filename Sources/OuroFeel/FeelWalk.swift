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
            let button = app.buttons.keyed(key)
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
            let b = app.buttons.keyed(button)
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
            guard node.elementType != .keyboard else { return }  // The keyboard is not the screen.
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

    /// Waits (up to `limit` seconds) until the navigation bars and buttons on screen hold still between two looks
    /// 0.3 s apart: a push that is still sliding in ignores a back swipe, and the first push after launch can take
    /// longer than any fixed pause on a busy machine. This waits for the screen to land; it never repeats a gesture.
    func landed(limit: TimeInterval = 4) {
        func layout() -> String {
            guard let root = try? app.snapshot() else { return "" }
            var parts: [String] = []
            func walk(_ node: any XCUIElementSnapshot) {
                if node.elementType == .navigationBar || node.elementType == .button {
                    let f = node.frame
                    parts.append("\(Self.key(node))@\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))")
                }
                node.children.forEach(walk)
            }
            walk(root)
            return parts.joined(separator: "|")
        }
        let start = Date()
        var last = layout()
        while Date().timeIntervalSince(start) < limit {
            pause(0.3)
            let now = layout()
            if now == last { return }
            last = now
        }
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
        let window = Self.mainWindow(root)
        var keys: [String] = []
        func walk(_ node: any XCUIElementSnapshot, switcher: Bool) {
            guard node.elementType != .keyboard else { return }
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
        app.descendants(matching: .any).keyed(key)
    }

    /// The visible back control: a navigation bar's leading button, or any button whose label or identifier says
    /// back, close, done, cancel or dismiss as a whole word (``FeelWayBack/saysBack(_:)``), inside the window.
    func backAffordance() -> XCUIElement? {
        let window = windowFrame
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
        guard let key = found else { return nil }
        return app.buttons.keyed(key)
    }

    /// From the leading edge at the navigation bar's height (or near the top), where no list row sits, so a missing
    /// pop gesture never turns into a full swipe across a row and fires its swipe action.
    /// A swipe in from the leading edge. `slower` is the retry for a swipe that moved nothing: a longer press, a slow
    /// drag nearly across, and a hold before letting go, so a loaded machine has time to start the transition.
    func edgeSwipe(slower: Bool = false) {
        let w = windowFrame
        let bar = app.navigationBars.firstMatch
        let y = bar.exists && w.contains(bar.frame) ? bar.frame.midY : w.minY + min(100, w.height * 0.12)
        if slower {
            point(w.minX + 1, y).press(forDuration: 0.3, thenDragTo: point(w.minX + w.width * 0.9, y), withVelocity: .slow, thenHoldForDuration: 0.3)
        } else {
            point(w.minX + 1, y).press(forDuration: 0.05, thenDragTo: point(w.minX + w.width * 0.7, y), withVelocity: .default, thenHoldForDuration: 0)
        }
    }

    func swipeDown(slower: Bool = false) {
        let w = windowFrame
        let from = point(w.midX, w.minY + w.height * 0.12)
        if slower {
            from.press(forDuration: 0.3, thenDragTo: point(w.midX, w.maxY - 10), withVelocity: .slow, thenHoldForDuration: 0.3)
        } else {
            from.press(forDuration: 0.05, thenDragTo: point(w.midX, w.maxY - 10), withVelocity: .fast, thenHoldForDuration: 0)
        }
    }

    /// What a gesture should move, by key: for a swipe across, a few of the screen's texts (a pushed screen slides
    /// with the finger); for a swipe down, the buttons in its navigation bar if it has any (a sheet carries its Done
    /// button down, while a list pulled past its top leaves the bar's buttons where they are), else the texts.
    func anchors(_ axis: FeelGestureProgress.Axis) -> [String: CGRect] {
        let w = windowFrame
        var found: [String: CGRect] = [:]
        if axis == .vertical {
            let buttons = app.navigationBars.buttons
            for i in 0..<min(buttons.count, 4) where found.count < 2 {
                guard let b = try? buttons.element(boundBy: i).snapshot() else { continue }
                let label = b.label, frame = b.frame, key = Self.buttonAnchor + label
                if !label.isEmpty, w.intersects(frame), found[key] == nil { found[key] = frame }
            }
            if !found.isEmpty { return found }
        }
        let barFrame = (try? app.navigationBars.firstMatch.snapshot())?.frame ?? .null
        // Only labels no other text on the screen has: a read by label finds the first match, so a repeated one
        // ("1 cup" twice) could compare two different texts and look like movement.
        let texts = app.staticTexts
        var seen: [String: Int] = [:], frames: [String: CGRect] = [:], order: [String] = []
        for i in 0..<min(texts.count, 12) {
            guard let t = try? texts.element(boundBy: i).snapshot() else { continue }
            let label = t.label, frame = t.frame
            guard !label.isEmpty else { continue }
            seen[label, default: 0] += 1
            guard w.intersects(frame), barFrame.isNull || !barFrame.contains(frame), frames[label] == nil else { continue }
            frames[label] = frame
            order.append(label)
        }
        for label in order where seen[label] == 1 && found.count < 3 { found[label] = frames[label] }
        return found
    }

    /// Marks an anchor that is a navigation bar button, not a text.
    static let buttonAnchor = "\u{0}bar button "

    func anchorFrame(_ key: String) -> CGRect? {
        let e = key.hasPrefix(Self.buttonAnchor)
            ? app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", String(key.dropFirst(Self.buttonAnchor.count)))).firstMatch
            : app.staticTexts.matching(NSPredicate(format: "label == %@", key)).firstMatch
        // A snapshot, not `exists` then `frame`: the screen may go between the two (the gesture worked), and reading a
        // gone element's frame fails the test.
        return (try? e.snapshot())?.frame
    }

    /// Sends `gesture` while reading the anchors every tenth of a second, and says whether any of them moved: the
    /// partial progress of a transition, seen while the finger is still down. XCUITest's drag call keeps the main run
    /// loop turning while the touch plays, so a timer on it can read the screen mid-gesture.
    func moves(_ axis: FeelGestureProgress.Axis, during gesture: () -> Void) -> Bool {
        let before = anchors(axis)
        guard !before.isEmpty else {
            gesture()
            return false
        }
        let seen = FeelSamples()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [self] _ in
            MainActor.assumeIsolated {
                // A read can turn the run loop too; never start a second one inside the first.
                guard !seen.busy else { return }
                seen.busy = true
                var sample: [String: CGRect] = [:]
                for key in before.keys { sample[key] = anchorFrame(key) }
                seen.during.append(sample)
                seen.busy = false
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        gesture()
        timer.invalidate()
        return FeelGestureProgress.moved(before: before, during: seen.during, axis: axis, window: windowFrame)
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
            landed()
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
        var walk = Walk()
        for entry in entries {
            _ = replay(entry, [])
            visit(entry, path: [], depth: depth, limit: limit, follow: follow, walk: &walk, check: alsoInsideWindow)
        }
        var result = FeelWayBack.evaluate(walk.screens, overlays: walk.overlays, relaunches: walk.relaunches)
        // Taps that changed a screen in place were not walked; say which, so the report shows what was left out.
        result.findings += walk.skipped.map { .note("\($0): changed the screen in place (edit mode, a row expanding), so no way back was asked") }
        if !walk.capped.isEmpty {
            result.findings += walk.capped.map { .couldNotCheck("\($0): its controls kept renaming, so the walk stopped after trying three times as many as it first found") }
            result.passed = false
        }
        if !walk.missing.isEmpty {
            result.findings += walk.missing.map { .couldNotCheck("\($0): was not on screen to tap when the walk came to it, so its screen was not walked") }
            result.passed = false
        }
        let layouts = walk.layouts
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

    /// What the walk carries from screen to screen.
    struct Walk {
        var screens: [FeelDestination] = []
        var layouts: [FeelResult] = []
        var visited = Set<String>()
        var skipped: [String] = []
        var overlays: [FeelOverlayTrial] = []
        var relaunches: [String] = []
        var missing: [String] = []
        var capped: [String] = []
    }

    /// Every element on screen that has an identifier or label, of any type, with its frame and type. Unlike the
    /// signature, it includes menu items, so an open menu shows here.
    func elements() -> [String: (frame: CGRect, type: XCUIElement.ElementType)] {
        guard let root = try? app.snapshot() else { return [:] }
        let window = Self.mainWindow(root)
        var all: [String: (frame: CGRect, type: XCUIElement.ElementType)] = [:]
        func walk(_ node: any XCUIElementSnapshot) {
            // A keyboard that a text field brought up floats over rows, but it is no overlay to dismiss.
            guard node.elementType != .keyboard else { return }
            let key = Self.key(node)
            if !key.isEmpty, node.frame.width > 0, node.frame.intersects(window), all[key] == nil {
                all[key] = (node.frame, node.elementType)
            }
            node.children.forEach(walk)
        }
        walk(root)
        return all
    }

    /// Relaunches back to `path` to recover, and says so in the report.
    func recover(_ entry: FeelEntry, _ path: [String], because why: String, _ walk: inout Walk) -> Bool {
        walk.relaunches.append(why)
        return replay(entry, path)
    }

    /// An overlay a tap opened (`appeared` holds its elements): a tap outside it should close it, and so should
    /// picking an item in it, after `reopen` brings it back.
    func checkOverlay(_ name: String, appeared: [String: (frame: CGRect, type: XCUIElement.ElementType)],
                      around before: [String: (frame: CGRect, type: XCUIElement.ElementType)], reopen: () -> Void) -> FeelOverlayTrial {
        func showing() -> Bool { let now = elements(); return appeared.keys.contains { now[$0] != nil } }
        let area = appeared.values.map(\.frame).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -8, dy: -8)
        let w = windowFrame
        // Outside it, and on nothing the screen behind would act on, so the tap can only dismiss.
        let controls = before.values.filter { [.button, .cell, .link, .switch, .textField, .segmentedControl].contains($0.type) }.map(\.frame)
        let outside = [CGPoint(x: w.midX, y: w.maxY - 40), CGPoint(x: w.minX + 20, y: w.midY), CGPoint(x: w.maxX - 20, y: w.midY),
                       CGPoint(x: w.midX, y: w.midY), CGPoint(x: w.midX, y: w.minY + 70)]
            .first { p in !area.contains(p) && !controls.contains { $0.insetBy(dx: -4, dy: -4).contains(p) } }
        var outsideDismisses: Bool?
        if let p = outside {
            point(p.x, p.y).tap()
            outsideDismisses = wait(3) { !showing() }
        }
        if !showing() {
            reopen()
            pause(0.8)
            if !wait(timeout, until: showing) {
                return FeelOverlayTrial(name: name, appeared: true, outsideDismisses: outsideDismisses, pickDismisses: nil)
            }
        }
        // The topmost item that is safe to pick.
        let items = appeared.filter { [.button, .menuItem, .cell].contains($0.value.type) && !FeelSafety.isDangerous($0.key) && !FeelWayBack.saysBack($0.key) }
            .sorted { $0.value.frame.minY < $1.value.frame.minY }
        var pickDismisses: Bool?
        if let item = items.first {
            let f = item.value.frame
            point(f.midX, f.midY).tap()
            pickDismisses = wait(3) { !showing() }
        }
        return FeelOverlayTrial(name: name, appeared: true, outsideDismisses: outsideDismisses, pickDismisses: pickDismisses)
    }

    private func visit(_ entry: FeelEntry, path: [String], depth: Int, limit: Int, follow: FeelFollow, walk: inout Walk, check: Bool) {
        var here = signature(follow)
        let bars = barTitles()
        walk.visited.insert(here)
        // Re-read after a pick, which can rename this screen's controls; each key is tried once.
        var keys = followable(follow)
        var tried = Set<String>()
        var lastTap = Date()
        let place = ([entry.name] + path).joined(separator: " › ")
        // A row renamed by every tap (a saved counter, "Last opened: <time>") would yield new keys without end.
        let cap = max(3 * keys.count, 3)
        while let key = keys.first(where: { !tried.contains($0) }) {
            guard tried.count < cap else {
                walk.capped.append(place)
                return
            }
            tried.insert(key)
            guard walk.screens.count < limit else { return }
            if signature(follow) != here {
                guard recover(entry, path, because: "to get back to \(place) before trying \(key)", &walk) else { return }
                here = signature(follow)
            }
            let target = element(key)
            guard target.exists else {
                // Something earlier on this screen removed it (a pick renamed it, say): say so, never skip in silence.
                walk.missing.append(([entry.name] + path + [key]).joined(separator: " › "))
                continue
            }
            let before = elements()
            target.tap()
            lastTap = Date()
            pause(0.8)
            landed()
            let there = signature(follow)
            let after = elements()
            // What the tap added; scroll bars and other plain containers are noise.
            let appeared = after.filter { before[$0.key] == nil && $0.value.type != .other }
            let label = ([entry.name] + path + [key]).joined(separator: " › ")
            // Still this screen (same navigation bars, most of its controls still in the tree): nothing happened, an
            // overlay opened, or the screen changed in place. A system menu hides the screen behind it from the tree,
            // so it is told from a new screen by what it brought (``FeelWayBack/opensOverlay``). Up to eight of the
            // screen's other controls are enough to tell.
            let others = keys.filter { $0 != key }.prefix(8)
            let stillThere = others.filter { after[$0] != nil }.count
            let barsAfter = barTitles()
            let gone = FeelWayBack.isNewScreen(barsBefore: bars, barsAfter: barsAfter, stillThere: stillThere, of: others.count)
            // Only a tap that hid the screen can have opened a hiding overlay (a system menu).
            let hides = gone && FeelWayBack.opensOverlay(barsBefore: bars, barsAfter: barsAfter, appeared: appeared.values.map(\.frame),
                                                 appearedSaysBack: appeared.contains { FeelWayBack.saysBack($0.key) }, window: windowFrame)
            // Controls that stayed exactly where they were: an overlay floats over them; a change in place (edit
            // mode, a row expanding, "Show more") moves what it pushes aside. Cells are left out, since edit mode puts
            // its controls inside them.
            let stayed = before.filter { k, v in
                [.button, .link, .switch, .textField, .staticText].contains(v.type) && appeared[k] == nil
                    && after[k].map { abs($0.frame.minX - v.frame.minX) < 1 && abs($0.frame.minY - v.frame.minY) < 1
                        && abs($0.frame.width - v.frame.width) < 1 } == true
            }.map(\.value.frame)
            // Only what can be read or acted on floats: a glyph that changed inside a control that stayed (a disclosure
            // chevron turning) is that control's own state.
            let floating = appeared.values.filter { [.button, .cell, .link, .menuItem, .staticText, .switch, .textField].contains($0.type) }
            let overlay = hides || FeelWayBack.floatsOver(appeared: floating.map(\.frame), stayed: stayed)
            if overlay || !gone {
                if overlay {
                    // A menu or popover: it must go away with a tap outside and once an item is picked.
                    let trial = checkOverlay(label, appeared: appeared, around: before) { target.tap() }
                    walk.overlays.append(trial)
                    if elements().keys.contains(where: { appeared[$0] != nil }) {
                        guard recover(entry, path, because: "after \(label), whose overlay stayed open", &walk) else { return }
                    }
                    if barTitles() != bars {
                        // Picking took the walk somewhere else: go back rather than adopt that screen as this one.
                        guard recover(entry, path, because: "after \(label), whose pick left the screen", &walk) else { return }
                    }
                } else if !appeared.isEmpty || there != here {
                    if !walk.skipped.contains(label) { walk.skipped.append(label) }
                    if there != here {
                        guard recover(entry, path, because: "after \(label), which changed the screen in place", &walk) else { return }
                    }
                }
                // Picking may have changed this screen (a sort order, say): carry on from it as it is now.
                here = signature(follow)
                keys = followable(follow)
                walk.visited.insert(here)
                continue
            }
            if walk.visited.contains(there) {
                // A screen already checked: leave it by its own way back, or recover.
                if let back = backAffordance() { back.tap() }
                if !wait(3, until: { signature(follow) == here }) {
                    guard recover(entry, path, because: "after \(label), a screen already checked that its way back did not leave", &walk) else { return }
                }
                continue
            }
            let name = [entry.name] + path + [key]
            if check {
                let (window, found) = controls()
                walk.layouts.append(FeelLayout.check(found, window: window, pose: label))
            }
            if depth > 1 {
                visit(entry, path: path + [key], depth: depth - 1, limit: limit, follow: follow, walk: &walk, check: check)
                if signature(follow) != there {
                    _ = recover(entry, path + [key], because: "to get back to \(label) after walking past it", &walk)
                }
            }
            // The gesture first, then (back on this screen) the visible control. Each step is timed and the screen read at
            // it, so a run where no gesture returns shows where the time went and what the screen was doing.
            var gesture: String?
            let clock = Date()
            var steps: [String] = []
            func at() -> String { String(format: "%.2fs", Date().timeIntervalSince(clock)) }
            func state(_ label: String) {
                let bar = app.navigationBars.firstMatch
                let backNow = backAffordance()
                let backText = backNow.map { "\($0.label.isEmpty ? $0.identifier : $0.label) hittable=\($0.isHittable)" } ?? "none"
                steps.append("\(label) \(at()) onTarget=\(signature(follow) == there) onHere=\(signature(follow) == here) bar=\(bar.exists ? "\(bar.frame)" : "none") back=\(backText)")
            }
            let sinceTap = Date().timeIntervalSince(lastTap)
            steps.append(String(format: "tapped %.2fs before landed()", sinceTap))
            landed()
            state("landed")
            // Each gesture is watched while the finger is down. One that does not return is sent once more, slower: a
            // loaded machine can drop a synthesized drag (it moves nothing) or rush it (the screen starts to follow,
            // then settles back). If the slow one does not return either, a screen that moved has no gesture back,
            // and one that never moved was never reached, so it could not be checked.
            var arrived = false
            func attempt(_ name: String, _ axis: FeelGestureProgress.Axis, _ send: () -> Void) -> (returned: Bool, moved: Bool) {
                let moved = moves(axis, during: send)
                arrived = arrived || moved
                steps.append("\(name) sent \(at()) moved=\(moved)")
                if wait(3, until: { signature(follow) == here }) {
                    gesture = name
                    steps.append("\(name) returned \(at())")
                    return (true, moved)
                }
                state("\(name) did not return")
                return (false, moved)
            }
            if !attempt("edge swipe", .horizontal, { edgeSwipe() }).returned,
               !attempt("slower edge swipe", .horizontal, { edgeSwipe(slower: true) }).returned,
               !attempt("swipe down", .vertical, { swipeDown() }).returned {
                _ = attempt("slower swipe down", .vertical) { swipeDown(slower: true) }
            }
            let diagnostic = steps.joined(separator: "; ")
            print("[ouro-feel] gesture back from \(name.joined(separator: " › ")): \(gesture ?? "none"); \(diagnostic)")
            if gesture != nil {
                target.tap()
                pause(0.8)
                landed()
                if signature(follow) != there {
                    _ = recover(entry, path + [key], because: "to reopen \(label) after its gesture back", &walk)
                }
            }
            let back = backAffordance()
            var shown: String?
            var returns = false
            if let back {
                shown = back.label.isEmpty ? back.identifier : back.label
                back.tap()
                returns = wait(3) { signature(follow) == here }
            }
            walk.screens.append(FeelDestination(path: name, affordance: shown, affordanceReturns: returns, gesture: gesture, diagnostic: diagnostic,
                                                gestureArrived: gesture == nil ? arrived : nil))
        }
    }

    // MARK: Overlay dismissal

    /// Opens each overlay, taps outside it (it should go), opens it again and picks its item (it should go).
    public func overlays(_ overlays: [FeelOverlay]) -> FeelResult {
        var trials: [FeelOverlayTrial] = []
        for overlay in overlays {
            func shown() -> Bool {
                let c = element(overlay.overlay)
                return c.exists && c.frame.intersects(windowFrame) && c.frame.width > 0
            }
            overlay.open(app)
            guard wait(timeout, until: shown) else {
                trials.append(FeelOverlayTrial(name: overlay.name, appeared: false))
                continue
            }
            let frame = element(overlay.overlay).frame, w = windowFrame
            let outside = [CGPoint(x: w.maxX - 20, y: w.midY), CGPoint(x: w.minX + 20, y: w.midY),
                           CGPoint(x: w.midX, y: w.maxY - 60), CGPoint(x: w.midX, y: w.minY + 80)]
                .first { !frame.insetBy(dx: -8, dy: -8).contains($0) }
            var outsideDismisses: Bool?
            if let p = outside {
                point(p.x, p.y).tap()
                outsideDismisses = wait(3) { !shown() }
            }
            var pickDismisses: Bool?
            if let pick = overlay.pick {
                if !(shown() || { overlay.open(app); return wait(timeout, until: shown) }()) {
                    pickDismisses = false  // it would not open again, so the pick was never tried
                } else {
                    let item = element(pick)
                    if item.waitForExistence(timeout: timeout) {
                        item.tap()
                        pickDismisses = wait(3) { !shown() }
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

/// What a gesture's watcher saw, shared with the timer that reads the screen.
@MainActor
final class FeelSamples {
    var during: [[String: CGRect]] = []
    var busy = false
}

extension XCUIElementQuery {
    /// The first element whose identifier is `key`, or else whose label is. A predicate rather than
    /// `matching(identifier:)` or a string subscript, which throw for a string over 128 characters, and a walk's key
    /// can be a long label (a recipe card's whole description).
    func keyed(_ key: String) -> XCUIElement {
        let byID = matching(NSPredicate(format: "identifier == %@", key)).firstMatch
        return byID.exists ? byID : matching(NSPredicate(format: "label == %@", key)).firstMatch
    }
}
