public import CoreGraphics
public import Foundation

/// One element in one sample.
public struct FeelSeen: Codable, Equatable, Sendable {
    public var key: String
    public var label: String
    public var frame: CGRect

    public init(key: String, label: String = "", frame: CGRect) {
        self.key = key
        self.label = label
        self.frame = frame
    }
}

/// One sample: what was on screen `t` seconds after the film started.
public struct FeelFrame: Codable, Equatable, Sendable {
    public var t: Double
    public var seen: [FeelSeen]

    public init(t: Double, seen: [FeelSeen]) {
        self.t = t
        self.seen = seen
    }
}

/// Samples of the screen over time, and the motion checks that read them.
///
/// In a UI test each sample is one accessibility snapshot, timed by the test runner's clock, so a film sees
/// positions every few tens of milliseconds, not every frame: it catches settling, jumps, double draws and chrome
/// hand-overs, never a single dropped frame (use ``FeelHitches`` for that).
public struct FeelFilm: Codable, Equatable, Sendable {
    public var window: CGRect
    public var frames: [FeelFrame]

    public init(window: CGRect, frames: [FeelFrame]) {
        self.window = window
        self.frames = frames
    }

    /// The film as JSON, to attach beside a report when a motion check needs explaining (frames, not pixels).
    public var json: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    /// Mean time between samples, in seconds.
    public var cadence: Double {
        guard let first = frames.first, let last = frames.last, frames.count > 1 else { return 0 }
        return (last.t - first.t) / Double(frames.count - 1)
    }

    func visible(_ s: FeelSeen) -> Bool {
        s.frame.width > 0 && s.frame.height > 0 && s.frame.intersects(window)
    }

    func find(_ key: String, in frame: FeelFrame) -> FeelSeen? {
        frame.seen.first { ($0.key == key || $0.label == key) && visible($0) }
    }

    /// The element's frame in each sample where it is on screen.
    public func track(_ key: String) -> [(t: Double, frame: CGRect)] {
        frames.compactMap { f in find(key, in: f).map { (f.t, $0.frame) } }
    }

    static func distance(_ a: CGRect, _ b: CGRect) -> Double {
        Double(max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.width - b.width), abs(a.height - b.height)))
    }

    /// The median time between samples: what the film's sampling usually managed, unlike `cadence` (the mean), which
    /// one long stall can drag up.
    public var typicalGap: Double {
        let gaps = zip(frames, frames.dropFirst()).map { $1.t - $0.t }.sorted()
        return gaps.isEmpty ? .infinity : gaps[gaps.count / 2]
    }

    static func times(_ n: Int) -> String { n == 1 ? "1 time" : "\(n) times" }

    func unseen(_ key: String) -> FeelFinding? {
        track(key).isEmpty ? .couldNotCheck("\"\(key)\" was never on screen in \(frames.count) samples") : nil
    }

    func tooSparse(_ maxGap: Double) -> FeelFinding? {
        if typicalGap <= maxGap { return nil }
        if !typicalGap.isFinite { return .couldNotCheck("the film had fewer than two samples; film for longer") }
        return .couldNotCheck("samples were usually \(FeelResult.number(round3(typicalGap))) s apart, too far apart to judge "
            + "(at most \(FeelResult.number(maxGap)) s); watch fewer elements, or rerun on a less busy machine")
    }

    // MARK: Settle

    /// Seconds from the film's start until the element reached the place it then kept to the end, within
    /// `tolerance` points; nil if it never appeared.
    public func settleTime(of key: String, tolerance: Double = 0.5) -> Double? {
        let track = track(key)
        guard let last = track.last else { return nil }
        var settled = last.t
        for sample in track.reversed() {
            if Self.distance(sample.frame, last.frame) > tolerance { break }
            settled = sample.t
        }
        return settled
    }

    /// When the element first moved (or appeared after the film began): the time of the last sample before it.
    public func motionStart(of key: String, tolerance: Double = 0.5) -> Double? {
        let track = track(key)
        guard let first = track.first else { return nil }
        if let firstFrame = frames.first, first.t > firstFrame.t {
            return frames.last { $0.t < first.t }?.t ?? first.t
        }
        for (a, b) in zip(track, track.dropFirst()) where Self.distance(a.frame, first.frame) <= tolerance && Self.distance(b.frame, first.frame) > tolerance {
            return a.t
        }
        return nil
    }

    /// Passes when the element comes to rest within `limit` seconds of starting to move and stays still for `hold`
    /// seconds before the film ends. It fails, saying why, when the element never appeared, was never seen moving (a
    /// film started by a tap begins after XCUITest's idle wait, when the motion is over), was still moving when the film
    /// ended, or when samples are usually more than `maxGap` apart.
    public func settles(_ key: String, within limit: Double, hold: Double = 0.3, maxGap: Double = 0.15, tolerance: Double = 0.5) -> FeelResult {
        let check = FeelGenre.settleTime.rawValue
        guard let end = settleTime(of: key, tolerance: tolerance), let last = track(key).last else {
            return FeelResult(check: check, passed: false, summary: "could not check: \"\(key)\" was never on screen",
                              findings: [.couldNotCheck("\"\(key)\" was not on screen in any of \(frames.count) samples")])
        }
        guard let start = motionStart(of: key, tolerance: tolerance) else {
            return FeelResult(check: check, passed: false, summary: "could not check: \"\(key)\" was never seen moving",
                              findings: [.couldNotCheck("\"\(key)\" was never seen moving, so its settling was not timed; "
                                + "let the app start the motion after the film begins (a tap's motion is over before the first sample)")])
        }
        let t = round3(max(0, end - start))
        if last.t - end < hold {
            return FeelResult(check: check, passed: false, summary: "could not check: \"\(key)\" had not settled when the film ended",
                              measures: ["moving": t, "cadence": round3(cadence)],
                              findings: [.couldNotCheck("\"\(key)\" was still moving when the film ended (still for under \(FeelResult.number(hold)) s); film for longer")])
        }
        if let sparse = tooSparse(maxGap) {
            return FeelResult(check: FeelGenre.settleTime.rawValue, passed: false, summary: "could not check: " + sparse.what,
                              measures: ["settle": t, "cadence": round3(cadence), "typicalGap": round3(typicalGap)], findings: [sparse])
        }
        let ok = t <= limit
        return FeelResult(check: FeelGenre.settleTime.rawValue, passed: ok,
                          summary: "\"\(key)\" came to rest \(FeelResult.number(t)) s after it started moving (limit \(FeelResult.number(limit)) s)",
                          measures: ["settle": t, "cadence": round3(cadence)],
                          findings: ok ? [] : [FeelFinding(what: "\"\(key)\" was still moving \(FeelResult.number(t)) s after it started")])
    }

    // MARK: Jumps

    /// A jump is the element moving more than `limit` points after it had landed: after its first move, then `rest`
    /// seconds still. Its first move from rest is the transition itself, so start the film before the transition.
    public func jumps(of key: String, rest: Double = 0.3, limit: Double = 2, tolerance: Double = 0.5) -> FeelResult {
        let track = track(key)
        var findings: [FeelFinding] = unseen(key).map { [$0] } ?? []
        var stillSince = track.first?.t ?? 0
        var landed = false
        for (previous, sample) in zip(track, track.dropFirst()) {
            let moved = Self.distance(previous.frame, sample.frame)
            if moved <= tolerance { continue }
            defer { landed = true }
            if landed && moved > limit && previous.t - stillSince >= rest {
                findings.append(FeelFinding(what: "\"\(key)\" jumped \(FeelResult.number(round3(moved))) pt at \(FeelResult.number(round3(sample.t))) s, "
                    + "after \(FeelResult.number(round3(previous.t - stillSince))) s at rest"))
            }
            stillSince = sample.t
        }
        return FeelResult.judged(check: FeelGenre.jumpAfterLanding.rawValue, passing: "\"\(key)\" never moved once at rest",
                                 failing: { "\"\(key)\" jumped \(Self.times($0)) after coming to rest" },
                                 measures: ["jumps": Double(findings.filter { !$0.unchecked }.count), "samples": Double(track.count), "cadence": round3(cadence)],
                                 findings: findings)
    }

    // MARK: Double draws

    /// The same content on screen twice at once: two visible elements with the same label or key whose frames do not
    /// mostly overlap (a button and its own text overlap, so they never count).
    public func doubleDraws(of contents: [String]) -> FeelResult {
        var findings: [FeelFinding] = []
        var total = 0
        if contents.isEmpty { findings.append(.couldNotCheck("no contents were named")) }
        for content in contents {
            if let unseen = unseen(content) { findings.append(unseen); continue }
            var hits: [Double] = []
            for f in frames {
                let copies = f.seen.filter { ($0.label == content || $0.key == content) && visible($0) }
                if Self.apart(copies) { hits.append(f.t) }
            }
            total += hits.count
            if let first = hits.first {
                findings.append(FeelFinding(what: "\"\(content)\" was on screen twice at once in \(hits.count) samples, first at \(FeelResult.number(round3(first))) s"))
            }
        }
        return FeelResult.judged(check: FeelGenre.doubleDraw.rawValue, passing: "no content drawn twice in \(frames.count) samples",
                          failing: { "\($0) of \(contents.count) contents drawn twice" },
                          measures: ["samples": Double(frames.count), "doubled": Double(total)], findings: findings)
    }

    static func apart(_ copies: [FeelSeen]) -> Bool {
        for (i, a) in copies.enumerated() {
            for b in copies.dropFirst(i + 1) {
                let overlap = a.frame.intersection(b.frame)
                let smaller = min(a.frame.width * a.frame.height, b.frame.width * b.frame.height)
                let shared = overlap.isNull ? 0 : overlap.width * overlap.height
                if smaller > 0 && shared < smaller * 0.5 { return true }
            }
        }
        return false
    }

    // MARK: Snaps

    /// A snap is a move of more than `distance` points between two samples with the element still, and at its resting
    /// size, on both sides, so no in-between position was ever on screen. With `appearing`, arriving in full between two samples counts too.
    /// The samples must be at most `maxGap` seconds apart around such a move, or the check cannot tell a snap from a
    /// quick transition. XCUITest's snapshot waits while the app animates, so when sampling is otherwise quick (the
    /// median gap within `maxGap`) a move inside a gap at least three times the median was not seen, and the check fails
    /// saying so; so does sampling usually slower than `maxGap`, moves seen or not, and a film in which the element
    /// never moved more than `distance` (or, with `appearing`, never arrived). It never passes on what it did not see.
    public func snaps(of key: String, distance: Double = 40, appearing: Bool = false, maxGap: Double = 0.15, tolerance: Double = 0.5) -> FeelResult {
        let places: [CGRect?] = frames.map { find(key, in: $0)?.frame }
        func moved(_ i: Int) -> Double? {
            guard i >= 0, i + 1 < places.count, let a = places[i], let b = places[i + 1] else { return nil }
            return Self.distance(a, b)
        }
        // Its resting size: the size it shows most. Mid-animation SwiftUI stretches the accessibility frame from where
        // the element is drawn to where it is going, so a sample at another size is an in-between position.
        let sizes = places.compactMap { $0.map { "\(Int(($0.width).rounded()))x\(Int(($0.height).rounded()))" } }
        let restingSize = Dictionary(sizes.map { ($0, 1) }, uniquingKeysWith: +).max { $0.value < $1.value }?.key
        func atRest(_ i: Int) -> Bool {
            guard let r = places[i] else { return false }
            return "\(Int(r.width.rounded()))x\(Int(r.height.rounded()))" == restingSize
        }
        var findings: [FeelFinding] = []
        for i in 0..<max(0, frames.count - 1) {
            let gap = frames[i + 1].t - frames[i].t
            let quietBefore = (moved(i - 1) ?? 0) <= tolerance
            let quietAfter = (moved(i + 1) ?? 0) <= tolerance
            var what: String?
            if let m = moved(i), m > distance, quietBefore, quietAfter, atRest(i), atRest(i + 1) {
                what = "\"\(key)\" moved \(FeelResult.number(round3(m))) pt between \(FeelResult.number(round3(frames[i].t))) s and \(FeelResult.number(round3(frames[i + 1].t))) s with nothing in between"
            } else if appearing, places[i] == nil, places[i + 1] != nil, quietAfter, i + 2 < places.count {
                what = "\"\(key)\" appeared in full at \(FeelResult.number(round3(frames[i + 1].t))) s with no transition"
            }
            guard let what else { continue }
            if gap <= maxGap {
                findings.append(FeelFinding(what: what))
            } else if typicalGap <= maxGap && gap >= typicalGap * 3 {
                // Sampling was quick except around this move: the app was busy, which a transition and a snap with heavy
                // layout both cause, so the move cannot be judged.
                findings.append(.couldNotCheck("the app was busy for \(FeelResult.number(round3(gap))) s while \"\(key)\" moved "
                    + "\(FeelResult.number(round3(moved(i) ?? 0))) pt, so whether it travelled or snapped was not seen; rerun, or slow the motion"))
            } else {
                findings.append(.couldNotCheck("samples \(FeelResult.number(round3(gap))) s apart are too far apart to tell a snap from a transition (\(what)); watch fewer elements"))
            }
        }
        if let sparse = tooSparse(maxGap) { findings.insert(sparse, at: 0) }
        let seen = places.compactMap { $0 }
        let arrived = appearing && places.contains { $0 == nil } && !seen.isEmpty
        if let first = seen.first, !arrived, !seen.contains(where: { Self.distance(first, $0) > distance }) {
            findings.insert(.couldNotCheck("\"\(key)\" never moved more than \(FeelResult.number(distance)) pt in the film, so no snap could be "
                + "seen; start the film before the motion"), at: 0)
        }
        if let unseen = unseen(key) { findings.insert(unseen, at: 0) }
        return FeelResult.judged(check: FeelGenre.snap.rawValue, passing: "\"\(key)\" travelled wherever it moved",
                                 failing: { "\"\(key)\" snapped \(Self.times($0))" },
                                 measures: ["snaps": Double(findings.filter { !$0.unchecked }.count), "cadence": round3(cadence)], findings: findings)
    }

    // MARK: Chrome

    /// A hand-over from one chrome state to another (a full bar to a compact one, a toolbar to its edit mode): it
    /// fails when both are on screen together, or neither is, for longer than `grace` seconds (a short crossfade is fine), counted from the first
    /// sample that shows either.
    public func chrome(from a: String, to b: String, grace: Double = 0.25) -> FeelResult {
        var both = 0.0, neither = 0.0, longestBoth = 0.0, longestNeither = 0.0, runBoth = 0.0, runNeither = 0.0
        var started = false
        for (f, next) in zip(frames, frames.dropFirst()) {
            let hasA = find(a, in: f) != nil, hasB = find(b, in: f) != nil
            if hasA || hasB { started = true }
            guard started else { continue }
            let span = next.t - f.t
            if hasA && hasB { both += span; runBoth += span } else { runBoth = 0 }
            if !hasA && !hasB { neither += span; runNeither += span } else { runNeither = 0 }
            longestBoth = max(longestBoth, runBoth)
            longestNeither = max(longestNeither, runNeither)
        }
        var findings: [FeelFinding] = []
        if !started {
            findings.append(.couldNotCheck("neither \"\(a)\" nor \"\(b)\" was ever on screen in \(frames.count) samples"))
        }
        if longestBoth > grace {
            findings.append(FeelFinding(what: "both \"\(a)\" and \"\(b)\" were on screen for \(FeelResult.number(round3(longestBoth))) s (lingering chrome)"))
        }
        if longestNeither > grace {
            findings.append(FeelFinding(what: "neither \"\(a)\" nor \"\(b)\" was on screen for \(FeelResult.number(round3(longestNeither))) s (late chrome)"))
        }
        return FeelResult.judged(check: FeelGenre.chrome.rawValue, passing: "\"\(a)\" handed over to \"\(b)\" cleanly",
                          failing: { _ in "\"\(a)\" to \"\(b)\" overlapped or left a gap" },
                          measures: ["both": round3(both), "neither": round3(neither), "cadence": round3(cadence)], findings: findings)
    }
}
