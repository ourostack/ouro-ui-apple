public import Foundation

// MARK: The first page shown is the one that stays

extension FeelScreenFilm {
    /// Jump after landing, at an open, judged from pixels: the first thing the screen rests on once the cover goes is the
    /// thing it stays on. Gatefold build 20 relaunched on an iPad showed a page 25 pages from his place for about 10 s,
    /// then jumped to it, while the app's own report of the place was right throughout; this catches that from the
    /// screen.
    ///
    /// The film starts on the cover (a launch screen, a placeholder, a picture of the page): the first rest is the cover,
    /// and every rest after it, up to sample `until` (the next scripted mark; the film's end when nil), must be the first
    /// one that is not the cover. A flash away from it and back is caught as it is by
    /// ``flickers(within:states:stable:merge:run:)``. Judged in samples, never seconds, with the same rests (`stable`,
    /// `merge`, `run`). It cannot be checked when the film stalled, skipped a tick, mixed picture sizes, never showed a
    /// rest after the cover, or was still changing at `until`.
    public func revealHolds(until: Int? = nil, stable: Double = 0.6, merge: Double = 1.5, run: Int = 2) -> FeelResult {
        let run = max(2, run)
        let end = min(until ?? (frames.count - 1), frames.count - 1)
        var findings = unjudgeable(run: run)
        var jumps = 0
        func at(_ i: Int) -> String { FeelResult.number(Self.round3(frames[i].t)) }
        if findings.allSatisfy({ !$0.what.contains("one size") }), frames.count >= run {
            let found = states(stable: stable, merge: merge, run: run).filter { $0.start <= end }
            if let cover = found.first, let reveal = found.dropFirst().first(where: { $0.label != cover.label }) {
                let after = found.drop { $0.start < reveal.start }
                for (a, b) in zip(after, after.dropFirst()) {
                    if b.label != reveal.label {
                        jumps += 1
                        findings.append(FeelFinding(what: "the first page shown (from \(at(reveal.start)) s) was replaced at \(at(b.start)) s, \(b.start - reveal.start) samples after it showed"))
                        break
                    }
                    if b.start > a.end + 1, let far = ((a.end + 1)..<b.start).first(where: { (Self.difference(frames[$0], frames[a.end]) ?? 0) >= merge }) {
                        jumps += 1
                        findings.append(FeelFinding(what: "the first page shown flashed away at \(at(far)) s and came back"))
                        break
                    }
                }
                if let last = after.last, last.end < end, jumps == 0 {
                    findings.append(.couldNotCheck("the screen was still changing at sample \(end) (\(at(end)) s), so whether the first page held was not seen; film for longer"))
                }
            } else {
                findings.append(.couldNotCheck(found.isEmpty
                    ? "the screen never rested; film for longer"
                    : "the screen never rested on anything but the cover by sample \(end); film for longer"))
            }
        }
        let result = FeelResult.judged(
            check: FeelGenre.jumpAfterLanding.rawValue,
            passing: "the first page shown after the cover held for \(end + 1) samples",
            failing: { _ in "the first page shown after the cover did not hold" },
            measures: ["jumps": Double(jumps), "samples": Double(end + 1)],
            findings: findings)
        guard let timedBy, result.environment == nil else { return result }
        var stamped = result
        stamped.environment = FeelEnvironment.current(clock: timedBy)
        return stamped
    }
}
