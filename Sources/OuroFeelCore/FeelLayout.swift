public import CoreGraphics

/// A control (or any element) as the accessibility tree reported it.
public struct FeelElement: Codable, Equatable, Sendable {
    /// The identifier, or the label when there is none.
    public var key: String
    public var type: String
    public var frame: CGRect
    /// The frame of the nearest scroll view around it, if any.
    public var scroll: CGRect?
    /// Whether that scroll view scrolls sideways (a carousel) rather than up and down.
    public var scrollsHorizontally: Bool

    public init(key: String, type: String, frame: CGRect, scroll: CGRect? = nil, scrollsHorizontally: Bool = false) {
        self.key = key
        self.type = type
        self.frame = frame
        self.scroll = scroll
        self.scrollsHorizontally = scrollsHorizontally
    }
}

/// Every control lies inside the window.
///
/// XCUITest's `isHittable` and `tap()` accept points past the window's edge on the simulator, where no finger can
/// reach (Gatefold build 19's portrait Fine-Tune panel passed taps this way), so this compares frames and never asks
/// `isHittable`. A control scrolled out of view is fine when the scroll view around it is itself inside the window and
/// the control is off only along the axis it scrolls: a vertical list does not excuse a control off the side.
public enum FeelLayout {
    /// Half a point of slack for rounding at the window's edge.
    public static let tolerance: CGFloat = 0.5

    public static func check(_ controls: [FeelElement], window: CGRect, pose: String) -> FeelResult {
        let slack = window.insetBy(dx: -tolerance, dy: -tolerance)
        var findings: [FeelFinding] = []
        var counted = 0
        for control in controls where control.frame.width > 0 && control.frame.height > 0 {
            counted += 1
            if slack.contains(control.frame) { continue }
            if let scroll = control.scroll, slack.contains(scroll) {
                let across = control.scrollsHorizontally
                    ? control.frame.minY >= slack.minY && control.frame.maxY <= slack.maxY
                    : control.frame.minX >= slack.minX && control.frame.maxX <= slack.maxX
                if across { continue }
            }
            findings.append(FeelFinding(what: "\(control.type) \"\(control.key)\" at \(describe(control.frame)) is outside the "
                + "\(describe(window)) window in \(pose)"))
        }
        if counted == 0 {
            findings.append(FeelFinding(what: "no controls were seen in \(pose), so nothing was checked"))
        }
        let summary = counted == 0 ? "no controls seen in \(pose)" : findings.isEmpty
            ? "all \(counted) controls inside the window in \(pose)"
            : "\(findings.count) of \(counted) controls outside the window in \(pose)"
        return FeelResult(check: FeelGenre.insideWindow.rawValue, passed: findings.isEmpty, summary: summary,
                          measures: ["controls": Double(counted), "outside": Double(findings.count)], findings: findings)
    }

    /// Several poses as one result: it passes only if every pose does.
    public static func combine(_ results: [FeelResult]) -> FeelResult {
        let failed = results.filter { !$0.passed }
        let outside = results.reduce(0) { $0 + ($1.measures["outside"] ?? 0) }
        let summary = failed.isEmpty
            ? "every control inside the window in \(results.count) poses"
            : "controls outside the window in \(failed.count) of \(results.count) poses"
        return FeelResult(check: FeelGenre.insideWindow.rawValue, passed: failed.isEmpty, summary: summary,
                          measures: ["poses": Double(results.count), "outside": outside],
                          findings: results.flatMap(\.findings), environment: results.first?.environment)
    }

    static func describe(_ r: CGRect) -> String {
        "(\(FeelResult.number(r.minX)), \(FeelResult.number(r.minY)), \(FeelResult.number(r.width))×\(FeelResult.number(r.height)))"
    }
}
