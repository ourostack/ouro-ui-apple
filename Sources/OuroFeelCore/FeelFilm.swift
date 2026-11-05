public import CoreGraphics

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

    /// Passes when the element settles within `limit` seconds of the film's start.
    public func settles(_ key: String, within limit: Double, tolerance: Double = 0.5) -> FeelResult {
        guard let t = settleTime(of: key, tolerance: tolerance) else {
            return FeelResult(check: FeelGenre.settleTime.rawValue, passed: false, summary: "\"\(key)\" never appeared",
                              findings: [FeelFinding(what: "\"\(key)\" was not on screen in any of \(frames.count) samples")])
        }
        let ok = t <= limit
        return FeelResult(check: FeelGenre.settleTime.rawValue, passed: ok, summary: "\"\(key)\" settled at \(FeelResult.number(round3(t))) s (limit \(FeelResult.number(limit)) s)",
                          measures: ["settle": round3(t), "cadence": round3(cadence)],
                          findings: ok ? [] : [FeelFinding(what: "\"\(key)\" was still moving \(FeelResult.number(round3(t))) s in")])
    }

    // MARK: Jumps

    /// A jump is the element moving more than `limit` points after it had been still for `rest` seconds.
    public func jumps(of key: String, rest: Double = 0.3, limit: Double = 2, tolerance: Double = 0.5) -> FeelResult {
        let track = track(key)
        var findings: [FeelFinding] = []
        var stillSince = track.first?.t ?? 0
        for (previous, sample) in zip(track, track.dropFirst()) {
            let moved = Self.distance(previous.frame, sample.frame)
            if moved <= tolerance { continue }
            if moved > limit && previous.t - stillSince >= rest {
                findings.append(FeelFinding(what: "\"\(key)\" jumped \(FeelResult.number(round3(moved))) pt at \(FeelResult.number(round3(sample.t))) s, "
                    + "after \(FeelResult.number(round3(previous.t - stillSince))) s at rest"))
            }
            stillSince = sample.t
        }
        return FeelResult(check: FeelGenre.jumpAfterLanding.rawValue, passed: findings.isEmpty,
                          summary: findings.isEmpty ? "\"\(key)\" never moved once at rest" : "\"\(key)\" jumped \(findings.count) times after coming to rest",
                          measures: ["jumps": Double(findings.count), "samples": Double(track.count), "cadence": round3(cadence)], findings: findings)
    }

    // MARK: Double draws

    /// The same content on screen twice at once: two visible elements with the same label or key whose frames do not
    /// mostly overlap (a button and its own text overlap, so they never count).
    public func doubleDraws(of contents: [String]) -> FeelResult {
        var findings: [FeelFinding] = []
        var total = 0
        for content in contents {
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
        return FeelResult(check: FeelGenre.doubleDraw.rawValue, passed: findings.isEmpty,
                          summary: findings.isEmpty ? "no content drawn twice in \(frames.count) samples" : "\(findings.count) contents drawn twice",
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

    /// A snap is a move of more than `distance` points between two samples with the element still on both sides, so
    /// no in-between position was ever on screen. With `appearing`, arriving in full between two samples counts too.
    /// The samples must be at most `maxGap` seconds apart around such a move, or the check cannot tell a snap from a
    /// quick transition and fails saying so.
    public func snaps(of key: String, distance: Double = 40, appearing: Bool = false, maxGap: Double = 0.1, tolerance: Double = 0.5) -> FeelResult {
        let places: [CGRect?] = frames.map { find(key, in: $0)?.frame }
        func moved(_ i: Int) -> Double? {
            guard i >= 0, i + 1 < places.count, let a = places[i], let b = places[i + 1] else { return nil }
            return Self.distance(a, b)
        }
        var findings: [FeelFinding] = []
        for i in 0..<max(0, frames.count - 1) {
            let gap = frames[i + 1].t - frames[i].t
            let quietBefore = (moved(i - 1) ?? 0) <= tolerance
            let quietAfter = (moved(i + 1) ?? 0) <= tolerance
            var what: String?
            if let m = moved(i), m > distance, quietBefore, quietAfter {
                what = "\"\(key)\" moved \(FeelResult.number(round3(m))) pt between \(FeelResult.number(round3(frames[i].t))) s and \(FeelResult.number(round3(frames[i + 1].t))) s with nothing in between"
            } else if appearing, places[i] == nil, places[i + 1] != nil, quietAfter, i + 2 < places.count {
                what = "\"\(key)\" appeared in full at \(FeelResult.number(round3(frames[i + 1].t))) s with no transition"
            }
            guard let what else { continue }
            findings.append(FeelFinding(what: gap > maxGap
                ? "samples \(FeelResult.number(round3(gap))) s apart are too far apart to tell a snap from a transition (\(what)); watch fewer elements"
                : what))
        }
        return FeelResult(check: FeelGenre.snap.rawValue, passed: findings.isEmpty,
                          summary: findings.isEmpty ? "\"\(key)\" travelled wherever it moved" : "\"\(key)\" snapped \(findings.count) times",
                          measures: ["snaps": Double(findings.count), "cadence": round3(cadence)], findings: findings)
    }

    // MARK: Chrome

    /// A hand-over from one chrome state to another (a full bar to a compact one, a toolbar to its edit mode): it
    /// fails when both are on screen together, or neither is, for longer than `grace` seconds, counted from the first
    /// sample that shows either.
    public func chrome(from a: String, to b: String, grace: Double = 0.1) -> FeelResult {
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
        if longestBoth > grace {
            findings.append(FeelFinding(what: "both \"\(a)\" and \"\(b)\" were on screen for \(FeelResult.number(round3(longestBoth))) s (lingering chrome)"))
        }
        if longestNeither > grace {
            findings.append(FeelFinding(what: "neither \"\(a)\" nor \"\(b)\" was on screen for \(FeelResult.number(round3(longestNeither))) s (late chrome)"))
        }
        return FeelResult(check: FeelGenre.chrome.rawValue, passed: findings.isEmpty,
                          summary: findings.isEmpty ? "\"\(a)\" handed over to \"\(b)\" cleanly" : "\"\(a)\" to \"\(b)\" overlapped or left a gap",
                          measures: ["both": round3(both), "neither": round3(neither), "cadence": round3(cadence)], findings: findings)
    }
}
