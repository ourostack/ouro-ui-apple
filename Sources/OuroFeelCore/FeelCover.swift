public import CoreGraphics

/// Covered content, part of the inside-the-window genre: nothing sits over what you read.
///
/// A header, bar or control (the chrome) must not cover any of the content on screen (a line of text, a picture),
/// and no chrome may sit under the status bar (`keepClear`). Content may scroll under the status bar; that is how a
/// scroll view works. Content outside the window is not judged here: where things are is the inside-the-window
/// check's job, and a paginated book keeps its next column past the side on purpose. From Gatefold build 39, whose
/// running head sat over the first line of text on the folded iPhone Duo, and whose controls sat under the status bar
/// on the open one.
public enum FeelCover {
    /// Frames that overlap by a point or less in either direction (rounding, a shared edge) do not cover each other.
    public static let tolerance: CGFloat = 1

    /// - Parameters:
    ///   - content: what you read, as the accessibility tree reported it.
    ///   - chrome: what floats over it: headers, bars, buttons.
    ///   - keepClear: places no chrome may sit, such as the status bar.
    ///   - expected: the chrome keys the caller asked for. One that was not seen could not be judged, so the check
    ///     cannot pass on it.
    public static func check(content: [FeelElement], chrome: [FeelElement], keepClear: [FeelElement] = [], window: CGRect,
                             pose: String, expected: [String] = []) -> FeelResult {
        let shown = content.filter { visible($0.frame, in: window) }
        let bars = chrome.filter { visible($0.frame, in: window) }
        var findings: [FeelFinding] = []
        for bar in bars {
            for item in shown where covers(bar.frame, item.frame) {
                let overlap = bar.frame.intersection(item.frame)
                findings.append(FeelFinding(what: "\(bar.type) \"\(bar.key)\" covers \(item.type) \"\(item.key)\" by "
                    + "\(FeelResult.number(overlap.width))×\(FeelResult.number(overlap.height)) pt at "
                    + "\(FeelLayout.describe(overlap)) in \(pose)"))
            }
            for clear in keepClear where covers(bar.frame, clear.frame) {
                findings.append(FeelFinding(what: "\(bar.type) \"\(bar.key)\" at \(FeelLayout.describe(bar.frame)) is under the "
                    + "\(clear.key) at \(FeelLayout.describe(clear.frame)) in \(pose)"))
            }
        }
        let covered = findings.count
        if shown.isEmpty { findings.append(.couldNotCheck("no content was on screen in \(pose)")) }
        let seen = Set(bars.map(\.key))
        for key in expected where !seen.contains(key) {
            findings.append(.couldNotCheck("\"\(key)\" was not on screen in \(pose)"))
        }
        return FeelResult.judged(check: FeelGenre.insideWindow.rawValue,
                                 passing: "nothing covers the \(shown.count) pieces of content in \(pose)",
                                 failing: { "\($0) covers in \(pose)" },
                                 measures: ["content": Double(shown.count), "chrome": Double(bars.count), "covers": Double(covered)],
                                 findings: findings)
    }

    /// Several poses as one result: it passes only if every pose does.
    public static func combine(_ results: [FeelResult]) -> FeelResult {
        let covers = results.reduce(0) { $0 + ($1.measures["covers"] ?? 0) }
        let failed = results.filter { !$0.passed }.count
        return FeelResult.judged(check: FeelGenre.insideWindow.rawValue,
                                 passing: "nothing covers the content in \(results.count) poses",
                                 failing: { _ in "content covered in \(failed) of \(results.count) poses" },
                                 measures: ["poses": Double(results.count), "covers": covers],
                                 findings: results.flatMap(\.findings), environment: results.first?.environment)
    }

    static func visible(_ frame: CGRect, in window: CGRect) -> Bool {
        let shown = frame.intersection(window)
        return !shown.isNull && shown.width > tolerance && shown.height > tolerance
    }

    static func covers(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = a.intersection(b)
        return !overlap.isNull && overlap.width > tolerance && overlap.height > tolerance
    }
}
