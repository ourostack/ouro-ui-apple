import OuroHX
import SwiftUI
import os
#if canImport(UIKit)
import UIKit
#endif

/// Hitch measurement for the gallery's UI tests, on only with `-probe 1`.
///
/// A display link times every frame. A frame that arrives later than one refresh interval (plus a quarter for timer
/// jitter) is a hitch, and the time past its interval is hitch time. The hitch ratio is hitch milliseconds per second
/// of measured time, Apple's measure: under 5 ms/s is good, over 10 is critical, so any above 5 fails a test.
///
/// The app opens the window itself (see `GalleryApp`), so the test need not touch the app while it measures, and the
/// test reads the result from the "probe" element's label: `frames=…;hitches=…;hitchMs=…;seconds=…;ratio=…;worstMs=…;worstFrames=…;log=<ms in>:+<ms late>,…`. Each window is also an
/// os_signpost animation interval (subsystem `bot.ouro.hx.gallery`, category `motion`, name `transition`) for
/// `XCTOSSignpostMetric` on a device.
@MainActor
final class FrameProbe: NSObject, ObservableObject {
    static var isOn: Bool { UserDefaults.standard.integer(forKey: "probe") > 0 }
    static let log = OSLog(subsystem: "bot.ouro.hx.gallery", category: "motion")

    @Published private(set) var summary = "idle"
    /// When each hitch came, in milliseconds from the start, and how late it was.
    private(set) var hitchLog: [String] = []
    private var measuring = false
    private var last: CFTimeInterval?
    private var frames = 0
    private var hitches = 0
    private var hitchTime: CFTimeInterval = 0
    private var worst: CFTimeInterval = 0
    /// The worst lateness in refresh intervals, so a limit holds at 60 Hz and 120 Hz alike.
    private var worstFrames: Double = 0
    private var began: CFTimeInterval = 0
    private var signpost: OSSignpostID?
    #if canImport(UIKit)
    private var link: CADisplayLink?
    #endif

    func start() {
        frames = 0; hitches = 0; hitchTime = 0; worst = 0; worstFrames = 0; last = nil; hitchLog = []
        began = CACurrentMediaTime()
        measuring = true
        summary = "measuring"
        let id = OSSignpostID(log: Self.log)
        signpost = id
        os_signpost(.animationBegin, log: Self.log, name: "transition", signpostID: id)
        #if canImport(UIKit)
        if link == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        #endif
    }

    func stop() {
        measuring = false
        #if canImport(UIKit)
        link?.invalidate()
        link = nil
        #endif
        if let signpost { os_signpost(.end, log: Self.log, name: "transition", signpostID: signpost) }
        let seconds = max(0.001, CACurrentMediaTime() - began)
        let ratio = hitchTime * 1000 / seconds
        summary = String(format: "frames=%d;hitches=%d;hitchMs=%.1f;seconds=%.2f;ratio=%.2f;worstMs=%.1f;worstFrames=%.2f", frames, hitches, hitchTime * 1000, seconds, ratio, worst * 1000, worstFrames)
            + ";log=" + hitchLog.joined(separator: ",")
    }

    #if canImport(UIKit)
    @objc private func tick(_ link: CADisplayLink) {
        guard measuring else { last = nil; return }
        let now = link.timestamp
        let interval = link.targetTimestamp - link.timestamp
        if let last, interval > 0 {
            let late = (now - last) - interval
            if late > interval * 0.25 {
                hitches += 1
                hitchTime += late
                hitchLog.append(String(format: "%.0f:+%.1f", (now - began) * 1000, late * 1000))
                worst = max(worst, late)
                worstFrames = max(worstFrames, late / interval)
            }
        }
        last = now
        frames += 1
    }
    #endif
}

/// The probe's near-invisible readout, drawn only with `-probe 1`.
struct FrameProbeControls: View {
    @ObservedObject var probe: FrameProbe

    var body: some View {
        Text(probe.summary).accessibilityIdentifier("probe")
        .font(.system(size: 6))
        .opacity(0.02)
        .frame(height: 8)
    }
}
