public import Foundation

// MARK: A failing screen film, as a picture

extension FeelScreenFilm {
    /// Every sample of the film, side by side in reading order, as one grayscale picture to save beside a failing report
    /// (#73): a check judged from pixels is hard to explain from its text alone. Each sample is drawn as filmed (with
    /// its blanked regions), `gap` pixels apart, `columns` to a row. Under each sample is a `mark`-pixel strip: white
    /// when the sample is part of a rest the judge found (``states(stable:merge:run:)``), black when it is on its way or
    /// flashing. Nil when the film is empty or its samples differ in size.
    public func contactSheet(columns: Int = 10, gap: Int = 2, mark: Int = 3, stable: Double = 0.6, merge: Double = 1.5,
                             run: Int = 2) -> FeelScreenFrame? {
        guard let first = frames.first, first.width > 0, first.height > 0,
              frames.allSatisfy({ $0.width == first.width && $0.height == first.height && $0.gray.count == first.gray.count })
        else { return nil }
        let columns = max(1, min(columns, frames.count)), gap = max(0, gap), mark = max(0, mark)
        let rows = (frames.count + columns - 1) / columns
        let cellW = first.width + gap, cellH = first.height + mark + gap
        let width = columns * cellW - gap, height = rows * cellH - gap
        var gray = [UInt8](repeating: 128, count: width * height)
        var resting = [Bool](repeating: false, count: frames.count)
        for state in states(stable: stable, merge: merge, run: max(2, run)) {
            for i in state.start...state.end { resting[i] = true }
        }
        for (n, frame) in frames.enumerated() {
            let x0 = (n % columns) * cellW, y0 = (n / columns) * cellH
            for y in 0..<frame.height {
                let src = y * frame.width, dst = (y0 + y) * width + x0
                gray.replaceSubrange(dst..<(dst + frame.width), with: frame.gray[src..<(src + frame.width)])
            }
            for y in 0..<mark {
                let dst = (y0 + frame.height + y) * width + x0
                gray.replaceSubrange(dst..<(dst + frame.width), with: repeatElement(resting[n] ? 255 : 0, count: frame.width))
            }
        }
        return FeelScreenFrame(t: 0, width: width, height: height, gray: gray)
    }
}
