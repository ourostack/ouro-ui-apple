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

    public init(path: [String], affordance: String?, affordanceReturns: Bool, gesture: String?) {
        self.path = path
        self.affordance = affordance
        self.affordanceReturns = affordanceReturns
        self.gesture = gesture
    }
}

/// The way back: every screen you can reach has a visible way back and a gesture back, and both return.
public enum FeelWayBack {
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
                findings.append(FeelFinding(what: "\(name): no gesture back (neither an edge swipe nor a swipe down returned)"))
            }
        }
        if screens.isEmpty { findings.append(FeelFinding(what: "the walk reached no screens; check the entry points and what it may follow")) }
        let good = screens.filter { $0.affordance != nil && $0.affordanceReturns && $0.gesture != nil }.count
        return FeelResult(check: FeelGenre.wayBack.rawValue, passed: findings.isEmpty,
                          summary: "\(good) of \(screens.count) reachable screens have a way back and a gesture back",
                          measures: ["screens": Double(screens.count), "good": Double(good)], findings: findings)
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

    public init(name: String, appeared: Bool, outsideDismisses: Bool? = nil, pickDismisses: Bool? = nil) {
        self.name = name
        self.appeared = appeared
        self.outsideDismisses = outsideDismisses
        self.pickDismisses = pickDismisses
    }
}

/// Overlay dismissal: every sidebar, popover and menu goes away with a tap outside, and once you pick something.
public enum FeelOverlays {
    public static func evaluate(_ trials: [FeelOverlayTrial]) -> FeelResult {
        var findings: [FeelFinding] = []
        for t in trials {
            if !t.appeared { findings.append(FeelFinding(what: "\(t.name): never appeared, so it could not be checked")); continue }
            if t.outsideDismisses == false { findings.append(FeelFinding(what: "\(t.name): a tap outside it did not dismiss it")) }
            if t.pickDismisses == false { findings.append(FeelFinding(what: "\(t.name): still on screen after picking an item")) }
        }
        if trials.isEmpty { findings.append(FeelFinding(what: "no overlays were named")) }
        return FeelResult(check: FeelGenre.overlayDismissal.rawValue, passed: findings.isEmpty,
                          summary: "\(trials.count - Set(findings.map { $0.what.components(separatedBy: ":")[0] }).count) of \(trials.count) overlays dismiss as they should",
                          measures: ["overlays": Double(trials.count)], findings: findings)
    }
}
