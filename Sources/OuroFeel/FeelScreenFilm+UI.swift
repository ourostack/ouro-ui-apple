#if canImport(XCTest) && os(iOS)
public import CoreGraphics
public import OuroFeelCore
public import XCTest

extension OuroFeel {
    /// Films the whole screen on the app's own clock, for ``FeelScreenFilm/flickers(within:states:stable:merge:run:)``:
    /// one screenshot per tick, shrunk to a `width`-pixel grayscale thumbnail. Like
    /// ``film(_:steps:tick:clock:advance:stall:during:)``, each sample waits for the app to show the next count on
    /// `clock`, never a fixed time, and the film ends early, with ``FeelScreenFilm/stalledAt`` set, if it shows none for
    /// `stall` seconds.
    ///
    /// The clock's own label changes every tick, so its frame is blanked, along with the top `statusBand` points (the
    /// status bar's time and battery) and every rect in `ignoring` (in the window's points: a slip the app means to show
    /// and take away again).
    public func screenFilm(steps: Int, tick: TimeInterval, clock: String, advance: () -> Void, width: Int = 160,
                           statusBand: CGFloat = 60, ignoring: [CGRect] = [], stall: TimeInterval = 30,
                           during action: (() -> Void)? = nil) -> FeelScreenFilm {
        let timedBy = "the app's own clock (\"\(clock)\", \(String(format: "%g", tick)) s a tick), one screenshot per tick"
        func sample(atLeast least: Int) -> (count: Int, clockFrame: CGRect)? {
            let deadline = Date().addingTimeInterval(stall)
            repeat {
                let (_, seen) = self.seen([clock])
                if let c = seen.first(where: { $0.key == clock }), let n = Int(c.label), n >= least { return (n, c.frame) }
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            } while Date() < deadline
            return nil
        }
        action?()
        guard let (base, clockFrame) = sample(atLeast: .min) else {
            return FeelScreenFilm(frames: [], stalledAt: 0, timedBy: timedBy)
        }
        var frames: [FeelScreenFrame] = []
        func shoot(at t: Double, clockFrame: CGRect) -> Bool {
            let shot = XCUIScreen.main.screenshot().image
            let points = shot.size
            let blank = [CGRect(x: 0, y: 0, width: points.width, height: statusBand), clockFrame.insetBy(dx: -4, dy: -4)] + ignoring
            guard let cg = shot.cgImage, let frame = Self.thumbnail(cg, points: points, width: width, blank: blank, t: t) else { return false }
            frames.append(frame)
            return true
        }
        guard shoot(at: 0, clockFrame: clockFrame) else { return FeelScreenFilm(frames: [], stalledAt: 0, timedBy: timedBy) }
        for step in 1...max(1, steps) {
            advance()
            guard let (n, frame) = sample(atLeast: base + step), shoot(at: Double(n - base) * tick, clockFrame: frame) else {
                return FeelScreenFilm(frames: frames, stalledAt: Double(step - 1) * tick, timedBy: timedBy)
            }
        }
        return FeelScreenFilm(frames: frames, timedBy: timedBy)
    }

    /// A screenshot as a `width`-pixel grayscale thumbnail, with each rect of `blank` (in points) painted black.
    static func thumbnail(_ image: CGImage, points: CGSize, width: Int, blank: [CGRect], t: Double) -> FeelScreenFrame? {
        guard points.width > 0, points.height > 0, width > 0 else { return nil }
        let height = max(1, Int((Double(width) * points.height / points.width).rounded()))
        var gray = [UInt8](repeating: 0, count: width * height)
        let drawn = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            // Points run down from the top; the context's y runs up from the bottom.
            let sx = CGFloat(width) / points.width, sy = CGFloat(height) / points.height
            context.setFillColor(gray: 0, alpha: 1)
            for r in blank {
                context.fill(CGRect(x: r.minX * sx, y: CGFloat(height) - r.maxY * sy, width: r.width * sx, height: r.height * sy))
            }
            return true
        }
        return drawn ? FeelScreenFrame(t: t, width: width, height: height, gray: gray) : nil
    }
}
#endif
