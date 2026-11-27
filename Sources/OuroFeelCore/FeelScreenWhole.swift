public import Foundation

// MARK: The screen shows only the before, the after or a veil

extension FeelScreenFilm {
    /// The screen shows only the before, the after or a veil, under motion and chrome never surprise (nothing moves
    /// unbidden): through a turn or a jump, every state the screen rests on is the old view, the new one, or a plain
    /// veil. Never a stretched, squeezed, shrunken or blended picture, a band, or another page.
    ///
    /// From Gatefold, 2026-11-27: an iPad turn showed the portrait page stretched to landscape for about 2.5 s, then a
    /// tiny layout, then two layouts at once (ourostack/gatefold#649); an open Duo's turn showed clipped columns, a grey
    /// band and the next chapter over the page (#648); and a search jump drew two pages at once, then a page that was
    /// neither, before the target (#653).
    ///
    /// The before is the film's ``cover``, shot just before the action (`screenFilm(cover: true, …)`); the after is the
    /// rest the film ends on, which must reach its last sample. A veil is a picture at least `uniform` of one shade (a
    /// blank, a dim) or one under `merge` from a picture in `veils` (the app's own loading state). Rests are
    /// ``states(stable:merge:run:)``: frames on their way between two rests (a turn's animation, a cross-fade) are not
    /// judged here, so a wrong state too brief to rest for `run` samples is not seen; film at the display's pace to see
    /// one. Pictures are compared only with pictures of the same size, since a turn changes the screen's shape. It cannot
    /// be checked without a cover, when the film stalled or skipped, or when it was still changing at its end.
    public func beforeAfterOrVeil(veils: [FeelScreenFrame] = [], uniform: Double = 0.98, stable: Double = 0.6,
                                  merge: Double = 1.5, run: Int = 2) -> FeelResult {
        let run = max(2, run)
        let check = FeelCheck.beforeAfterOrVeil.name
        guard let cover else {
            return FeelResult.judged(check: check, passing: "", failing: { _ in "" },
                                     findings: [.couldNotCheck("the film has no picture of the before: film it with screenFilm(cover: true, …)")])
        }
        var findings = unjudgeable(run: run, sizes: false)
        var third = 0
        func at(_ i: Int) -> String { String(format: "%.2f", frames[min(max(0, i), frames.count - 1)].t) }
        func near(_ a: FeelScreenFrame, _ b: FeelScreenFrame) -> Bool { (Self.difference(a, b) ?? .infinity) < merge }
        let found = frames.count >= run ? states(stable: stable, merge: merge, run: run) : []
        if let last = found.last, last.end == frames.count - 1 {
            let after = frames[last.end]
            var labels: Set<Int> = []
            for state in found where !labels.contains(state.label) {
                let picture = frames[state.end]
                if near(picture, cover) || near(picture, after) || Self.isVeil(picture, uniform: uniform)
                    || veils.contains(where: { near(picture, $0) }) { continue }
                labels.insert(state.label)
                third += 1
                let from = Self.difference(picture, cover).map { "\(FeelResult.number(Self.round3($0))) from the before" }
                    ?? "another shape than the before"
                let to = Self.difference(picture, after).map { "\(FeelResult.number(Self.round3($0))) from the after" }
                    ?? "another shape than the after"
                let samples = state.end - state.start + 1
                findings.append(FeelFinding(what: "the screen rested on a state that is neither the before, the after nor a "
                    + "veil, for \(samples) samples from \(at(state.start)) s to \(at(state.end)) s (\(from), \(to), where "
                    + "\(FeelResult.number(merge)) is the same)"))
            }
            if near(after, cover) {
                findings.append(.note("the film ended where it started, so the action changed nothing on screen"))
            }
        } else if !found.isEmpty {
            let last = found[found.count - 1]
            findings.append(.couldNotCheck("the screen was still changing in the film's last \(frames.count - 1 - last.end) "
                + "samples, so the after was not seen; film for longer"))
        } else if frames.count >= run {
            findings.append(.couldNotCheck("the screen never rested for \(run) samples; film for longer"))
        }
        let result = FeelResult.judged(
            check: check,
            passing: "the screen rested only on the before, the after or a veil in \(frames.count) samples",
            failing: { "the screen rested on \($0 == 1 ? "a state" : "\($0) states") that \($0 == 1 ? "is" : "are") neither the before, the after nor a veil" },
            measures: ["samples": Double(frames.count), "states": Double(Set(found.map(\.label)).count), "third states": Double(third)],
            findings: findings)
        guard let timedBy, result.environment == nil else { return result }
        var stamped = result
        stamped.environment = FeelEnvironment.current(clock: timedBy)
        return stamped
    }

    /// Whether a picture is a veil: at least `uniform` of its pixels within 6 of its middle shade. Pure black pixels are
    /// left out when most of the picture is not black, since the film paints the status band and ignored rects black.
    public static func isVeil(_ picture: FeelScreenFrame, uniform: Double = 0.98) -> Bool {
        guard !picture.gray.isEmpty else { return false }
        let lit = picture.gray.filter { $0 != 0 }
        let pixels = lit.count * 2 >= picture.gray.count ? lit : picture.gray
        let sorted = pixels.sorted()
        let middle = Int(sorted[sorted.count / 2])
        let near = pixels.reduce(0) { $0 + (abs(Int($1) - middle) <= 6 ? 1 : 0) }
        return Double(near) / Double(pixels.count) >= uniform
    }
}
