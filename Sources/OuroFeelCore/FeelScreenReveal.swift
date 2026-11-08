public import Foundation

// MARK: The first page shown is the one that stays

extension FeelScreenFilm {
    /// Jump after landing, at an open, judged from pixels: the first thing the screen rests on once the cover goes is the
    /// thing it stays on. Gatefold build 20 relaunched on an iPad showed a page 25 pages from his place for about 10 s,
    /// then jumped to it, while the app's own report of the place was right throughout; this catches that from the
    /// screen.
    ///
    /// `cover` is a picture of the cover, taken while it is surely up (before the action that opens, or from a known
    /// launch placeholder), on the same size and blanking as the film. The judge never guesses which rest is the cover:
    /// a film that starts after the cover had gone would otherwise take the wrong first page for the cover and pass the
    /// very jump it is for. Rests before the first one that looks like `cover` (under `merge`) are not judged. The reveal
    /// is the first rest after the cover that is not the cover; every rest after it that begins before sample `until`
    /// (the next scripted mark, not itself included; the film's end when nil) must be the reveal. Another rest, the
    /// cover coming back, or a flash away and back fails. Judged in samples, never seconds, with the same rests
    /// (`stable`, `merge`, `run`) as ``flickers(within:states:stable:merge:run:)``. It cannot be checked when the film
    /// stalled, skipped a tick or mixed picture sizes, when `cover` is another size, when no rest looks like the cover
    /// (start the film while the cover is up), when nothing but the cover rests, or when the screen was still changing
    /// at `until`.
    public func revealHolds(cover: FeelScreenFrame, until: Int? = nil, stable: Double = 0.6, merge: Double = 1.5,
                            run: Int = 2) -> FeelResult {
        let run = max(2, run)
        let end = max(0, min(until ?? frames.count, frames.count))  // exclusive
        var findings = unjudgeable(run: run)
        var jumps = 0
        func at(_ i: Int) -> String { FeelResult.number(Self.round3(frames[min(max(0, i), frames.count - 1)].t)) }
        let sizes = Set(frames.map { "\($0.width)x\($0.height)" })
        let coverFits = sizes.isEmpty || sizes == ["\(cover.width)x\(cover.height)"]
        if !coverFits {
            findings.append(.couldNotCheck("the cover picture is \(cover.width)x\(cover.height), not the film's size, so it cannot be compared"))
        }
        if sizes.count <= 1, coverFits, frames.count >= run {
            let found = states(stable: stable, merge: merge, run: run).filter { $0.start < end }
            func isCover(_ s: State) -> Bool { (Self.difference(frames[s.end], cover) ?? .infinity) < merge }
            if let first = found.firstIndex(where: isCover) {
                if let r = found[first...].firstIndex(where: { !isCover($0) }) {
                    let reveal = found[r]
                    let after = found[r...]
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
                    if jumps == 0, let last = after.last, last.end < end - 1 {
                        findings.append(.couldNotCheck("the screen was still changing before sample \(end) (\(at(end - 1)) s), so whether the first page held was not seen; film for longer"))
                    }
                } else {
                    findings.append(.couldNotCheck("the screen never rested on anything but the cover before sample \(end); film for longer"))
                }
            } else {
                findings.append(.couldNotCheck(found.isEmpty
                    ? "the screen never rested; film for longer"
                    : "no rest looked like the cover, so where it ended was not seen; start the film while the cover is up"))
            }
        }
        let result = FeelResult.judged(
            check: FeelGenre.jumpAfterLanding.rawValue,
            passing: "the first page shown after the cover held for \(end) samples",
            failing: { _ in "the first page shown after the cover did not hold" },
            measures: ["jumps": Double(jumps), "samples": Double(end)],
            findings: findings)
        guard let timedBy, result.environment == nil else { return result }
        var stamped = result
        stamped.environment = FeelEnvironment.current(clock: timedBy)
        return stamped
    }
}
