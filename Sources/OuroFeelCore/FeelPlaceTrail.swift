public import Foundation

/// A session's place, read after every action: what happened, in order, and the place's fingerprint
/// (``FeelPlace/fingerprint(_:)``) at each read. Two checks judge it, in reads and actions, never in seconds:
///
/// - ``strayInput()``: a stray tap, an edge swipe that goes nowhere, dismissing a sheet, backgrounding, or no input at
///   all while a late reply arrives: an action that is not a move must leave the place where it was.
/// - ``fights(hold:)``: after your own move, the place lands where you chose (when the trail says where) and stays; no
///   late restore, re-sent jump, sync landing or input queued while a jump was under way moves it again.
///
/// It holds fingerprints only, never the text, so a trail can be attached to a report without the book in it.
public struct FeelPlaceTrail: Codable, Equatable, Sendable {
    public enum Event: Codable, Equatable, Sendable {
        /// Something done to the app. `deliberate` marks a move meant to change the place (a page turn, a jump to a
        /// chapter); everything else (a stray tap, a sheet dismissed, a trip to the Home Screen) must keep it.
        case action(String, deliberate: Bool)
        /// The fingerprint of the place the last move must land at (a chapter picked from Contents).
        case chose(String)
        /// The last action did not happen as described (a sheet that never opened or never closed), so it cannot be
        /// judged.
        case unchecked(String)
        /// The place's fingerprint at one read.
        case read(String)
    }

    public var events: [Event]

    public init(_ events: [Event] = []) { self.events = events }

    public mutating func act(_ name: String, deliberate: Bool) { events.append(.action(name, deliberate: deliberate)) }
    public mutating func read(_ fingerprint: String) { events.append(.read(fingerprint)) }
    public mutating func chose(_ fingerprint: String) { events.append(.chose(fingerprint)) }
    public mutating func unchecked(_ why: String) { events.append(.unchecked(why)) }

    /// One action and the reads up to the next action, with the place before it (the last non-empty read).
    struct Span {
        var name: String
        var deliberate: Bool
        var before: String?
        var reads: [String]
        var chose: String?
        var unchecked: String?
    }

    var spans: [Span] {
        var out: [Span] = []
        var last: String?
        for event in events {
            switch event {
            case let .action(name, deliberate):
                out.append(Span(name: name, deliberate: deliberate, before: last, reads: []))
            case let .chose(place):
                if !out.isEmpty { out[out.count - 1].chose = place }
            case let .unchecked(why):
                if !out.isEmpty { out[out.count - 1].unchecked = why }
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
    /// be checked. A late move that lands while a stray action's reads are taken is blamed on that action: the place
    /// moved with no move of yours either way, so start a stray step only once the last move has held.
    public func strayInput() -> FeelResult {
        var findings: [FeelFinding] = []
        let stray = spans.filter { !$0.deliberate }
        if stray.isEmpty { findings.append(.couldNotCheck("the trail had no action that should keep the place")) }
        var kept = 0
        for span in stray {
            let reads = span.reads.filter { $0 != FeelPlace.empty }
            if let why = span.unchecked { findings.append(.couldNotCheck("\(span.name): \(why)")); continue }
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

    /// Passes when, after every move you made, the place landed and then held for the rest of the reads before your next
    /// action. The landing is the first place two reads in a row agree on once the place left where you were, so a page
    /// that shows a place for one read on its way is fine. It fails when:
    ///
    /// - the place goes back to where you were, even for one read (a late restore);
    /// - it moves on after landing (a re-sent jump, a sync landing);
    /// - it lands somewhere other than where you chose, when the trail says (``Event/chose(_:)``): an input queued while
    ///   a jump was under way and applied as it landed.
    ///
    /// Reads of an empty place (still loading) are skipped, so read the place with something that names it and is
    /// empty while a placeholder shows. The landing must be read at least `hold` times (the two that agree count; at
    /// least 2), or the move could not be checked.
    public func fights(hold: Int = 3) -> FeelResult {
        let hold = max(2, hold)
        var findings: [FeelFinding] = []
        let moves = spans.filter(\.deliberate)
        if moves.isEmpty { findings.append(.couldNotCheck("the trail had no move of yours")) }
        var held = 0
        for span in moves {
            let reads = span.reads.filter { $0 != FeelPlace.empty }
            if let why = span.unchecked { findings.append(.couldNotCheck("\(span.name): \(why)")); continue }
            guard let before = span.before else {
                findings.append(.couldNotCheck("no place was read before \(span.name)")); continue
            }
            let runs = FeelFilm.runs(reads)
            var i = 0
            while i < runs.count, runs[i].value == before { i += 1 }
            if i == runs.count {
                // It never left `before`: a move that went nowhere is no fight, if it was read long enough to know.
                if let chose = span.chose, chose != before {
                    findings.append(FeelFinding(what: "\(span.name) never left \(before) for where you chose (\(chose)) in \(reads.count) reads"))
                } else if reads.count < hold {
                    findings.append(.couldNotCheck("the place was read only \(reads.count) times after \(span.name) (at least \(hold) needed); read for longer"))
                } else {
                    findings.append(.note("\(span.name) did not move the place"))
                    held += 1
                }
                continue
            }
            // Once it left, any read back at `before` is a restore, however short.
            if let back = runs[i...].first(where: { $0.value == before }) {
                findings.append(FeelFinding(what: "after \(span.name) the place went to \(runs[i].value), then moved back to where you were (a late restore) at read \(back.start + 1) of \(reads.count) with no input"))
                continue
            }
            while i < runs.count, runs[i].count < 2 { i += 1 }
            guard i < runs.count else {
                findings.append(.couldNotCheck("after \(span.name) the place never held for two reads in a row (\(reads.count) reads); read for longer"))
                continue
            }
            let landing = runs[i]
            if let chose = span.chose, landing.value != chose {
                findings.append(FeelFinding(what: "\(span.name) landed at \(landing.value), not where you chose (\(chose)), at read \(landing.start + 1) of \(reads.count)"))
            } else if i + 1 < runs.count {
                let fight = runs[i + 1]
                findings.append(FeelFinding(what: "after \(span.name) the place landed at \(landing.value), then moved on to \(fight.value) (a re-sent or late jump) at read \(fight.start + 1) of \(reads.count) with no input"))
            } else if landing.count < hold {
                findings.append(.couldNotCheck("after \(span.name) the place was read only \(landing.count) times at its landing (at least \(hold) needed); read for longer"))
            } else {
                held += 1
            }
        }
        let summary = "\(held) of \(moves.count) moves stayed where they landed"
        return FeelResult.judged(check: FeelGenre.navigationFight.rawValue, passing: summary, failing: { _ in summary },
                                 measures: ["moves": Double(moves.count), "held": Double(held)], findings: findings)
    }
}
