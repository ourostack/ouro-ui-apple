public import CoreGraphics
public import Foundation

// MARK: Content clears the fold

/// Content clears the fold, under posture changes re-lay out in place: in every fold posture, nothing you read runs
/// across the hinge, and a device held open like a book shows a page on each side of it.
///
/// From Gatefold, 2026-11-27 (ourostack/gatefold#646): an iPhone Duo half-open with its hinge upright, held like a
/// book, laid the page out as one column of text straight across the fold, with the controls panel across the other
/// half. The fold is whatever the app reports for it (OuroHX's `OuroFoldRegion.frame`), so the judge needs no folding
/// device: a fixture or a simulator declares one.
public enum FeelFold {
    /// Frames that reach a point or less past the fold's edge (rounding, a shared edge) do not cross it.
    public static let tolerance: CGFloat = 1

    /// - Parameters:
    ///   - content: what you read, as the accessibility tree reported it.
    ///   - fold: the hinge or fold, in the window's coordinates; zero-width when the fold is a seam. Nil when none was
    ///     declared or seen, which cannot be checked.
    ///   - spread: whether content must lie on both sides of a fold that runs top to bottom (a book's two-page spread).
    ///   - posture: the posture's name, for the report ("half-open like a book").
    public static func check(content: [FeelElement], fold: CGRect?, window: CGRect, spread: Bool = false,
                             posture: String) -> FeelResult {
        guard let fold, !fold.isNull, fold.insetBy(dx: -tolerance, dy: -tolerance).intersects(window) else {
            return FeelResult.judged(check: FeelCheck.clearsTheFold.name, passing: "", failing: { _ in "" },
                                     findings: [.couldNotCheck("no fold inside the window was declared in \(posture): put an "
                                         + "accessibility element over the hinge (OuroHX's OuroFoldRegion.frame), or pass its frame")])
        }
        let upright = fold.height >= fold.width
        let shown = content.filter { FeelCover.visible($0.frame, in: window) }
        var findings: [FeelFinding] = []
        var crossing = 0
        for item in shown where crosses(item.frame, fold) {
            crossing += 1
            let (a, b): (CGFloat, CGFloat) = upright
                ? (fold.minX - item.frame.minX, item.frame.maxX - fold.maxX)
                : (fold.minY - item.frame.minY, item.frame.maxY - fold.maxY)
            if a > tolerance, b > tolerance {
                findings.append(FeelFinding(what: "\(item.type) \"\(item.key)\" runs across the fold in \(posture): "
                    + "\(FeelResult.number(a.rounded())) pt of it on one side and \(FeelResult.number(b.rounded())) pt on the other"))
            } else {
                let under = item.frame.intersection(fold)
                findings.append(FeelFinding(what: "\(item.type) \"\(item.key)\" reaches under the fold in \(posture): "
                    + "\(FeelResult.number((upright ? under.width : under.height).rounded())) pt of it lies under the fold"))
            }
        }
        if spread {
            if upright {
                let leading = shown.filter { $0.frame.maxX <= fold.minX + tolerance }.count
                let trailing = shown.filter { $0.frame.minX >= fold.maxX - tolerance }.count
                if !shown.isEmpty && (leading == 0 || trailing == 0) {
                    findings.append(FeelFinding(what: "held open like a book (\(posture)), the "
                        + "\(leading == 0 ? "leading" : "trailing") side of the fold has no page: a book shows a page on each side"))
                }
            } else {
                findings.append(.note("a spread was asked for, but the fold runs across the screen in \(posture), so only "
                    + "crossing was judged; a spread is judged on a fold that runs top to bottom"))
            }
        }
        if shown.isEmpty { findings.append(.couldNotCheck("no content was on screen in \(posture)")) }
        return FeelResult.judged(check: FeelCheck.clearsTheFold.name,
                                 passing: "none of the \(shown.count) pieces of content crosses the fold"
                                    + (spread && upright ? ", and both sides hold a page," : "") + " in \(posture)",
                                 failing: { _ in "content does not clear the fold in \(posture)" },
                                 measures: ["content": Double(shown.count), "crossing": Double(crossing)],
                                 findings: findings)
    }

    /// Whether `frame` reaches into `fold` by more than a point on both axes: across it, or under it (a hinge hides
    /// what lies under it). A zero-width fold (a seam) is crossed by anything more than a point past it on each side.
    static func crosses(_ frame: CGRect, _ fold: CGRect) -> Bool {
        let acrossX = frame.minX < fold.maxX - tolerance && frame.maxX > fold.minX + tolerance
        let acrossY = frame.minY < fold.maxY - tolerance && frame.maxY > fold.minY + tolerance
        return acrossX && acrossY
    }

    /// Several postures as one result: it passes only if every posture does.
    public static func combine(_ results: [FeelResult]) -> FeelResult {
        guard results.count > 1 else { return results.first ?? check(content: [], fold: nil, window: .zero, posture: "no posture") }
        let failed = results.filter { !$0.passed }.count
        return FeelResult.judged(check: FeelCheck.clearsTheFold.name,
                                 passing: "content clears the fold in \(results.count) postures",
                                 failing: { _ in "content does not clear the fold in \(failed) of \(results.count) postures" },
                                 measures: ["postures": Double(results.count)],
                                 findings: results.flatMap(\.findings), environment: results.first?.environment)
    }
}

// MARK: A turn lays out like a fresh launch

/// A turn lays out like a fresh launch, under posture changes re-lay out in place: a few seconds after the device
/// turns, folds or unfolds, the screen is laid out as a fresh launch in that posture lays it out. Nothing lingers from
/// the old shape, and nothing the new one shows is missing.
///
/// From Gatefold, 2026-11-27: opening an iPhone Duo flat after holding it half-open like a book kept the tabletop
/// layout, the controls panel up and the page cut off mid-line, for 10 s and more (ourostack/gatefold#647); an iPad
/// took 6 to 7 s to land its new layout after a turn (#649).
public enum FeelRelayout {
    /// Frames this close (in points, on every edge) are the same place.
    public static let tolerance: CGFloat = 2

    /// - Parameters:
    ///   - turned: the elements compared (identified ones), `waited` seconds after `change`.
    ///   - fresh: the same, from a fresh launch in the posture the change ended in.
    ///   - settled: whether the turned layout had stopped changing when it was read.
    ///   - beforeWindow: the window before a turn, when the change is one that must change its shape (a turn). A turn
    ///     that left the window as it was (a portrait-only app, a platform with nothing to turn) tried nothing, so it
    ///     cannot be checked. Nil for a change that may keep the window's size (folding or unfolding).
    public static func compare(turned: [FeelElement], fresh: [FeelElement], turnedWindow: CGRect, freshWindow: CGRect,
                               change: String, waited: Double, settled: Bool = true, beforeWindow: CGRect? = nil) -> FeelResult {
        var findings: [FeelFinding] = []
        let after = "\(FeelIntent.seconds(waited)) s after \(change)"
        if let beforeWindow, sameSize(beforeWindow, turnedWindow) {
            findings.append(.couldNotCheck("the window kept its shape (\(size(turnedWindow))) through \(change), so nothing "
                + "turned and there was no new layout to compare"))
        } else if !sameSize(turnedWindow, freshWindow) {
            findings.append(.couldNotCheck("the window was \(size(turnedWindow)) \(after), but \(size(freshWindow)) on a fresh "
                + "launch, so the launch was not in the same posture and the layouts could not be compared"))
        } else if fresh.isEmpty {
            findings.append(.couldNotCheck("a fresh launch after \(change) showed none of the elements compared, so there was "
                + "no layout to compare with (name them in keys:, or reopen the screen in reopen:)"))
        } else {
            let a = group(turned), b = group(fresh)
            for key in Set(a.keys).union(b.keys).sorted() {
                let mine = a[key] ?? [], theirs = b[key] ?? []
                if theirs.isEmpty {
                    findings.append(FeelFinding(what: "\(mine[0].type) \"\(key)\" is still on screen \(after), but a fresh launch "
                        + "in that posture has none: it lingers from the layout before"))
                } else if mine.isEmpty {
                    findings.append(FeelFinding(what: "\(theirs[0].type) \"\(key)\" is on screen on a fresh launch, but not \(after)"))
                } else if mine.count != theirs.count {
                    findings.append(FeelFinding(what: "\(mine.count) of \"\(key)\" are on screen \(after), and \(theirs.count) on a fresh launch"))
                } else {
                    for (m, t) in zip(mine, theirs) where moved(m.frame, t.frame) {
                        findings.append(FeelFinding(what: "\(m.type) \"\(key)\" is at \(FeelLayout.describe(m.frame)) \(after), "
                            + "but at \(FeelLayout.describe(t.frame)) on a fresh launch"))
                        break
                    }
                }
            }
            if !settled {
                findings.append(.note("the layout was still changing \(after)"))
            }
        }
        return FeelResult.judged(check: FeelCheck.laysOutFresh.name,
                                 passing: "\(after) the \(turned.count) elements compared are where a fresh launch puts them",
                                 failing: { "\($0 == 1 ? "1 element differs" : "\($0) elements differ") from a fresh launch \(after)" },
                                 measures: ["elements": Double(turned.count), "fresh": Double(fresh.count), "seconds": round3(waited)],
                                 findings: findings)
    }

    static func group(_ elements: [FeelElement]) -> [String: [FeelElement]] {
        Dictionary(grouping: elements, by: \.key).mapValues {
            $0.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        }
    }

    static func moved(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) > tolerance || abs(a.minY - b.minY) > tolerance
            || abs(a.width - b.width) > tolerance || abs(a.height - b.height) > tolerance
    }

    static func sameSize(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    static func size(_ r: CGRect) -> String { "\(FeelResult.number(r.width.rounded()))×\(FeelResult.number(r.height.rounded())) pt" }

    /// Several changes as one result: it passes only if every change does.
    public static func combine(_ results: [FeelResult]) -> FeelResult {
        guard results.count > 1 else {
            return results.first ?? compare(turned: [], fresh: [], turnedWindow: .zero, freshWindow: .zero, change: "no change", waited: 0)
        }
        let failed = results.filter { !$0.passed }.count
        return FeelResult.judged(check: FeelCheck.laysOutFresh.name,
                                 passing: "after each of \(results.count) changes the layout matches a fresh launch",
                                 failing: { _ in "the layout differs from a fresh launch after \(failed) of \(results.count) changes" },
                                 measures: ["changes": Double(results.count)],
                                 findings: results.flatMap(\.findings), environment: results.first?.environment)
    }
}

// MARK: Your place survives a turn

/// What was read around one turn, for ``FeelTurnPlace/judge(_:)``: fingerprints of the first words on screen, one per
/// word, never the words.
public struct FeelTurnRead: Codable, Equatable, Sendable {
    /// The turn, in the report's words ("landscape").
    public var turn: String
    /// The words on screen before the turn, in reading order, each as ``FeelTurnPlace/words(_:)`` gives it.
    public var before: [String]
    /// The same, after the turn had settled.
    public var after: [String]
    /// How many words a line holds: the most the place may move and still be within a line.
    public var line: Int
    /// Whether the content was scrolled since the turn before this one.
    public var scrolledFirst: Bool
    /// Whether that scroll moved what was on screen. A scroll that moved nothing leaves the turn after a scroll untried.
    public var scrollMoved: Bool
    /// Whether the window changed shape through the turn. A turn that kept it (a portrait-only app, a platform with
    /// nothing to turn) tried nothing.
    public var shapeChanged: Bool
    /// The words before the turn read from below the status and navigation bars, not from the window's top: an app
    /// that keeps its place at the safe area's top (UIKit's adjusted content inset, a TextKit reader) keeps it there.
    /// Nil when only one reading was taken (the app's own `read:`).
    public var beforeBelowBars: [String]?
    /// The same, after the turn.
    public var afterBelowBars: [String]?

    public init(turn: String, before: [String], after: [String], line: Int, scrolledFirst: Bool = false,
                scrollMoved: Bool = true, shapeChanged: Bool = true, beforeBelowBars: [String]? = nil,
                afterBelowBars: [String]? = nil) {
        self.turn = turn
        self.before = before
        self.after = after
        self.line = line
        self.scrolledFirst = scrolledFirst
        self.scrollMoved = scrollMoved
        self.shapeChanged = shapeChanged
        self.beforeBelowBars = beforeBelowBars
        self.afterBelowBars = afterBelowBars
    }
}

/// Your place survives a turn, under your place is yours: after a turn, the first words on screen are
/// within a line of the first words before it, however you scrolled since the last turn.
///
/// From Gatefold, 2026-11-27 (ourostack/gatefold#650): in scroll mode, rotating after a scroll landed back at the
/// previous rotation's place, a screen and a half earlier. Place stability's `.rotate` compares the whole reading
/// exactly, which a turn's reflow changes; this compares where the reading starts, word by word, so a reflow passes and
/// a lost scroll fails.
public enum FeelTurnPlace {
    /// How many words in a row must agree for two readings to be at the same place.
    public static let run = 4

    /// Each word of `text`, lowercased with its punctuation dropped, as a fingerprint: reports never carry the words.
    public static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).compactMap { word in
            let bare = word.lowercased().filter { $0.isLetter || $0.isNumber }
            return bare.isEmpty ? nil : String(FeelPlace.fingerprint(bare).prefix(8))
        }
    }

    /// The texts read, in reading order, from what is shown of each inside `viewport` (the window, or the scroll view
    /// read): every text more than a point of which shows, so the reading starts at the viewport's top edge in every
    /// orientation, whether or not a status bar is over it, and a paragraph that began above the screen is still the
    /// first thing read.
    public static func reading(_ texts: [(frame: CGRect, text: String)], in viewport: CGRect) -> [String] {
        texts.filter { item in
            let shown = item.frame.intersection(viewport)
            return !shown.isNull && shown.width > FeelCover.tolerance && shown.height > FeelCover.tolerance
        }
        .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        .map(\.text)
    }

    /// The reading from the viewport's top, and the reading from below `bars` (the bottom of the status and navigation
    /// bars, in the viewport's coordinates; at or above its top when there are none), each as ``reading(_:in:)``. An app
    /// keeps its place at one of the two, and which one is the app's.
    public static func readings(_ texts: [(frame: CGRect, text: String)], in viewport: CGRect, below bars: CGFloat)
        -> (fromTop: [String], belowBars: [String]) {
        let top = reading(texts, in: viewport)
        guard bars > viewport.minY, bars < viewport.maxY else { return (top, top) }
        let clear = CGRect(x: viewport.minX, y: bars, width: viewport.width, height: viewport.maxY - bars)
        return (top, reading(texts, in: clear))
    }

    /// How many words the reading moved through the turn: positive when it starts that many words further on, negative
    /// when it starts earlier; nil when neither reading's start is in the other.
    public static func offset(before: [String], after: [String]) -> Int? {
        let k = min(run, before.count, after.count)
        guard k > 0 else { return nil }
        var best: Int?
        func better(_ d: Int) { if best.map({ abs(d) < abs($0) }) ?? true { best = d } }
        let head = Array(after.prefix(k))
        for d in 0...(before.count - k) where Array(before[d..<(d + k)]) == head { better(d); break }
        let start = Array(before.prefix(k))
        if after.count > k { for d in 1...(after.count - k) where Array(after[d..<(d + k)]) == start { better(-d); break } }
        return best
    }

    public static func judge(_ reads: [FeelTurnRead]) -> FeelResult {
        var findings: [FeelFinding] = []
        var moves: [Double] = []
        var judged = 0
        for read in reads {
            let line = max(1, read.line)
            guard read.shapeChanged else {
                findings.append(.couldNotCheck("the window kept its shape through turning to \(read.turn), so nothing turned "
                    + "and the place was not judged"))
                continue
            }
            if read.scrolledFirst && !read.scrollMoved {
                findings.append(.couldNotCheck("the scroll before turning to \(read.turn) moved nothing on screen, so a turn "
                    + "after a scroll was not tried"))
            }
            let scrolled = read.scrolledFirst && read.scrollMoved ? ", after a scroll," : ""
            judged += 1
            guard !read.before.isEmpty, !read.after.isEmpty else {
                findings.append(.couldNotCheck("no words were on screen \(read.before.isEmpty ? "before" : "after") turning to "
                    + "\(read.turn)\(scrolled.isEmpty ? "" : " after a scroll"), so the place was not judged"))
                continue
            }
            var pairs = [(read.before, read.after)]
            if let b = read.beforeBelowBars, let a = read.afterBelowBars {
                pairs += [(b, a), (read.before, a), (b, read.after)]
            }
            let offsets = pairs.compactMap { offset(before: $0.0, after: $0.1) }
            guard let d = offsets.min(by: { abs($0) < abs($1) }) else {
                findings.append(FeelFinding(what: "turning to \(read.turn)\(scrolled) lost the place: the first words after it "
                    + "are nowhere in the \(read.before.count) words on screen before it, nor are those in the \(read.after.count) after"))
                continue
            }
            moves.append(Double(abs(d)))
            if abs(d) > line {
                findings.append(FeelFinding(what: "turning to \(read.turn)\(scrolled) moved the place \(abs(d)) words "
                    + "\(d > 0 ? "on" : "back"), more than a line (\(line) words)"))
            }
        }
        if reads.isEmpty { findings.append(.couldNotCheck("no turns were made")) }
        return FeelResult.judged(check: FeelCheck.placeSurvivesTurns.name,
                                 passing: "the place stayed within a line through \(judged) turns",
                                 failing: { "\($0 == 1 ? "a turn" : "\($0) turns") lost the place" },
                                 measures: ["turns": Double(reads.count), "most words moved": moves.max() ?? 0],
                                 findings: findings)
    }
}
