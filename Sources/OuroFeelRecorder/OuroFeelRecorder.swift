#if canImport(UIKit) && !os(watchOS)
public import Foundation
import OuroFeelCore
import QuartzCore
import UIKit

/// Ouro Feel's recorder inside the app: it films what the app draws, one sample per display frame, on the app's own
/// display clock. A UI test cannot film a transition itself, because XCUITest makes the test wait until the app is idle
/// after every tap, and by then the push or the sheet has landed. The recorder runs in the app, where nothing waits:
/// the test starts it with a Darwin notification, taps, stops it, and reads the film it wrote
/// (`OuroFeel.recordedFilm(_:timeout:during:)` on the test side).
///
/// Each sample is every accessibility element the test asked for (by identifier or label), at the place it is drawn
/// in that frame: its accessibility frame moved by however far its view's presentation layer is from the view's
/// model (an animating push moves the layer, not the view), and left out while its view is hidden or transparent.
///
/// Call ``installIfRequested(environment:)`` once at launch. It does nothing unless the UI test launched the app with
/// ``directoryVariable`` set, so a shipped app never records.
@MainActor
public enum OuroFeelRecorder {
    /// The launch environment key that holds the folder the test and the app share.
    public static let directoryVariable = "OURO_FEEL_RECORD_DIR"
    /// The Darwin notifications that start and stop a film.
    public static let startNotification = "bot.ouro.feel.record.start"
    public static let stopNotification = "bot.ouro.feel.record.stop"
    /// Files in the shared folder: the keys to watch (written by the test), the marker the app writes once it is
    /// recording, and the film it writes when it stops.
    public static let keysFile = "keys.json"
    public static let recordingFile = "recording"
    public static let filmFile = "film.json"

    static var recorder: Recorder?

    /// Starts listening for the test's start and stop, if the test asked for a recorder.
    public static func installIfRequested(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard recorder == nil, let path = environment[directoryVariable], !path.isEmpty else { return }
        recorder = Recorder(directory: URL(fileURLWithPath: path, isDirectory: true))
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(center, nil, recorderStarted, startNotification as CFString, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(center, nil, recorderStopped, stopNotification as CFString, nil, .deliverImmediately)
    }
}

// Not main-actor code: Darwin notifications may arrive on any thread, so the callbacks hop to the main queue themselves.
private let recorderStarted: CFNotificationCallback = { _, _, _, _, _ in
    DispatchQueue.main.async { MainActor.assumeIsolated { OuroFeelRecorder.recorder?.begin() } }
}
private let recorderStopped: CFNotificationCallback = { _, _, _, _, _ in
    DispatchQueue.main.async { MainActor.assumeIsolated { OuroFeelRecorder.recorder?.end() } }
}

@MainActor
final class Recorder: NSObject {
    let directory: URL
    /// The longest film, in frames (20 s at 60 Hz), so a test that never says stop cannot fill the disk.
    let cap = 1200
    private var link: CADisplayLink?
    private var wanted: Set<String> = []
    private var frames: [FeelFrame] = []
    private var start: CFTimeInterval?
    private var tail: Int?

    init(directory: URL) {
        self.directory = directory
    }

    func begin() {
        link?.invalidate()
        frames = []
        start = nil
        tail = nil
        let keys = (try? Data(contentsOf: directory.appendingPathComponent(OuroFeelRecorder.keysFile)))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        wanted = Set(keys)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        try? Data().write(to: directory.appendingPathComponent(OuroFeelRecorder.recordingFile))
    }

    /// Stops after `after` more frames, so the film holds the page coming to rest after the test's last step.
    func end(after: Int = 30) {
        guard link != nil else { return }
        tail = after
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let t0 = start ?? now
        start = t0
        frames.append(FeelFrame(t: now - t0, seen: sample()))
        if let left = tail {
            tail = left - 1
            if left <= 1 { finish() }
        } else if frames.count >= cap {
            finish()
        }
    }

    private func finish() {
        link?.invalidate()
        link = nil
        let window = windows.first.map { $0.convert($0.bounds, to: nil) } ?? .zero
        let film = FeelFilm(window: window, frames: frames,
                            timedBy: "the app's display (an in-app sample every frame, CADisplayLink)")
        let url = directory.appendingPathComponent(OuroFeelRecorder.filmFile)
        try? film.json.write(to: url, options: .atomic)
        frames = []
    }

    private var windows: [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { !$0.isHidden }
    }

    /// Where each view is drawn this frame, against where it is laid out: the offset of its presentation layer, and
    /// how opaque it is, both through all its ancestors. Nil when it is hidden.
    private var placements: [ObjectIdentifier: (dx: CGFloat, dy: CGFloat, opacity: Float)?] = [:]

    private func sample() -> [FeelSeen] {
        placements = [:]
        var seen: [FeelSeen] = []
        for window in windows { visit(window, depth: 0, into: &seen) }
        return seen
    }

    private func visit(_ object: NSObject, depth: Int, into seen: inout [FeelSeen]) {
        guard depth < 80 else { return }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return }
        let identifier = identifier(of: object)
        let label = object.accessibilityLabel ?? ""
        if object.isAccessibilityElement || !identifier.isEmpty {
            let key = identifier.isEmpty ? label : identifier
            if !key.isEmpty, wanted.isEmpty || wanted.contains(key) || wanted.contains(label), let frame = drawn(object) {
                seen.append(FeelSeen(key: key, label: label, frame: frame))
            }
        }
        if let elements = object.accessibilityElements as? [NSObject] {
            for element in elements { visit(element, depth: depth + 1, into: &seen) }
        } else if let view = object as? UIView {
            for sub in view.subviews { visit(sub, depth: depth + 1, into: &seen) }
        }
    }

    /// The element's identifier. SwiftUI's elements answer `accessibilityIdentifier` at run time without the Swift
    /// protocol saying so, so it is asked by selector.
    private func identifier(of object: NSObject) -> String {
        if let named = (object as? UIAccessibilityIdentification)?.accessibilityIdentifier { return named }
        let getter = NSSelectorFromString("accessibilityIdentifier")
        guard object.responds(to: getter) else { return "" }
        return object.perform(getter)?.takeUnretainedValue() as? String ?? ""
    }

    /// The element's frame on screen as drawn this frame, or nil while it is invisible.
    private func drawn(_ object: NSObject) -> CGRect? {
        let frame = object.accessibilityFrame
        guard frame.width > 0, frame.height > 0, let host = hostView(of: object) else { return nil }
        guard let placed = placement(of: host) else { return nil }
        guard placed.opacity >= 0.02 else { return nil }
        return frame.offsetBy(dx: placed.dx, dy: placed.dy)
    }

    private func hostView(of object: NSObject) -> UIView? {
        var current: Any? = object
        for _ in 0..<40 {
            if let view = current as? UIView { return view }
            // `accessibilityContainer` is on every element at run time, but Swift sees it only on some classes.
            let getter = NSSelectorFromString("accessibilityContainer")
            guard let object = current as? NSObject, object.responds(to: getter) else { return nil }
            current = object.perform(getter)?.takeUnretainedValue()
            if current == nil { return nil }
        }
        return nil
    }

    private func placement(of view: UIView) -> (dx: CGFloat, dy: CGFloat, opacity: Float)? {
        let id = ObjectIdentifier(view)
        if let cached = placements[id] { return cached }
        var result: (dx: CGFloat, dy: CGFloat, opacity: Float)?
        if let window = view.window {
            var opacity: Float = 1
            var hidden = false
            var layer: CALayer? = view.layer
            while let model = layer {
                let shown = model.presentation() ?? model
                if shown.isHidden { hidden = true; break }
                opacity *= shown.opacity
                layer = model.superlayer
            }
            if !hidden {
                let laidOut = view.convert(view.bounds, to: window)
                let shown = view.layer.presentation() ?? view.layer
                let windowShown = window.layer.presentation() ?? window.layer
                let drawn = shown.convert(shown.bounds, to: windowShown)
                result = (drawn.minX - laidOut.minX, drawn.minY - laidOut.minY, opacity)
            }
        }
        placements[id] = result
        return result
    }
}
#endif
