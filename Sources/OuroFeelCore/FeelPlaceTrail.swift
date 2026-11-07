public import Foundation

/// A session's place, read after every action: what happened, in order, and the place's fingerprint
/// (``FeelPlace/fingerprint(_:)``) at each read. Two checks judge it, in reads and actions, never in seconds:
///
/// - ``strayInput()``: a stray tap, an edge swipe that goes nowhere, dismissing a sheet, backgrounding: an action that
///   is not a move must leave the place where it was.
/// - ``fights(hold:)``: after your own move, the place lands once and stays; no late restore, re-sent jump or sync
///   landing moves it again.
///
/// It holds fingerprints only, never the text, so a trail can be attached to a report without the book in it.
public struct FeelPlaceTrail: Codable, Equatable, Sendable {
    public enum Event: Codable, Equatable, Sendable {
        /// Something done to the app. `deliberate` marks a move meant to change the place (a page turn, a jump to a
        /// chapter); everything else (a stray tap, a sheet dismissed, a trip to the Home Screen) must keep it.
        case action(String, deliberate: Bool)
        /// The place's fingerprint at one read.
        case read(String)
    }

    public var events: [Event]

    public init(_ events: [Event] = []) { self.events = events }

    public mutating func act(_ name: String, deliberate: Bool) { events.append(.action(name, deliberate: deliberate)) }
    public mutating func read(_ fingerprint: String) { events.append(.read(fingerprint)) }

    /// One action and the reads up to the next action, with the place before it (the last non-empty read).
    struct Span {
        var name: String
        var deliberate: Bool
        var before: String?
        var reads: [String]
    }

    var spans: [Span] {
        var out: [Span] = []
        var last: String?
        for event in events {
            switch event {
            case let .action(name, deliberate):
                out.append(Span(name: name, deliberate: deliberate, before: last, reads: []))
            case let .read(place):
                if !out.isEmpty { out[out.count - 1].reads.append(place) }
                if place != FeelPlace.empty { last = place }
            }
        }
        return out
    }

    // MARK: Stray input

    /// Passes when every action that is not a move left the place where it was, at every read after it. An empty read
    /// (the screen still loading) is skipped; an action with no reads after it, or with no place before it, could not
    /// be checked.
    public func strayInput() -> FeelResult {
        var findings: [FeelFinding] = []
        let stray = spans.filter { !$0.deliberate }
        if stray.isEmpty { findings.append(.couldNotCheck("the trail had no action that should keep the place")) }
        var kept = 0
        for span in stray {
            let reads = span.reads.filter { $0 != FeelPlace.empty }
            guard let before = span.before else {
                findings.append(.couldNotCheck("no place was read before \(span.name)")); continue
            }
            guard !reads.isEmpty else {
                findings.append(.couldNotCheck("the place was never read after \(span.name)")); continue
            }
            if let moved = reads.firstIndex(where: { $0 != before }) {
                let back = reads[(moved + 1)...].contains(before)
                findings.append(FeelFinding(what: "\(span.name) moved the place (\(before) to \(reads[moved]), read \(moved + 1) of \(reads.count) after it)"
                    + (back ? ", and it later came back" : "")))
            } else {
                kept += 1
            }
        }
        let summary = "\(kept) of \(stray.count) stray actions kept the place"
        return FeelResult.judged(check: FeelGenre.strayInput.rawValue, passing: summary, failing: { _ in summary },
                                 measures: ["actions": Double(stray.count), "kept": Double(kept)], findings: findings)
    }

    // MARK: Fights

    /// Passes when, after every move you made, the place landed (the first place two reads in a row agree on, once it
    /// left where you were) and then held for the rest of the reads before your next action. A second change is a fight: back to where you were is a late restore pulling
    /// you back; anywhere else is a re-sent jump or a sync landing moving you on. After the place lands it must be read
    /// at least `hold` more times, or that move could not be checked (read for longer).
    public func fights(hold: Int = 3) -> FeelResult {
        var findings: [FeelFinding] = []
        let moves = spans.filter(\.deliberate)
        if moves.isEmpty { findings.append(.couldNotCheck("the trail had no move of yours")) }
        var held = 0
        for span in moves {
            let reads = span.reads.filter { $0 != FeelPlace.empty }
            guard let before = span.before else {
                findings.append(.couldNotCheck("no place was read before \(span.name)")); continue
            }
            // The landing is the first place two reads in a row agree on, once the place has left `before`: a page
            // that lands across two reads mid-animation shows a place for one read on its way. Any change after the
            // landing is a fight; so is landing back at `before` after the place was seen elsewhere (a late restore
            // that came before the move had held for two reads).
            let runs = FeelFilm.runs(reads)
            var i = 0
            while i < runs.count, runs[i].value == before { i += 1 }
            let left = i < runs.count
            while i < runs.count, runs[i].count < 2 { i += 1 }
            if !left {
                // It never left `before`: a move that went nowhere is no fight, if it was read long enough to know.
                if reads.count < hold {
                    findings.append(.couldNotCheck("the place was read only \(reads.count) times after \(span.name) (at least \(hold) needed); read for longer"))
                } else {
                    findings.append(.note("\(span.name) did not move the place"))
                    held += 1
                }
                continue
            }
            if i < runs.count, runs[i].value == before {
                let away = runs.first { $0.value != before }!
                findings.append(FeelFinding(what: "after \(span.name) the place went to \(away.value), then moved back to where you were (a late restore) at read \(runs[i].start + 1) of \(reads.count) with no input"))
                continue
            }
            guard i < runs.count else {
                findings.append(.couldNotCheck("after \(span.name) the place never held for two reads in a row (\(reads.count) reads); read for longer"))
                continue
            }
            let landing = runs[i]
            if i + 1 < runs.count {
                let fight = runs[i + 1]
                let to = fight.value == before ? "back to where you were (a late restore)" : "on to \(fight.value) (a re-sent or late jump)"
                findings.append(FeelFinding(what: "after \(span.name) the place landed at \(landing.value), then moved \(to) at read \(fight.start + 1) of \(reads.count) with no input"))
            } else if landing.count < hold {
                findings.append(.couldNotCheck("after \(span.name) the place was read only \(landing.count) times once it landed (at least \(hold) needed); read for longer"))
            } else {
                held += 1
            }
        }
        let summary = "\(held) of \(moves.count) moves stayed where they landed"
        return FeelResult.judged(check: FeelGenre.navigationFight.rawValue, passing: summary, failing: { _ in summary },
                                 measures: ["moves": Double(moves.count), "held": Double(held)], findings: findings)
    }
}
