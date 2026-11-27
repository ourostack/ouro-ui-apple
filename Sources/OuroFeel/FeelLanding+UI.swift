#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
public import CoreGraphics
import Foundation
public import OuroFeelCore
public import XCTest

extension OuroFeel {
    // MARK: A jump lands on its own, on time

    /// A jump lands on its own, on time (your intent is the unit): a tap on `control` (a Contents entry, a search
    /// result) brings `target` (an identifier or label only the landed jump shows) on screen within `budget` seconds,
    /// with no further input. The target has landed once it shows in the window: one that exists off screen (the next
    /// page, laid out ahead) has not.
    public func landsOnItsOwn(_ control: XCUIElement, on target: String, budget: TimeInterval = 2, within: TimeInterval = 10,
                              nudge: Bool = true) -> FeelResult {
        let predicate = NSPredicate(format: "identifier == %@ OR label == %@", target, target)
        let landed = app.descendants(matching: .any).matching(predicate).firstMatch
        let key = control.waitForExistence(timeout: timeout) ? ((try? control.snapshot()).map(Self.key) ?? target) : target
        let window = windowFrame
        return landsOnItsOwn(named: "the jump from \"\(key)\" to \"\(target)\"", budget: budget, within: within, nudge: nudge,
                             jump: { control.tap() }, landed: { landed.exists && FeelCover.visibleForUI(landed.frame, in: window) })
    }

    /// A jump lands on its own, on time: runs `jump` (a tap, a scrubber drag and release), then waits up to `within`
    /// seconds for `landed` to hold, timing it from when `jump` returned (XCUITest waits for the app to go idle around a
    /// tap, and that wait is reported as the action's own seconds). Landing past `budget` fails. If it has not landed
    /// once `within` is over and `nudge` is on, it taps the middle of the window once: a jump that lands only then was
    /// waiting for input, and fails. One that never lands could not be checked. The default budget of 2 s is for a
    /// simulator on a loaded CI runner; set a device's own.
    public func landsOnItsOwn(named intent: String, budget: TimeInterval = 2, within: TimeInterval = 10, nudge: Bool = true,
                              jump: () -> Void, landed: () -> Bool) -> FeelResult {
        var trail = FeelJumpTrail(intent: intent, budget: budget, within: max(within, budget))
        if landed() {
            trail.landedBefore = true
        } else {
            let started = Date()
            jump()
            let returned = Date()
            trail.actionSeconds = returned.timeIntervalSince(started)
            if wait(trail.within, until: landed) {
                trail.landedAfter = Date().timeIntervalSince(returned)
            } else if nudge {
                trail.nudged = true
                let window = windowFrame
                point(window.midX, window.midY).tap()
                let tapped = Date()
                if wait(5, until: landed) { trail.landedAfterNudge = Date().timeIntervalSince(tapped) }
            }
        }
        var result = FeelJump.judge(trail)
        result.environment = environment
        return result
    }

    // MARK: What you asked for lands in clear view

    /// What you asked for lands in clear view (the content is the canvas): after `jump`, `target` (the identifier or
    /// label of the search hit, the linked passage, the chosen heading) lies wholly inside the window, and inside the
    /// viewport named `over` when given, under none of `chrome` (pills, bars, banners) and not under the status bar.
    ///
    /// It waits up to `within` seconds for the target, then for its frame to hold still for half a second, and reads
    /// the target and the chrome together. Chrome that is not on screen once the jump lands covers nothing, and is noted.
    public func landsInClearView(_ target: String, chrome: [String], over viewport: String? = nil, within: TimeInterval = 5,
                                 jump: () -> Void) -> FeelResult {
        jump()
        let shown = wait(within) { reading(find: [target]).found[target] != nil }
        var last = reading(find: [target]).found[target]?.frame, since = Date()
        let deadline = Date().addingTimeInterval(within)
        while shown, Date() < deadline, Date().timeIntervalSince(since) < 0.5 {
            pause(0.1)
            let now = reading(find: [target]).found[target]?.frame
            if now != last { last = now; since = Date() }
        }
        let read = reading(find: [target] + chrome + (viewport.map { [$0] } ?? []))
        var covering = chrome.compactMap { read.found[$0] }
        #if os(iOS)
        if let bar = statusBar(window: read.window) {
            covering.append(FeelElement(key: "status bar", type: "status bar", frame: bar))
        }
        #endif
        var result = FeelClearView.check(target: read.found[target], chrome: covering,
                                         window: read.window, viewport: viewport.flatMap { read.found[$0]?.frame },
                                         expected: chrome, intent: "the jump to \"\(target)\"")
        result.environment = environment
        return result
    }

    // MARK: A notice gets out of the way

    /// A notice gets out of the way (the content is the canvas): the banner, toast or notice named `notice` never
    /// stays over what you read. It passes when the content makes room for it, or when it has gone (or moved clear)
    /// after `then` (a page turn, a scroll) or, with no `then`, after `after` seconds (5 by default).
    ///
    /// It waits for the notice to show, reads it and the content (`content` and `within` as
    /// ``uncovered(by:content:within:poses:)`` takes them), runs `then` or waits, and reads again. A notice that never
    /// showed could not be checked.
    public func noticeGivesWay(_ notice: String, content: [String] = [], within: String? = nil, after: TimeInterval = 5,
                               then: FeelPlaceStep? = nil) -> FeelResult {
        let shown = wait(timeout) { reading(find: [notice]).found[notice] != nil }
        let first = reading(content: content, within: within, excluding: [notice], find: [notice])
        if shown, let then {
            then.run(self)
            pause(1)
        } else if shown {
            pause(after)
        }
        let later = reading(content: content, within: within, excluding: [notice], find: [notice])
        var result = FeelNotice.check(notice: shown ? first.found[notice] : nil, first: first.content, later: later.found[notice],
                                      laterContent: later.content, window: later.window,
                                      then: then?.name ?? String(format: "%.1f s", after))
        result.environment = environment
        return result
    }

    // MARK: Every target is big enough to hit

    /// Every target is big enough to hit (your intent is the unit): in each pose, every enabled button, link, tab and
    /// menu on screen is at least `minimum` points on each side, by its accessibility frame: by default the platform's
    /// default control size in Apple's HIG (``FeelTargets/minimum``: 44 on iOS, 28 on macOS, 60 on visionOS).
    ///
    /// The system's own controls that Apple sizes below it are left out, with everything inside them: switches,
    /// sliders, steppers, text fields, search fields and text views (a field's clear button), segments of a segmented
    /// control, pickers, the keyboard's keys, a sheet's grabber and a Mac window's close, minimize, zoom and full-screen
    /// buttons. So is anything whose identifier or label is in `ignoring` (an inline link in running text, which HIG
    /// lets be the text's own size).
    public func targetsBigEnough(minimum: CGFloat = FeelTargets.minimum, ignoring: [String] = [],
                                 poses: [FeelPose] = [.current]) -> FeelResult {
        var results: [FeelResult] = []
        for pose in poses {
            pose.apply(self)
            let read = targets(ignoring: Set(ignoring))
            results.append(FeelTargets.check(read.targets, window: read.window, minimum: minimum, pose: pose.name))
        }
        #if os(iOS)
        if poses.contains(where: { $0.orientation != nil }) { FeelPose.portrait.apply(self) }
        #endif
        var result = FeelTargets.combine(results)
        result.environment = environment
        return result
    }

    static let targetTypes: Set<XCUIElement.ElementType> = [.button, .link, .tab, .menuButton, .popUpButton]
    /// A Mac window's own buttons, by the identifiers XCUITest gives them: the system's to size.
    static let windowButtons: Set<String> = ["_XCUI:CloseWindow", "_XCUI:MinimizeWindow", "_XCUI:ZoomWindow", "_XCUI:FullScreenWindow"]
    /// Controls whose parts are the system's to size.
    static let systemSized: Set<XCUIElement.ElementType> = [.segmentedControl, .picker, .datePicker, .keyboard, .switch, .slider, .stepper,
                                                           .textField, .secureTextField, .searchField, .textView]

    func targets(ignoring: Set<String>) -> (window: CGRect, targets: [FeelElement]) {
        guard let root = try? app.snapshot() else { return (.zero, []) }
        let window = Self.mainWindow(root)
        let keyboardTop = Self.keyboardTop(root)
        var found: [FeelElement] = []
        func walk(_ node: any XCUIElementSnapshot) {
            let type = node.elementType, identifier = node.identifier, label = node.label, enabled = node.isEnabled, frame = node.frame
            if Self.systemSized.contains(type) { return }
            if ignoring.contains(identifier) || ignoring.contains(label) || Self.windowButtons.contains(identifier) { return }
            if Self.targetTypes.contains(type), enabled, label != "Sheet Grabber", frame.width > 0, frame.height > 0,
               !Self.isSystemKeyboardKey(node, keyboardTop: keyboardTop) {
                found.append(FeelElement(key: Self.key(node), type: Self.name(type), frame: frame))
            }
            for child in node.children { walk(child) }
        }
        walk(root)
        return (window, found)
    }
}
#endif
