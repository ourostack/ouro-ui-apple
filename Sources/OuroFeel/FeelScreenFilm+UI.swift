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
    ///
    /// Only what follows the app's clock is filmed deterministically. Motion on wall time (a web view's CSS or WebKit's
    /// own fades) is caught at whatever point each screenshot lands; film such content from a recording instead.
    /// A screenshot is taken once the accessibility tree shows the tick, which on a slow runner can be a frame before
    /// the screen shows it, so give a fixture's states a few ticks each.
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
            guard let frame = Self.thumbnail(shot, width: width, blank: blank, t: t) else { return false }
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

    /// One picture of the screen now, shrunk and blanked as ``screenFilm(steps:tick:clock:advance:width:statusBand:ignoring:stall:during:)``
    /// does (the status band, the clock's label, `ignoring`), to compare a film with: the cover for
    /// ``FeelScreenFilm/revealHolds(cover:until:stable:merge:run:)``, taken while it is surely up. Nil when there is no
    /// screenshot to take.
    public func screenPicture(clock: String, width: Int = 160, statusBand: CGFloat = 60, ignoring: [CGRect] = []) -> FeelScreenFrame? {
        let clockFrame = self.seen([clock]).seen.first { $0.key == clock }?.frame ?? .zero
        let shot = XCUIScreen.main.screenshot().image
        let blank = [CGRect(x: 0, y: 0, width: shot.size.width, height: statusBand), clockFrame.insetBy(dx: -4, dy: -4)] + ignoring
        return Self.thumbnail(shot, width: width, blank: blank, t: 0)
    }

    /// A screenshot as a `width`-pixel grayscale thumbnail, with each rect of `blank` (in points, top down) painted
    /// black. Drawn through UIKit, so a landscape screenshot's orientation is honoured and the rects land where they are.
    static func thumbnail(_ image: UIImage, width: Int, blank: [CGRect], t: Double) -> FeelScreenFrame? {
        let points = image.size
        guard points.width > 0, points.height > 0, width > 0 else { return nil }
        let height = max(1, Int((Double(width) * points.height / points.width).rounded()))
        var gray = [UInt8](repeating: 0, count: width * height)
        let drawn = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            // Top down, as UIKit draws: row 0 of the buffer is the top of the screen.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            UIGraphicsPopContext()
            let sx = CGFloat(width) / points.width, sy = CGFloat(height) / points.height
            context.setFillColor(gray: 0, alpha: 1)
            for r in blank { context.fill(CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy)) }
            return true
        }
        return drawn ? FeelScreenFrame(t: t, width: width, height: height, gray: gray) : nil
    }
}
#endif
