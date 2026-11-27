public import Foundation

// MARK: The screen shows only the before, the after or a veil

extension FeelScreenFilm {
    /// The screen shows only the before, the after or a veil, under motion and chrome never surprise (nothing moves
    /// unbidden): through a turn or a jump, every state the screen rests on is the old view, the new one, or a plain
    /// veil. Never a stretched, squeezed, shrunken or blended picture, a band, or another page.
    ///
    /// From Gatefold, 2026-11-27: an iPad turn showed the portrait page stretched to landscape for about 2.5 s, then a
    /// tiny layout, then two layouts at once (ourostack/gatefold#649); an open Duo's turn showed clipped columns, a grey
    /// band and the next chapter over the page (#648). A search jump that drew two pages at once, then a page that was
    /// neither, before the target (#653) is the same promise, but its wrong states lasted about 0.2 s each, under a
    /// screenshot film's rest, so this does not catch it yet: that needs a film at the display's pace.
    ///
    /// The before is the film's ``cover``, shot just before the action (`screenFilm(cover: true, …)`); the after is the
    /// rest the film ends on, which must reach its last sample and match `later`, a picture shot a second or two after
    /// the film (OuroFeel's `feel.beforeAfterOrVeil(film)` shoots it), so a wrong picture that outlasts the film is not
    /// taken for the after. A veil is a picture at least `uniform` of one shade (a blank), a
    /// dimmed or washed copy of the before (``isDimmed(_:of:merge:)``: the old page greyed while the next one loads), or
    /// one under `merge` from a picture in `veils` (the app's own loading state, such as a skeleton). Rests are
    /// ``states(stable:merge:run:)``: frames on their way between two rests (a turn's animation, a cross-fade) are not
    /// judged here, so a wrong state too brief to rest for `run` samples is not seen; film at the display's pace to see
    /// one. Pictures are compared only with pictures of the same size, since a turn changes the screen's shape. It cannot
    /// be checked without a cover, when the film stalled or skipped, when it was still changing at its end, or without a
    /// later picture that matches its end.
    public func beforeAfterOrVeil(veils: [FeelScreenFrame] = [], later: FeelScreenFrame? = nil, uniform: Double = 0.98,
                                  stable: Double = 0.6, merge: Double = 1.5, run: Int = 2) -> FeelResult {
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
            if let later {
                if !near(later, after) {
                    let by = Self.difference(later, after).map { "\(FeelResult.number(Self.round3($0))) from the after" } ?? "another shape"
                    findings.append(.couldNotCheck("the screen changed after the film ended (a later picture is \(by)), so the "
                        + "film did not reach the after; film for longer"))
                }
            } else {
                findings.append(.couldNotCheck("there is no later picture to show the film's end was the after: judge it with "
                    + "feel.beforeAfterOrVeil(film), or pass later:"))
            }
            var labels: Set<Int> = []
            for state in found where !labels.contains(state.label) {
                let picture = frames[state.end]
                if near(picture, cover) || near(picture, after) || later.map({ near(picture, $0) }) == true
                    || Self.isVeil(picture, uniform: uniform) || Self.isDimmed(picture, of: cover, merge: merge)
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

    /// Whether `picture` is `before` dimmed or washed evenly (a dark scrim, a light veil over the old page): each pixel is
    /// the before's scaled by the same factor, under 0.9, plus the same shade. Undoing that dim must give back the before
    /// to within `merge` on average, measured on the before's own scale, since dimming shrinks every difference with it
    /// (another page of the same layout, dimmed, would otherwise pass). A different page, or the before itself, is not.
    /// Pixels black in both (the film's blanked bands) are left out.
    public static func isDimmed(_ picture: FeelScreenFrame, of before: FeelScreenFrame, merge: Double = 1.5) -> Bool {
        guard picture.width == before.width, picture.height == before.height, picture.gray.count == before.gray.count else { return false }
        var xs: [Double] = [], ys: [Double] = []
        for i in 0..<picture.gray.count where !(picture.gray[i] == 0 && before.gray[i] == 0) {
            xs.append(Double(before.gray[i]))
            ys.append(Double(picture.gray[i]))
        }
        guard xs.count >= 4 else { return false }
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0
        for (x, y) in zip(xs, ys) { sxx += (x - mx) * (x - mx); sxy += (x - mx) * (y - my) }
        // The before needs some contrast to be recognised in its dimmed copy (a plain before is judged by isVeil).
        guard sxx / n > 25 else { return false }
        let a = sxy / sxx, b = my - a * mx
        guard a > 0.05, a < 0.9 else { return false }
        let undone = zip(xs, ys).reduce(0.0) { $0 + abs(($1.1 - b) / a - $1.0) } / n
        return undone < merge
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
