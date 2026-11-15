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
    /// status bar's time and battery) and every rect in `ignoring` (in the app's points, as ``seen(_:)`` gives them: a slip the app means
    /// to show and take away again).
    ///
    /// Only what follows the app's clock is filmed deterministically. Motion on wall time (a web view's CSS or WebKit's
    /// own fades) is caught at whatever point each screenshot lands; film such content from a recording instead.
    /// A screenshot is taken once the accessibility tree shows the tick, which on a slow runner can be a frame before
    /// the screen shows it, so give a fixture's states a few ticks each.
    public func screenFilm(steps: Int, tick: TimeInterval, clock: String, advance: () -> Void, width: Int = 160,
                           statusBand: CGFloat = 60, ignoring: [CGRect] = [], stall: TimeInterval = 30,
                           during action: (() -> Void)? = nil) -> FeelScreenFilm {
        screenFilm(cover: false, steps: steps, tick: tick, clock: clock, advance: advance, width: width,
                   statusBand: statusBand, ignoring: ignoring, stall: stall, during: action)
    }

    /// ``screenFilm(steps:tick:clock:advance:width:statusBand:ignoring:stall:during:)`` that, with `cover`, first shoots
    /// the screen as it is, before `action`, with the film's own size and blanking, into ``FeelScreenFilm/cover``, for
    /// ``FeelScreenFilm/revealHolds(until:stable:merge:run:)``. Start it while the cover is up. A cover taken apart with
    /// ``screenPicture(clock:width:statusBand:ignoring:)`` and other settings would only make the judge "could not check".
    public func screenFilm(cover: Bool, steps: Int, tick: TimeInterval, clock: String, advance: () -> Void,
                           width: Int = 160, statusBand: CGFloat = 60, ignoring: [CGRect] = [], stall: TimeInterval = 30,
                           during action: (() -> Void)? = nil) -> FeelScreenFilm {
        var coverClock = CGRect.null
        let coverPicture = cover ? screenPicture(clock: clock, width: width, statusBand: statusBand, ignoring: ignoring, clockOnScreen: &coverClock) : nil
        return clockFilm(steps: steps, tick: tick, clock: clock, advance: advance, width: width, statusBand: statusBand,
                         ignoring: ignoring, stall: stall, during: action, cover: coverPicture, coverClock: coverClock)
    }

    func clockFilm(steps: Int, tick: TimeInterval, clock: String, advance: () -> Void, width: Int,
                   statusBand: CGFloat, ignoring: [CGRect], stall: TimeInterval,
                   during action: (() -> Void)?, cover: FeelScreenFrame? = nil, coverClock: CGRect = .null) -> FeelScreenFilm {
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
        let onScreen = screenMapping()
        guard let (base, clockFrame) = sample(atLeast: .min) else {
            var film = FeelScreenFilm(frames: [], stalledAt: 0, timedBy: timedBy)
            film.cover = cover
            return film
        }
        var frames: [FeelScreenFrame] = []
        // Every place the clock's blank fell, so each sample can be blanked at all of them once the film ends.
        var clocks = coverClock, screen = CGSize.zero
        func shoot(at t: Double, clockFrame: CGRect) -> Bool {
            let shot = XCUIScreen.main.screenshot().image
            let points = shot.size
            let clockBlank = onScreen(clockFrame).insetBy(dx: -Self.clockMargin, dy: -Self.clockMargin)
            let blank = [CGRect(x: 0, y: 0, width: points.width, height: statusBand), clockBlank] + ignoring.map(onScreen)
            guard let frame = Self.thumbnail(shot, width: width, blank: blank, t: t) else { return false }
            frames.append(frame)
            clocks = clocks.union(clockBlank)
            screen = points
            return true
        }
        // The clock's frame can shift a little between ticks. Where a thumbnail pixel spans more than a point (on an
        // iPad, a 640-pixel film of a 1032-point screen), a blank that moved a fraction of a point shows as a change at
        // its edge (#73, item 2). So every sample is blanked at every place the clock was.
        func film(stalledAt: Double? = nil) -> FeelScreenFilm {
            var film = FeelScreenFilm(frames: frames.map { Self.blanking(clocks, in: $0, screen: screen) }, stalledAt: stalledAt, timedBy: timedBy)
            film.cover = cover.map { Self.blanking(clocks, in: $0, screen: screen) }
            return film
        }
        guard shoot(at: 0, clockFrame: clockFrame) else { return film(stalledAt: 0) }
        for step in 1...max(1, steps) {
            advance()
            guard let (n, frame) = sample(atLeast: base + step), shoot(at: Double(n - base) * tick, clockFrame: frame) else {
                return film(stalledAt: Double(step - 1) * tick)
            }
        }
        return film()
    }

    /// Films the whole screen for an app with no clock of its own (#94): one screenshot per XCUITest read, as fast as
    /// screenshots come, each shrunk to a `width`-pixel grayscale thumbnail with the top `statusBand` points and every
    /// rect in `ignoring` blanked. An app that runs on the system's animations (UIKit, a web view, a reader engine)
    /// can't step a clock for ``screenFilm(steps:tick:clock:advance:width:statusBand:ignoring:stall:during:)``, so this
    /// samples it as it plays and the film is judged in reads: ``FeelScreenFilm/flickers(within:states:stable:merge:run:)``
    /// and ``FeelScreenFilm/revealHolds(cover:until:stable:merge:run:)`` count samples, never seconds.
    ///
    /// It reads for at least `atLeast` seconds after `action`, then stops once the last `settle` reads all look the same
    /// (under 0.6 apart, a film's `stable`), or after `reads` reads at most. Set `atLeast` past the slowest step you
    /// expect, so a page that rests for a moment before it jumps is still filmed when it jumps. The film is marked
    /// ``FeelScreenFilm/byReads`` and its ``FeelScreenFilm/timedBy`` says how many reads covered how long, since a flash
    /// shorter than one read can't be seen. Each sample's `t` is the seconds since `action`, for the report only.
    public func screenFilm(reads: Int = 120, atLeast: TimeInterval = 2, settle: Int = 6, width: Int = 160,
                           statusBand: CGFloat = 60, ignoring: [CGRect] = [],
                           during action: (() -> Void)? = nil) -> FeelScreenFilm {
        screenFilm(cover: false, reads: reads, atLeast: atLeast, settle: settle, width: width, statusBand: statusBand,
                   ignoring: ignoring, during: action)
    }

    /// ``screenFilm(reads:atLeast:settle:width:statusBand:ignoring:during:)`` that, with `cover`, first shoots the screen
    /// as it is, before `action`, with the film's own size and blanking, into ``FeelScreenFilm/cover``, for
    /// ``FeelScreenFilm/revealHolds(until:stable:merge:run:)``. Start it while the cover is up.
    public func screenFilm(cover: Bool, reads: Int = 120, atLeast: TimeInterval = 2, settle: Int = 6, width: Int = 160,
                           statusBand: CGFloat = 60, ignoring: [CGRect] = [],
                           during action: (() -> Void)? = nil) -> FeelScreenFilm {
        let coverPicture = cover ? screenPicture(width: width, statusBand: statusBand, ignoring: ignoring) : nil
        var frames: [FeelScreenFrame] = []
        let onScreen = screenMapping()
        action?()
        let start = Date()
        let settle = max(2, settle)
        while frames.count < max(1, reads) {
            let shot = XCUIScreen.main.screenshot().image
            let t = Date().timeIntervalSince(start)
            let blank = [CGRect(x: 0, y: 0, width: shot.size.width, height: statusBand)] + ignoring.map(onScreen)
            guard let frame = Self.thumbnail(shot, width: width, blank: blank, t: t) else { break }
            frames.append(frame)
            if t >= atLeast, frames.count >= settle {
                let last = frames.suffix(settle)
                if let first = last.first, last.allSatisfy({ (FeelScreenFilm.difference(first, $0) ?? .infinity) < 0.6 }) { break }
            }
        }
        let seconds = frames.last.map { String(format: "%.2f", $0.t) } ?? "0"
        var film = FeelScreenFilm(frames: frames, timedBy: "XCUITest's reads, one screenshot a read (\(frames.count) reads over \(seconds) s; a flash shorter than one read is not seen)")
        film.byReads = true
        film.cover = coverPicture
        return film
    }

    /// One picture of the screen now, shrunk and blanked as ``screenFilm(steps:tick:clock:advance:width:statusBand:ignoring:stall:during:)``
    /// does (the status band, the clock's label, `ignoring`), to compare a film with: the cover for
    /// ``FeelScreenFilm/revealHolds(cover:until:stable:merge:run:)``, taken while it is surely up. Nil when there is no
    /// screenshot to take.
    public func screenPicture(clock: String, width: Int = 160, statusBand: CGFloat = 60, ignoring: [CGRect] = []) -> FeelScreenFrame? {
        var clockOnScreen = CGRect.null
        return screenPicture(clock: clock, width: width, statusBand: statusBand, ignoring: ignoring, clockOnScreen: &clockOnScreen)
    }

    func screenPicture(clock: String, width: Int, statusBand: CGFloat, ignoring: [CGRect], clockOnScreen: inout CGRect) -> FeelScreenFrame? {
        let onScreen = screenMapping()
        let clockFrame = self.seen([clock]).seen.first { $0.key == clock }.map { onScreen($0.frame) } ?? .zero
        let shot = XCUIScreen.main.screenshot().image
        clockOnScreen = clockFrame.insetBy(dx: -Self.clockMargin, dy: -Self.clockMargin)
        let blank = [CGRect(x: 0, y: 0, width: shot.size.width, height: statusBand), clockOnScreen] + ignoring.map(onScreen)
        return Self.thumbnail(shot, width: width, blank: blank, t: 0)
    }

    /// One picture of the screen now, shrunk and blanked as ``screenFilm(reads:atLeast:settle:width:statusBand:ignoring:during:)``
    /// does (the status band and `ignoring`), for an app with no clock of its own: the cover for
    /// ``FeelScreenFilm/revealHolds(cover:until:stable:merge:run:)``, taken while it is surely up. Nil when there is no
    /// screenshot to take.
    public func screenPicture(width: Int = 160, statusBand: CGFloat = 60, ignoring: [CGRect] = []) -> FeelScreenFrame? {
        let onScreen = screenMapping()
        let shot = XCUIScreen.main.screenshot().image
        return Self.thumbnail(shot, width: width, blank: [CGRect(x: 0, y: 0, width: shot.size.width, height: statusBand)] + ignoring.map(onScreen), t: 0)
    }

    /// Turns a frame from the app's snapshot into the screenshot's points. They're the same on an iPhone. An iPhone app
    /// on an iPad runs in compatibility mode, in a window smaller than the screen, and there the snapshot's frames don't
    /// match the screen's, so the clock was blanked where it isn't (#73, item 2). XCUIElement's frames are the screen's,
    /// so the main window's frame from each gives the mapping.
    func screenMapping() -> (CGRect) -> CGRect {
        guard let root = try? app.snapshot() else { return { $0 } }
        let inSnapshot = Self.mainWindow(root)
        let windows = app.windows.allElementsBoundByIndex.map(\.frame)
        guard let onScreen = windows.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return { $0 } }
        return Self.mapping(from: inSnapshot, to: onScreen)
    }

    /// The map that takes rect `a` onto rect `b`; none when they're the same or either is empty.
    static func mapping(from a: CGRect, to b: CGRect) -> (CGRect) -> CGRect {
        guard a.width > 0, a.height > 0, b.width > 0, b.height > 0, a != b else { return { $0 } }
        let sx = b.width / a.width, sy = b.height / a.height
        return { r in
            r.isNull ? r : CGRect(x: b.minX + (r.minX - a.minX) * sx, y: b.minY + (r.minY - a.minY) * sy,
                                  width: r.width * sx, height: r.height * sy)
        }
    }

    /// How far past its accessibility frame the clock's label is blanked, in points. In landscape on an iPhone the drawn
    /// digits sat up to 5 points above the frame the snapshot gave (#172), so 4 points let each tick show.
    static let clockMargin: CGFloat = 8

    /// `frame` with `rect` (in points of a `screen`-sized screenshot, top down) painted black, out to whole pixels as
    /// ``thumbnail(_:width:blank:t:)`` paints it.
    static func blanking(_ rect: CGRect, in frame: FeelScreenFrame, screen: CGSize) -> FeelScreenFrame {
        guard !rect.isNull, !rect.isEmpty, screen.width > 0, screen.height > 0 else { return frame }
        let sx = CGFloat(frame.width) / screen.width, sy = CGFloat(frame.height) / screen.height
        let x0 = max(0, Int((rect.minX * sx).rounded(.down))), x1 = min(frame.width, Int((rect.maxX * sx).rounded(.up)))
        let y0 = max(0, Int((rect.minY * sy).rounded(.down))), y1 = min(frame.height, Int((rect.maxY * sy).rounded(.up)))
        guard x0 < x1, y0 < y1 else { return frame }
        var out = frame
        for y in y0..<y1 { for x in x0..<x1 { out.gray[y * frame.width + x] = 0 } }
        return out
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
            // Out to whole pixels: a rect that only partly covers a pixel would blend what is under it into the
            // thumbnail, so a ticking clock would still show at its edge (#73, landscape).
            for r in blank {
                let x0 = (r.minX * sx).rounded(.down), y0 = (r.minY * sy).rounded(.down)
                context.fill(CGRect(x: x0, y: y0, width: (r.maxX * sx).rounded(.up) - x0, height: (r.maxY * sy).rounded(.up) - y0))
            }
            return true
        }
        return drawn ? FeelScreenFrame(t: t, width: width, height: height, gray: gray) : nil
    }
}
#endif
