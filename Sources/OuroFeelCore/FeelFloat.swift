public import CoreGraphics

/// Chrome floats over content, under the content is the canvas: a glass control or any overlay never takes room from
/// what you read nor crops it. The content runs underneath, and its end can still be brought clear of the chrome.
///
/// From Gatefold, 2026-11-27: a Liquid Glass "start from the beginning" pill shrank the reading area and hid its last
/// lines, instead of floating over the text. Two readings judge it:
///
/// - **At rest**, each piece of chrome must sit over the content's viewport (its middle inside the viewport's frame). A
///   pill whose middle is outside it, beside the viewport's edge, has taken that room from the content.
/// - **At the end** (scrolled, or turned, as far as it goes), the content's last line must lie wholly inside the
///   viewport and the window, and under no chrome. A last line wholly outside the window was never brought on screen,
///   so that end could not be checked.
public enum FeelFloat {
    /// Frames that overlap by a point or less (rounding, a shared edge) do not cover each other.
    public static let tolerance: CGFloat = 1

    /// - Parameters:
    ///   - viewport: the content's viewport at rest (a reader's page, a scroll view), nil when it was not on screen.
    ///   - chrome: the chrome named, at rest.
    ///   - end: the content in the viewport once brought to its end, and the viewport's frame then.
    ///   - reachedEnd: whether the content stopped moving on the way to its end.
    ///   - swiped: whether swipes brought the content there and moved it on the way. Then a last line still wholly
    ///     outside the window is one no finger can bring on screen; otherwise (`toEnd:`, or swipes that moved nothing)
    ///     the end could not be checked.
    ///   - expected: the chrome keys asked for; one not seen could not be judged.
    public static func check(viewport: FeelElement?, chrome: [FeelElement], end: [FeelElement], endViewport: CGRect?,
                             endChrome: [FeelElement], window: CGRect, reachedEnd: Bool, swiped: Bool = false,
                             expected: [String], pose: String) -> FeelResult {
        var findings: [FeelFinding] = []
        guard let viewport else {
            return FeelResult.judged(check: FeelCheck.chromeFloats.name, passing: "", failing: { _ in "" },
                                     findings: [.couldNotCheck("the content's viewport was not on screen in \(pose)")])
        }
        let v = viewport.frame
        let shown = chrome.filter { FeelCover.visible($0.frame, in: window) }
        for c in shown {
            let middle = CGPoint(x: c.frame.midX, y: c.frame.midY)
            guard !v.insetBy(dx: -tolerance, dy: -tolerance).contains(middle) else { continue }
            // Which side of the viewport it sits beside, and how much room the content gave up for it.
            let room: (String, CGFloat)
            if c.frame.minY >= v.maxY - tolerance { room = ("bottom", c.frame.maxY - v.maxY) }
            else if c.frame.maxY <= v.minY + tolerance { room = ("top", v.minY - c.frame.minY) }
            else if c.frame.minX >= v.maxX - tolerance { room = ("trailing side", c.frame.maxX - v.maxX) }
            else { room = ("leading side", v.minX - c.frame.minX) }
            findings.append(FeelFinding(what: "\(c.type) \"\(c.key)\" sits beside \(viewport.type) \"\(viewport.key)\", not over "
                + "it: the content stops at its \(room.0), \(FeelResult.number(room.1.rounded())) pt short of the chrome's far "
                + "edge, so the chrome takes that room from what you read instead of floating over it, in \(pose)"))
        }
        let seen = Set(shown.map(\.key))
        for key in expected where !seen.contains(key) {
            findings.append(.couldNotCheck("\"\(key)\" was not on screen in \(pose)"))
        }

        let endFrame = endViewport ?? v
        let lines = end.filter { $0.frame.width > 0 && $0.frame.height > 0 }
        if !reachedEnd {
            findings.append(.couldNotCheck("the content was still moving after the last swipe towards its end in \(pose), so its end was not judged"))
        } else if let bottom = lines.map(\.frame.maxY).max() {
            let last = lines.filter { $0.frame.maxY >= bottom - tolerance }
            let clear = endFrame.intersection(window)
            if clear.isNull || clear.isEmpty {
                findings.append(.couldNotCheck("\"\(viewport.key)\" was not inside the window at its end in \(pose)"))
            }
            // A last line wholly outside the window was never brought on screen, so the end was not reached there.
            let unseen = last.filter { $0.frame.intersection(window).isNull || $0.frame.intersection(window).isEmpty }
            if !last.isEmpty && unseen.count == last.count {
                let line = last[0]
                if swiped {
                    let below = max(line.frame.minY - window.maxY, window.minY - line.frame.maxY, 0)
                    findings.append(FeelFinding(what: "at its end, the content's last line (\(line.type) \"\(line.key)\") cannot "
                        + "be brought on screen: swipes moved the content until it held still with that line "
                        + "\(FeelResult.number(below.rounded())) pt outside the window, in \(pose)", inferred: true))
                } else {
                    findings.append(.couldNotCheck("the content's last line (\(line.type) \"\(line.key)\") was never brought "
                        + "into the window in \(pose), so its end was not judged"))
                }
            }
            for line in last where !(clear.isNull || clear.isEmpty) && unseen.count < last.count {
                // The line must lie wholly inside what can be seen: past any edge, it is cut off.
                let sides: [(String, CGFloat)] = [("bottom", line.frame.maxY - clear.maxY), ("top", clear.minY - line.frame.minY),
                                                  ("trailing side", line.frame.maxX - clear.maxX),
                                                  ("leading side", clear.minX - line.frame.minX)]
                for (side, cut) in sides where cut > tolerance {
                    findings.append(FeelFinding(what: "at its end, the content's last line (\(line.type) \"\(line.key)\") is cut "
                        + "off: it runs \(FeelResult.number(cut.rounded())) pt past the \(side) of \"\(viewport.key)\" in \(pose)"))
                }
                for c in endChrome where FeelCover.covers(c.frame, line.frame) {
                    let overlap = c.frame.intersection(line.frame)
                    findings.append(FeelFinding(what: "at its end, the content's last line (\(line.type) \"\(line.key)\") stays "
                        + "\(FeelResult.number(overlap.height.rounded())) pt under \(c.type) \"\(c.key)\": the content cannot be "
                        + "brought clear of the chrome, in \(pose)"))
                }
            }
        } else {
            findings.append(.couldNotCheck("no content was in \"\(viewport.key)\" at its end in \(pose)"))
        }
        return FeelResult.judged(check: FeelCheck.chromeFloats.name,
                                 passing: "\(shown.count) pieces of chrome float over \"\(viewport.key)\" and its end comes clear in \(pose)",
                                 failing: { "\($0 == 1 ? "chrome crowds" : "\($0) ways chrome crowds") the content in \(pose)" },
                                 measures: ["chrome": Double(shown.count), "lines": Double(lines.count)],
                                 findings: findings)
    }

    /// Several poses as one result: it passes only if every pose does.
    public static func combine(_ results: [FeelResult]) -> FeelResult {
        guard results.count > 1 else {
            return results.first ?? check(viewport: nil, chrome: [], end: [], endViewport: nil, endChrome: [], window: .zero,
                                          reachedEnd: false, expected: [], pose: "no pose")
        }
        let failed = results.filter { !$0.passed }.count
        return FeelResult.judged(check: FeelCheck.chromeFloats.name,
                                 passing: "chrome floats over the content in \(results.count) poses",
                                 failing: { _ in "chrome crowds the content in \(failed) of \(results.count) poses" },
                                 measures: ["poses": Double(results.count)],
                                 findings: results.flatMap(\.findings), environment: results.first?.environment)
    }
}
