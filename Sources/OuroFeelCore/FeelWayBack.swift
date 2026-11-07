import CoreGraphics
/// One screen a walk reached, and how it could be left.
public struct FeelDestination: Codable, Equatable, Sendable {
    /// What was tapped to get here, from the entry point.
    public var path: [String]
    /// The visible control that leads back (a Back, Close or Done button), if there is one.
    public var affordance: String?
    /// Whether tapping it returned to the screen before.
    public var affordanceReturns: Bool
    /// The gesture that returned (`edge swipe`, `swipe down`), if any did.
    public var gesture: String?
    /// When each step of leaving this screen happened and what the screen looked like at each, kept so a run that
    /// finds no gesture back shows the race (and a run that passes can be compared with it).
    public var diagnostic: String?
    /// When no gesture returned: whether any of them moved the screen while the finger was down. `true` means a
    /// transition started and settled back (no way back, a bug); `false` means none moved anything, even when retried
    /// slower, so the touch may never have reached the app (could not check). `nil` (an older record) counts as a bug.
    public var gestureArrived: Bool?

    public init(path: [String], affordance: String?, affordanceReturns: Bool, gesture: String?, diagnostic: String? = nil,
                gestureArrived: Bool? = nil) {
        self.path = path
        self.affordance = affordance
        self.affordanceReturns = affordanceReturns
        self.gesture = gesture
        self.diagnostic = diagnostic
        self.gestureArrived = gestureArrived
    }
}

/// Whether a gesture moved the screen while the finger was down: the partial progress of an interactive transition
/// (a pushed screen sliding right under an edge swipe, a sheet following a pull down). Read from a few of the screen's
/// texts, keyed by label, sampled during the drag.
public enum FeelGestureProgress {
    public enum Axis: String, Codable, Sendable { case horizontal, vertical }

    /// True if, in any sample, an anchor still on screen sat at least 5% of the window (and at least 12 points) from
    /// where it was before the gesture, along `axis`. An anchor missing from a sample tells nothing either way.
    public static func moved(before: [String: CGRect], during: [[String: CGRect]], axis: Axis, window: CGRect) -> Bool {
        let extent = axis == .horizontal ? window.width : window.height
        let enough = max(12, extent * 0.05)
        for sample in during {
            for (key, then) in before {
                guard let now = sample[key] else { continue }
                let shift = axis == .horizontal ? now.minX - then.minX : now.minY - then.minY
                if abs(shift) >= enough { return true }
            }
        }
        return false
    }
}

/// The way back: every screen you can reach has a visible way back and a gesture back, and both return.
public enum FeelWayBack {
    /// `overlays` are menus and popovers a tap opened on a screen, checked for dismissal (a tap outside, then picking
    /// an item); one that stays open fails the way back. `relaunches` names each time the walk had to relaunch the
    /// app to recover, listed as a note so it never passes silently.
    public static func evaluate(_ screens: [FeelDestination], overlays: [FeelOverlayTrial] = [], relaunches: [String] = []) -> FeelResult {
        var result = evaluate(screens)
        if !overlays.isEmpty {
            let checked = FeelOverlays.evaluate(overlays)
            result.findings += checked.findings
            let tried = overlays.filter(\.appeared).count
            let fine = overlays.filter { $0.appeared && $0.outsideDismisses == true && $0.pickDismisses != false }.count
            result.summary += "; \(fine) of \(tried) overlays the walk opened dismiss"
            result.measures["overlays"] = Double(overlays.count)
            result.passed = result.passed && checked.passed
        }
        result.findings += relaunches.map { .note("relaunched the app \($0)") }
        if !relaunches.isEmpty { result.summary += " (after \(relaunches.count) relaunch\(relaunches.count == 1 ? "" : "es") to recover)" }
        result.measures["relaunches"] = Double(relaunches.count)
        return result
    }

    public static func evaluate(_ screens: [FeelDestination]) -> FeelResult {
        var findings: [FeelFinding] = []
        for screen in screens {
            let name = screen.path.joined(separator: " › ")
            if screen.affordance == nil {
                findings.append(FeelFinding(what: "\(name): no visible way back (no Back, Close, Done or Cancel button)"))
            } else if !screen.affordanceReturns {
                findings.append(FeelFinding(what: "\(name): \"\(screen.affordance!)\" did not return to the screen before"))
            }
            if screen.gesture == nil {
                let evidence = screen.diagnostic.map { " [steps: \($0)]" } ?? ""
                switch screen.gestureArrived {
                case false?:
                    findings.append(.couldNotCheck("\(name): the gesture back moved nothing, neither an edge swipe nor a swipe down, each also sent slower, so either the gesture is off on this screen or the touch never reached the app\(evidence)"))
                case true?:
                    findings.append(FeelFinding(what: "\(name): no gesture back (a swipe moved the screen, then it settled back where it was)\(evidence)"))
                case nil:
                    findings.append(FeelFinding(what: "\(name): no gesture back (neither an edge swipe nor a swipe down returned)\(evidence)"))
                }
            }
        }
        if screens.isEmpty { findings.append(.couldNotCheck("the walk reached no screens; check the entry points and what it may follow")) }
        let good = screens.filter { $0.affordance != nil && $0.affordanceReturns && $0.gesture != nil }.count
        let summary = "\(good) of \(screens.count) reachable screens have a way back and a gesture back"
        return FeelResult.judged(check: FeelGenre.wayBack.rawValue, passing: summary, failing: { _ in summary },
                                 measures: ["screens": Double(screens.count), "good": Double(good)], findings: findings)
    }

    /// Whether a tap reached a new screen. A tap that left the navigation bars as they were (`barsBefore`, by
    /// ``barIdentity(key:backLabels:)``) and most of the screen's followable controls still in the tree (`stillThere`
    /// of `of`; covered counts) changed the screen in place (a menu opened, edit mode, a row expanded), so the walk
    /// does not ask it for a way back.
    public static func isNewScreen(barsBefore: [String], barsAfter: [String], stillThere: Int, of total: Int) -> Bool {
        if barsBefore.sorted() != barsAfter.sorted() { return true }
        guard total > 0 else { return true }
        return Double(stillThere) / Double(total) < 0.5
    }

    /// A navigation bar's identity for the walk: its key (its title, or SwiftUI's identifier when it has none) and the
    /// labels of its back buttons. An untitled bar keeps one identifier from screen to screen; its back button says
    /// where it goes back to, so a push changes it.
    public static func barIdentity(key: String, backLabels: [String]) -> String {
        ([key] + backLabels).joined(separator: backMark)
    }

    static let backMark = " ‹ "

    /// Whether a navigation-bar button is the bar's way back to the last screen: the system back button (identifier
    /// `BackButton`) or one whose identifier or label says back. Done, Cancel and Close are not: edit mode, selection
    /// and a popover's own bar bring them without leaving the screen.
    public static func isBackButton(identifier: String, label: String) -> Bool {
        identifier == "BackButton" || (FeelSafety.words(identifier) + FeelSafety.words(label)).contains(" back ")
    }

    /// Whether a tap replaced a navigation bar that was on screen (`barsBefore`, by ``barIdentity(key:backLabels:)``),
    /// or brought a bar with a back button: it went somewhere new, so it opened no overlay, whatever its content
    /// overlaps (a pushed page scrolling under a tab bar that stayed). Only adding a bar with no way back, as a
    /// popover with its own does, leaves an overlay possible.
    public static func replacedBar(barsBefore: [String], barsAfter: [String]) -> Bool {
        let before = Set(barsBefore)
        return !before.isSubset(of: Set(barsAfter)) || barsAfter.contains { !before.contains($0) && $0.contains(backMark) }
    }

    /// A height beside the page's middle for an edge swipe, with nothing at the leading edge that a missing pop would
    /// turn the swipe into (a row's swipe action, a carousel): the first of a few heights near the middle that no
    /// `blocked` frame touching the edge covers, or nil when none is free, so the swipe is better not sent.
    public static func quietEdgeHeight(window w: CGRect, blocked: [CGRect]) -> CGFloat? {
        let edge = w.minX + 1
        return [0.5, 0.42, 0.58, 0.34, 0.66].map { w.minY + w.height * $0 }
            .first { y in !blocked.contains { $0.minX <= edge + 30 && $0.maxX >= edge && $0.minY <= y && $0.maxY >= y } }
    }

    /// Whether a tap left the screen by its content: under half of the screen's own texts and controls (`kept` of `of`,
    /// leaving out the tab and navigation bars every screen shares) are still there. A menu, edit mode or a row
    /// expanding keeps the content around it; a push replaces it, even when the bar and a shared control stay. Under
    /// four to compare says nothing.
    public static func leftContent(kept: Int, of total: Int) -> Bool {
        total >= 4 && Double(kept) / Double(total) < 0.5
    }

    /// Whether a tap that hid the screen's controls opened an overlay rather than a new screen. A system menu hides the
    /// screen behind it from the accessibility tree, as a push does; unlike a screen, it brings no navigation bar of
    /// its own (`barsAfter` holds none that `barsBefore` lacked), no way back of its own, and covers under 60% of the
    /// window (`appeared`, the frames of what the tap added).
    public static func opensOverlay(barsBefore: [String], barsAfter: [String], appeared: [CGRect],
                                    appearedSaysBack: Bool, window: CGRect) -> Bool {
        guard !appeared.isEmpty, !appearedSaysBack, Set(barsAfter).isSubset(of: Set(barsBefore)) else { return false }
        let area = appeared.reduce(CGRect.null) { $0.union($1) }.intersection(window)
        guard !area.isNull, window.width > 0, window.height > 0 else { return false }
        return area.width * area.height < 0.6 * window.width * window.height
    }

    /// Whether what a tap added (`appeared`) floats over controls that stayed exactly where they were (`stayed`): an
    /// overlay on the screen. A change in place (edit mode, a row expanding, "Show more", validation text) moves the
    /// controls it pushes aside, so they do not stay. An overlap counts when it is at least a quarter of the smaller
    /// frame.
    public static func floatsOver(appeared: [CGRect], stayed: [CGRect]) -> Bool {
        appeared.contains { a in
            stayed.contains { b in
                let i = a.intersection(b)
                guard !i.isNull, !i.isEmpty else { return false }
                return i.width * i.height >= 0.25 * min(a.width * a.height, b.width * b.height)
            }
        }
    }

    /// Words that mark a control as a way back. They match whole words only, so "Feedback" and "Playback" are not.
    public static let backWords = ["back", "close", "done", "cancel", "dismiss"]

    /// Whether any of `texts` (identifiers or labels, split as ``FeelSafety/words(_:)`` splits them) says back.
    public static func saysBack(_ texts: String...) -> Bool {
        let all = texts.map(FeelSafety.words).joined()
        return backWords.contains { all.contains(" \($0) ") }
    }
}

/// One overlay (sidebar, popover, menu) opened and dismissed.
public struct FeelOverlayTrial: Codable, Equatable, Sendable {
    public var name: String
    public var appeared: Bool
    /// Whether a tap outside it dismissed it; nil when not tried.
    public var outsideDismisses: Bool?
    /// Whether picking an item in it dismissed it; nil when not tried.
    public var pickDismisses: Bool?
    /// Why no pick was asked of it, when it is no menu: a popover of controls (a stepper, a slider) stays open while
    /// you adjust them and closes with a tap outside.
    public var noPickBecause: String?
    /// True when the tap outside changed the screen behind (it went through the overlay to a row, say), so whether
    /// the overlay dismisses was not seen. `outsideDismisses` is then nil.
    public var outsideLandedBehind: Bool?

    public init(name: String, appeared: Bool, outsideDismisses: Bool? = nil, pickDismisses: Bool? = nil, noPickBecause: String? = nil,
                outsideLandedBehind: Bool? = nil) {
        self.name = name
        self.appeared = appeared
        self.outsideDismisses = outsideDismisses
        self.pickDismisses = pickDismisses
        self.noPickBecause = noPickBecause
        self.outsideLandedBehind = outsideLandedBehind
    }
}

/// Overlay dismissal: every sidebar, popover and menu goes away with a tap outside, and once you pick something.
public enum FeelOverlays {
    public static func evaluate(_ trials: [FeelOverlayTrial]) -> FeelResult {
        var findings: [FeelFinding] = []
        for t in trials {
            if !t.appeared { findings.append(.couldNotCheck("\(t.name): never appeared")); continue }
            if t.outsideDismisses == false { findings.append(FeelFinding(what: "\(t.name): a tap outside it did not dismiss it")) }
            if t.outsideLandedBehind == true {
                findings.append(.couldNotCheck("\(t.name): the tap outside landed on the screen behind (the screen changed), so whether it dismisses was not seen"))
            } else if t.outsideDismisses == nil {
                findings.append(.couldNotCheck("\(t.name): there was no place outside it to tap, so a tap outside was not tried"))
            }
            if t.pickDismisses == false { findings.append(FeelFinding(what: "\(t.name): still on screen after picking an item")) }
            if let why = t.noPickBecause { findings.append(.note("\(t.name): \(why), so only a tap outside was asked of it")) }
        }
        if trials.isEmpty { findings.append(.couldNotCheck("no overlays were named")) }
        let tried = trials.filter(\.appeared).count
        let failing = Set(findings.filter { !$0.unchecked }.map { $0.what.components(separatedBy: ":")[0] }).count
        let summary = "\(tried - failing) of \(tried) overlays dismiss as they should"
        return FeelResult.judged(check: FeelGenre.overlayDismissal.rawValue, passing: summary, failing: { _ in summary },
                                 measures: ["overlays": Double(trials.count)], findings: findings)
    }
}
