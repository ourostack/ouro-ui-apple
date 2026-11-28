public import CoreGraphics
public import Foundation

// MARK: A jump lands on its own, on time

/// What happened after a jump, for ``FeelJump/judge(_:)``.
public struct FeelJumpTrail: Codable, Equatable, Sendable {
    /// The jump, in the report's words ("Contents to Chapter XIV").
    public var intent: String
    /// Seconds from the jump's action until its target showed with no further input; nil if it never did in `within`.
    public var landedAfter: Double?
    /// The most a jump may take to land.
    public var budget: Double
    /// How long the check waited before it nudged.
    public var within: Double
    /// Whether the check tapped the middle of the window once the wait ran out.
    public var nudged: Bool
    /// Seconds from that tap until the target showed; nil if it never did.
    public var landedAfterNudge: Double?
    /// Whether the target was on screen before the jump (the check was pointed at something already shown).
    public var landedBefore: Bool
    /// How long the jump's own action took to return (XCUITest waits for the app to go idle around a tap).
    public var actionSeconds: Double

    public init(intent: String, landedAfter: Double? = nil, budget: Double, within: Double, nudged: Bool = false,
                landedAfterNudge: Double? = nil, landedBefore: Bool = false, actionSeconds: Double = 0) {
        self.intent = intent
        self.landedAfter = landedAfter
        self.budget = budget
        self.within = within
        self.nudged = nudged
        self.landedAfterNudge = landedAfterNudge
        self.landedBefore = landedBefore
        self.actionSeconds = actionSeconds
    }
}

/// A jump lands on its own, on time, under your intent is the unit: a jump (a contents entry, a search hit, a scrubber
/// drop, a link) lands on its target within its budget, with no further input.
///
/// From Gatefold, 2026-11-27 (ourostack/gatefold#651): Contents, search and scrubber jumps held the old page greyed for
/// 4 to 8 s, and on the iPhone and the Duo's cover screen they landed only at the next tap on the page. The check
/// times the jump from when its action returns, and if the target has not shown once the wait is over, taps the middle
/// of the window once: a jump that lands only then was waiting for input it should never need.
public enum FeelJump {
    public static func judge(_ trail: FeelJumpTrail) -> FeelResult {
        var findings: [FeelFinding] = []
        var measures: [String: Double] = ["budget": trail.budget]
        if trail.actionSeconds > 0 { measures["action seconds"] = round3(trail.actionSeconds) }
        let s = FeelIntent.seconds
        if trail.landedBefore {
            findings.append(.couldNotCheck("the target of \(trail.intent) was on screen before the jump: name something only "
                + "the landed jump shows (the target page's words, not a title that both show)"))
        } else if let landed = trail.landedAfter {
            measures["seconds"] = round3(landed)
            if landed > trail.budget {
                findings.append(FeelFinding(what: "\(trail.intent) took \(s(landed)) s to land, past its \(s(trail.budget)) s budget"))
            }
        } else if trail.nudged, let nudge = trail.landedAfterNudge {
            measures["seconds after the tap"] = round3(nudge)
            findings.append(FeelFinding(what: "\(trail.intent) had not landed \(s(trail.within)) s after the jump, and landed only "
                + "after a tap on the middle of the window, \(s(nudge)) s after it: the jump waited for input"))
        } else {
            findings.append(.couldNotCheck("\(trail.intent) had not landed \(s(trail.within)) s after the jump"
                + (trail.nudged ? ", nor after a tap on the middle of the window" : "")
                + ": the jump may have been lost, or the target is named wrong (name what only the landed jump shows)"))
        }
        return FeelResult.judged(check: FeelCheck.landsOnItsOwn.name,
                                 passing: "\(trail.intent) landed in \(s(trail.landedAfter ?? 0)) s, within its \(s(trail.budget)) s budget, with no further input",
                                 failing: { _ in "\(trail.intent) did not land on its own, on time" },
                                 measures: measures, findings: findings)
    }
}

// MARK: What you asked for lands in clear view

/// What you asked for lands in clear view, under the content is the canvas: the target of a jump (a search hit, a
/// linked passage, a chosen chapter's heading) lands wholly inside the window and its viewport, under no chrome.
///
/// From Gatefold, 2026-11-27 (ourostack/gatefold#652): a search landed with the hit on the second-to-last line, under
/// the "Back to where you were" pill; only the end of the word and its underline showed beside it.
public enum FeelClearView {
    public static let tolerance: CGFloat = 1

    /// - Parameters:
    ///   - target: the target once the jump had landed, nil when it never showed.
    ///   - viewport: the frame of the viewport it lands in (a reader's page), when one was named.
    ///   - chrome: the chrome named, as it was once the jump landed. Chrome that is not there covers nothing.
    public static func check(target: FeelElement?, chrome: [FeelElement], window: CGRect, viewport: CGRect? = nil,
                             expected: [String] = [], intent: String) -> FeelResult {
        guard let target else {
            return FeelResult.judged(check: FeelCheck.landsInClearView.name, passing: "", failing: { _ in "" },
                                     findings: [.couldNotCheck("the target of \(intent) never showed, so where it landed was not seen")])
        }
        var findings: [FeelFinding] = []
        var clear = window
        if let viewport { clear = clear.intersection(viewport) }
        let f = target.frame
        if clear.isNull || clear.isEmpty {
            findings.append(.couldNotCheck("the viewport was not inside the window after \(intent)"))
        } else {
            let sides: [(String, CGFloat)] = [("bottom", f.maxY - clear.maxY), ("top", clear.minY - f.minY),
                                              ("trailing side", f.maxX - clear.maxX), ("leading side", clear.minX - f.minX)]
            for (side, cut) in sides where cut > tolerance {
                findings.append(FeelFinding(what: "\(target.type) \"\(target.key)\" landed cut off: it runs "
                    + "\(FeelResult.number(cut.rounded())) pt past the \(side) of \(viewport == nil ? "the window" : "its viewport") after \(intent)"))
            }
        }
        let shown = chrome.filter { FeelCover.visible($0.frame, in: window) }
        for c in shown where FeelCover.covers(c.frame, f) {
            let overlap = c.frame.intersection(f)
            findings.append(FeelFinding(what: "\(target.type) \"\(target.key)\" landed under \(c.type) \"\(c.key)\": "
                + "\(FeelResult.number(overlap.width.rounded()))×\(FeelResult.number(overlap.height.rounded())) pt of it is covered after \(intent)"))
        }
        let seen = Set(shown.map(\.key))
        let absent = expected.filter { !seen.contains($0) }
        if !absent.isEmpty {
            findings.append(.note("\(absent.map { "\"\($0)\"" }.joined(separator: ", ")) was not on screen once \(intent) landed, so it covered nothing"))
        }
        return FeelResult.judged(check: FeelCheck.landsInClearView.name,
                                 passing: "\"\(target.key)\" landed wholly in view, under none of \(shown.count) pieces of chrome, after \(intent)",
                                 failing: { _ in "\"\(target.key)\" did not land in clear view after \(intent)" },
                                 measures: ["chrome": Double(shown.count)], findings: findings)
    }
}

// MARK: A notice gets out of the way

/// A notice gets out of the way, under the content is the canvas: a banner, toast or notice shown while you read never
/// stays over the content. It makes room (the content insets for it), or it goes once you act or wait.
///
/// From Gatefold, 2026-11-27 (ourostack/gatefold#654): the re-sign-in notice floated over the top of the page and
/// covered its first line, and after a page turn it was still there, over the first line of the next page.
public enum FeelNotice {
    /// - Parameters:
    ///   - notice: the notice when it first showed; nil when it never did.
    ///   - first: the content it covered then.
    ///   - later: the notice after `then` (an action, or a wait), nil when it had gone.
    ///   - laterContent: the content on screen then.
    ///   - then: what happened between the two readings, in the report's words ("a page turn", "5 s").
    public static func check(notice: FeelElement?, first: [FeelElement], later: FeelElement?, laterContent: [FeelElement],
                             window: CGRect, then: String) -> FeelResult {
        guard let notice else {
            return FeelResult.judged(check: FeelCheck.noticeGivesWay.name, passing: "", failing: { _ in "" },
                                     findings: [.couldNotCheck("the notice never showed, so whether it gets out of the way was not seen")])
        }
        let coveredFirst = first.filter { FeelCover.visible($0.frame, in: window) && FeelCover.covers(notice.frame, $0.frame) }
        var findings: [FeelFinding] = []
        var coveredLater: [FeelElement] = []
        if let later {
            coveredLater = laterContent.filter { FeelCover.visible($0.frame, in: window) && FeelCover.covers(later.frame, $0.frame) }
            if !coveredLater.isEmpty {
                let items = coveredLater.prefix(3).map { "\($0.type) \"\($0.key)\"" }.joined(separator: ", ")
                findings.append(FeelFinding(what: "\(later.type) \"\(later.key)\" still covers \(coveredLater.count == 1 ? "" : "\(coveredLater.count) pieces of content, ")"
                    + "\(items)\(coveredLater.count > 3 ? " and more" : "") after \(then)"
                    + (coveredFirst.isEmpty ? "" : ", as it covered \(coveredFirst.count == 1 ? "one" : "\(coveredFirst.count)") when it first showed")))
            }
        }
        if laterContent.isEmpty && later != nil {
            findings.append(.couldNotCheck("no content was on screen after \(then)"))
        }
        let passing: String
        if coveredFirst.isEmpty && later != nil {
            passing = "\"\(notice.key)\" covers none of the content, before or after \(then)"
        } else if later == nil {
            passing = "\"\(notice.key)\" was gone after \(then)"
        } else {
            passing = "\"\(notice.key)\" moved off the content after \(then)"
        }
        return FeelResult.judged(check: FeelCheck.noticeGivesWay.name, passing: passing,
                                 failing: { _ in "\"\(notice.key)\" stays over the content after \(then)" },
                                 measures: ["covered first": Double(coveredFirst.count), "covered later": Double(coveredLater.count)],
                                 findings: findings)
    }
}

// MARK: Every target is big enough to hit

/// Every target is big enough to hit, under your intent is the unit: every button, link and tab on screen is at least
/// the default control size [Apple's Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/accessibility#Mobility)
/// give for its platform ("Offer sufficiently sized controls"): 44 by 44 points on iOS, iPadOS and watchOS, 28 on macOS,
/// 60 on visionOS and 66 on tvOS, so a tap lands where you aim.
///
/// From the Gatefold jank hunt's notes, 2026-11-27: a dump of the iPhone Duo's reader showed its close button with a 14
/// by 14 point accessibility frame, not confirmed as a real tap-size problem. The frame is what accessibility reports;
/// a control that answers taps beyond its frame (UIKit's `point(inside:with:)`) is bigger than it reads, so a finding
/// is marked inference. SwiftUI's `contentShape` and padding inside a button's label do grow the frame.
public enum FeelTargets {
    /// The platform's default control size, in points, from the HIG's table. A Mac Catalyst app is a Mac app.
    #if os(macOS) || targetEnvironment(macCatalyst)
    public static let minimum: CGFloat = 28
    #elseif os(visionOS)
    public static let minimum: CGFloat = 60
    #elseif os(tvOS)
    public static let minimum: CGFloat = 66
    #else
    public static let minimum: CGFloat = 44
    #endif
    /// Frames come back in fractional points: this much short is rounding, not a smaller target.
    public static let slack: CGFloat = 0.01

    public static func check(_ targets: [FeelElement], window: CGRect, minimum: CGFloat = minimum, pose: String) -> FeelResult {
        let shown = targets.filter { FeelCover.visible($0.frame, in: window) }
        var findings: [FeelFinding] = []
        for t in shown where t.frame.width < minimum - slack || t.frame.height < minimum - slack {
            findings.append(FeelFinding(what: "\(t.type) \"\(t.key)\" is \(FeelResult.number(round1(t.frame.width)))×"
                + "\(FeelResult.number(round1(t.frame.height))) pt, under \(FeelResult.number(minimum)) pt on a side, in \(pose)",
                inferred: true))
        }
        if shown.isEmpty { findings.append(.couldNotCheck("no buttons, links or tabs were on screen in \(pose)")) }
        return FeelResult.judged(check: FeelCheck.targetsBigEnough.name,
                                 passing: "all \(shown.count) targets are at least \(FeelResult.number(minimum)) pt on each side in \(pose)",
                                 failing: { "\($0 == 1 ? "1 target is" : "\($0) targets are") under \(FeelResult.number(minimum)) pt in \(pose)" },
                                 measures: ["targets": Double(shown.count)], findings: findings)
    }

    /// Several poses as one result: it passes only if every pose does.
    public static func combine(_ results: [FeelResult]) -> FeelResult {
        guard results.count > 1 else { return results.first ?? check([], window: .zero, pose: "no pose") }
        let failed = results.filter { !$0.passed }.count
        return FeelResult.judged(check: FeelCheck.targetsBigEnough.name,
                                 passing: "every target is big enough in \(results.count) poses",
                                 failing: { _ in "targets too small in \(failed) of \(results.count) poses" },
                                 measures: ["poses": Double(results.count)],
                                 findings: results.flatMap(\.findings), environment: results.first?.environment)
    }

    static func round1(_ v: CGFloat) -> Double { (Double(v) * 10).rounded() / 10 }
}
