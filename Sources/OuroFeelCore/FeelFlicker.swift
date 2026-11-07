public import CoreGraphics
public import Foundation

// MARK: Flicker

extension FeelFilm {
    /// Flicker: something that flips back and forth, or keeps changing, before it settles. For each element in `keys` it
    /// reads three things sample by sample, and judges them in samples, never in seconds:
    ///
    /// - **Shown, hidden, shown** (or hidden, shown, hidden): it disappears and comes back, or blinks in and out, with
    ///   the middle run at most `within` samples long.
    /// - **Its words**: a label that goes A, B, A (taken back) within `within` samples, or changes more than `changes`
    ///   times within any `within` samples (Gatefold build 20's page spazzing through several pages before it settled).
    /// - **Its place**: it rests somewhere (the same frame, within `tolerance` points, for two samples or more), leaves by
    ///   more than `distance` points (seen in at least one sample, so a dropped frame is never an excursion) and rests at
    ///   that same place again within `within` samples. A spring that overshoots never rests on its way, so it is not a
    ///   flicker.
    ///
    /// One move, one change of words, or appearing once are what good looks like. It cannot be checked, and fails saying
    /// so, when the film stalled, when an element was never on screen, when an element was still changing in the film's
    /// last `hold` samples (film for longer), or when nothing flickered but samples were once more than `maxGap` seconds
    /// apart (a blink shorter than that could be missed). A film recorded in the app (``OuroFeel/recordedFilm``) samples
    /// every frame, and one on the app's own clock samples every tick; a wall-clock film on a busy runner rarely passes.
    public func flickers(of keys: [String], within: Int = 30, changes: Int = 1, distance: Double = 2, hold: Int = 3,
                         maxGap: Double = 0.15, tolerance: Double = 0.5) -> FeelResult {
        timed(flickersUntimed(of: keys, within: max(1, within), changes: max(0, changes), distance: distance,
                              hold: max(1, hold), maxGap: maxGap, tolerance: tolerance))
    }

    private func flickersUntimed(of keys: [String], within: Int, changes: Int, distance: Double, hold: Int, maxGap: Double,
                                 tolerance: Double) -> FeelResult {
        var findings: [FeelFinding] = stall().map { [$0] } ?? []
        if keys.isEmpty { findings.append(.couldNotCheck("no elements were named")) }
        var flips = 0
        for key in keys {
            if let unseen = unseen(key) { findings.append(unseen); continue }
            let seen: [FeelSeen?] = frames.map { find(key, in: $0) }
            var found: [FeelFinding] = []
            found += Self.blinks(key, seen.map { $0 != nil }, times: frames.map(\.t), within: within)
            found += Self.wordFlips(key, seen, times: frames.map(\.t), within: within, changes: changes)
            found += Self.placeFlips(key, seen, times: frames.map(\.t), within: within, distance: distance, tolerance: tolerance)
            flips += found.count
            findings += found
            if found.isEmpty, let last = seen.last, seen.count >= hold {
                let tail = seen.suffix(hold)
                let still = tail.allSatisfy { s in
                    (s == nil) == (last == nil)
                        && (s.map { a in last.map { b in a.label == b.label && Self.distance(a.frame, b.frame) <= tolerance } ?? false } ?? true)
                }
                if !still {
                    findings.append(.couldNotCheck("\"\(key)\" was still changing in the film's last \(hold) samples, so whether it settled was not seen; film for longer"))
                }
            } else if found.isEmpty {
                findings.append(.couldNotCheck("the film had \(seen.count) samples, fewer than the \(hold) needed to see \"\(key)\" settle"))
            }
        }
        if flips == 0, let (at, gap) = widestGap, gap > maxGap {
            findings.append(.couldNotCheck("nothing flickered, but samples were once \(FeelResult.number(round3(gap))) s apart (from \(FeelResult.number(round3(at))) s), so a flicker shorter than that could be missed (a pass needs samples at most \(FeelResult.number(maxGap)) s apart; record the film in the app)"))
        }
        return FeelResult.judged(check: FeelGenre.flicker.rawValue, passing: "nothing flickered in \(frames.count) samples",
                                 failing: { "\($0) \($0 == 1 ? "flicker" : "flickers") in \(frames.count) samples" },
                                 measures: ["flickers": Double(flips), "samples": Double(frames.count), "cadence": round3(cadence)],
                                 findings: findings)
    }

    /// Runs of equal values: the value, the first sample index and the run's length.
    static func runs<T: Equatable>(_ values: [T]) -> [(value: T, start: Int, count: Int)] {
        var out: [(value: T, start: Int, count: Int)] = []
        for (i, v) in values.enumerated() {
            if let last = out.last, last.value == v { out[out.count - 1].count += 1 } else { out.append((v, i, 1)) }
        }
        return out
    }

    /// Shown, hidden, shown, or hidden, shown, hidden, with the middle run at most `within` samples.
    static func blinks(_ key: String, _ shown: [Bool], times: [Double], within: Int) -> [FeelFinding] {
        let runs = runs(shown)
        guard runs.count >= 3 else { return [] }
        var out: [FeelFinding] = []
        for i in 1..<(runs.count - 1) where runs[i].count <= within {
            let at = times[runs[i].start]
            let what = runs[i].value
                ? "\"\(key)\" blinked on for \(runs[i].count) \(runs[i].count == 1 ? "sample" : "samples") at \(FeelResult.number(round3(at))) s, then went again"
                : "\"\(key)\" went away for \(runs[i].count) \(runs[i].count == 1 ? "sample" : "samples") at \(FeelResult.number(round3(at))) s, then came back"
            out.append(FeelFinding(what: what))
        }
        return out
    }

    /// A label taken back (A, B, A) within `within` samples, or changed more than `changes` times within `within`
    /// samples. Hidden samples are skipped: a blink is judged on its own.
    static func wordFlips(_ key: String, _ seen: [FeelSeen?], times: [Double], within: Int, changes: Int) -> [FeelFinding] {
        let shown = seen.enumerated().compactMap { i, s in s.map { (i, $0.label) } }
        // Each change: the sample index it happened at, from what, to what.
        var steps: [(at: Int, from: String, to: String)] = []
        for (a, b) in zip(shown, shown.dropFirst()) where a.1 != b.1 { steps.append((b.0, a.1, b.1)) }
        var out: [FeelFinding] = []
        var reported = Set<Int>()
        for (n, step) in steps.enumerated() {
            if n > 0, steps[n - 1].from == step.to, step.at - steps[n - 1].at <= within, !reported.contains(n) {
                reported.insert(n)
                out.append(FeelFinding(what: "\"\(key)\"'s words changed and were taken back \(step.at - steps[n - 1].at) samples later, at \(FeelResult.number(round3(times[step.at]))) s"))
            }
        }
        if out.isEmpty {
            // The busiest window of `within` samples.
            var most = 0, at = 0
            for (n, step) in steps.enumerated() {
                let count = steps[n...].prefix { $0.at - step.at < within }.count
                if count > most { most = count; at = step.at }
            }
            if most > changes {
                out.append(FeelFinding(what: "\"\(key)\"'s words changed \(FeelFilm.times(most)) within \(within) samples from \(FeelResult.number(round3(times[at]))) s before settling (at most \(changes) expected)"))
            }
        }
        return out
    }

    /// Rested at a place, left it by more than `distance`, and rested there again within `within` samples.
    static func placeFlips(_ key: String, _ seen: [FeelSeen?], times: [Double], within: Int, distance apart: Double,
                           tolerance: Double) -> [FeelFinding] {
        // Rests: runs of two or more samples in the same frame.
        var rests: [(frame: CGRect, start: Int, end: Int)] = []
        var i = 0
        while i < seen.count {
            guard let f = seen[i]?.frame else { i += 1; continue }
            var j = i
            while j + 1 < seen.count, let g = seen[j + 1]?.frame, distance(f, g) <= tolerance { j += 1 }
            if j > i { rests.append((f, i, j)) }
            i = j + 1
        }
        var out: [FeelFinding] = []
        for (n, rest) in rests.enumerated() {
            guard let back = rests[(n + 1)...].first(where: { distance(rest.frame, $0.frame) <= tolerance }) else { continue }
            guard back.start - rest.end <= within else { continue }
            let between = seen[(rest.end + 1)..<back.start].compactMap { $0?.frame }
            let far = between.map { distance(rest.frame, $0) }.max() ?? 0
            guard far > apart else { continue }
            out.append(FeelFinding(what: "\"\(key)\" left its place by \(FeelResult.number(round3(far))) pt at \(FeelResult.number(round3(times[rest.end + 1]))) s and came back to it \(back.start - rest.end) samples later"))
        }
        return out
    }
}
