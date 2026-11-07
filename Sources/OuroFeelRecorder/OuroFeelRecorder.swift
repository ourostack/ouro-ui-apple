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
/// in that frame: its accessibility frame mapped from where its view is laid out to where the view's presentation
/// layer draws it (an animating push or sheet moves and scales the layer, not the view), and left out while a layer
/// above it is hidden or transparent. That covers UIKit-level motion: pushes, sheets, zooms, `UIView` animations.
/// Effects SwiftUI applies inside its hosting view (`.offset`, `.scaleEffect`, `.opacity`) show only as far as SwiftUI
/// moves the element's accessibility frame, so judge those with an identifier on the moving view itself.
///
/// Call ``installIfRequested(environment:)`` once at launch. It does nothing unless the UI test launched the app with
/// ``directoryVariable`` set, so a shipped app never records.
@MainActor
public enum OuroFeelRecorder {
    /// The names the test and the app share (``FeelRecording``).
    public static let directoryVariable = FeelRecording.directoryVariable

    static var recorder: Recorder?

    /// Starts listening for the test's start and stop, if the test asked for a recorder.
    public static func installIfRequested(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard recorder == nil, let path = environment[directoryVariable], !path.isEmpty else { return }
        recorder = Recorder(directory: URL(fileURLWithPath: path, isDirectory: true))
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(center, nil, recorderStarted, FeelRecording.startNotification as CFString, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(center, nil, recorderStopped, FeelRecording.stopNotification as CFString, nil, .deliverImmediately)
    }
}

/// Called when the injectable recorder library is loaded into an app (`OuroFeelRecorderInjectable`, see
/// `OuroFeel.injectedRecorderEnvironment`): installs the recorder on the main queue once the app is running.
@_cdecl("ouro_feel_recorder_install_when_launched")
public func ouroFeelRecorderInstallWhenLaunched() {
    DispatchQueue.main.async { MainActor.assumeIsolated { OuroFeelRecorder.installIfRequested() } }
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
    /// The longest film, in seconds, so a test that never says stop cannot fill the disk. A film cut here is marked
    /// stalled at its last frame, so no check passes on what came after.
    let cap: CFTimeInterval = 20
    private var link: CADisplayLink?
    private var wanted: Set<String> = []
    private var copies = false
    private var id = ""
    private var frames: [FeelFrame] = []
    private var start: CFTimeInterval?

    init(directory: URL) {
        self.directory = directory
    }

    func begin() {
        link?.invalidate()
        frames = []
        start = nil
        stopAt = nil
        stillSince = nil
        // No readable request, no film: recording every element every frame would slow the app it films.
        guard let request = (try? Data(contentsOf: directory.appendingPathComponent(FeelRecording.requestFile)))
            .flatMap({ try? JSONDecoder().decode(FeelRecording.Request.self, from: $0) }) else { return }
        id = request.id
        wanted = Set(request.keys)
        copies = request.copies
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        try? Data().write(to: directory.appendingPathComponent(FeelRecording.recordingFile(id)))
    }

    /// How long everything filmed must hold still after the test says stop before the film ends: a tap can return
    /// to the test while its transition is still moving, so the film waits for the page to come to rest.
    let restAfterStop: CFTimeInterval = 0.5
    private var stopAt: CFTimeInterval?
    private var stillSince: CFTimeInterval?

    /// Ends the film once what it watches has held still for ``restAfterStop`` (or the cap is reached).
    func end() {
        guard let link else { return }
        stopAt = link.timestamp
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let t0 = start ?? now
        start = t0
        let seen = sample()
        if !Self.holdsStill(from: frames.last?.seen, to: seen) { stillSince = now }
        frames.append(FeelFrame(t: now - t0, seen: seen))
        if now - t0 >= cap {
            finish(stalledAt: now - t0)
        } else if let stopAt, now - max(stopAt, stillSince ?? t0) >= restAfterStop || now - stopAt >= tailAfterStop {
            // At rest, or something watched never rests (a spinner, a ticking label): the film ends unstalled, and a
            // check on an element still moving says so.
            finish()
        }
    }

    /// The longest a film runs on after the test says stop.
    let tailAfterStop: CFTimeInterval = 3

    /// The same elements, none moved more than the half point the checks allow.
    static func holdsStill(from a: [FeelSeen]?, to b: [FeelSeen]) -> Bool {
        guard let a, a.count == b.count else { return false }
        return zip(a, b).allSatisfy { $0.key == $1.key && FeelFilm.distance($0.frame, $1.frame) <= 0.5 }
    }

    private func finish(stalledAt: Double? = nil) {
        link?.invalidate()
        link = nil
        // In screen coordinates, as accessibility frames are.
        let window = windows.first.map { $0.convert($0.bounds, to: $0.screen.coordinateSpace) } ?? .zero
        let film = FeelFilm(window: window, frames: frames, stalledAt: stalledAt,
                            timedBy: FeelRecording.timedBy)
        let url = directory.appendingPathComponent(FeelRecording.filmFile(id))
        try? film.json.write(to: url, options: .atomic)
        frames = []
    }

    private var windows: [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { !$0.isHidden }
    }

    /// How opaque each view is drawn this frame, through all its ancestors' presentation layers; nil when hidden.
    private var opacities: [ObjectIdentifier: Float?] = [:]

    /// One sample per key, unless the request asks for every copy: where a key shows twice (the same title on both pages of a push), the one the walk reaches
    /// last, which is the frontmost among sibling views (not always across windows or a custom reading order). Track by
    /// identifier where a label can repeat.
    private func sample() -> [FeelSeen] {
        opacities = [:]
        var seen: [FeelSeen] = []
        for window in windows { visit(window, depth: 0, into: &seen) }
        if copies { return seen }  // Every copy, for double draws.
        var last: [String: Int] = [:]
        for (i, s) in seen.enumerated() { last[s.key] = i }
        return seen.enumerated().filter { last[$0.element.key] == $0.offset }.map(\.element)
    }

    private func visit(_ object: NSObject, depth: Int, into seen: inout [FeelSeen]) {
        guard depth < 80 else { return }
        // The presentation layer, not the model: a view fading out has its model alpha at 0 while it is still drawn.
        if let view = object as? UIView {
            let shown = view.layer.presentation() ?? view.layer
            if shown.isHidden || shown.opacity < 0.01 { return }
        }
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
        } else if !(object is UIView) || (object as? UIView)?.subviews.isEmpty == true,
                  case let count = object.accessibilityElementCount(), count > 0, count != NSNotFound {
            // A container that lists its children only by count and index.
            for i in 0..<count {
                if let element = object.accessibilityElement(at: i) as? NSObject { visit(element, depth: depth + 1, into: &seen) }
            }
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

    /// The element's frame on screen as drawn this frame, or nil while it is invisible: its accessibility frame (in
    /// screen coordinates, where the view is laid out) carried through the presentation layers to where it is drawn,
    /// so a scale or zoom moves and sizes it as well as a slide.
    private func drawn(_ object: NSObject) -> CGRect? {
        let frame = object.accessibilityFrame
        guard frame.width > 0, frame.height > 0, let host = hostView(of: object), let window = host.window else { return nil }
        guard let opacity = opacity(of: host), opacity >= 0.02 else { return nil }
        let screen = window.screen.coordinateSpace
        let local = host.convert(window.convert(frame, from: screen), from: window)
        let shown = host.layer.presentation() ?? host.layer
        let windowShown = window.layer.presentation() ?? window.layer
        return window.convert(shown.convert(local, to: windowShown), to: screen)
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

    private func opacity(of view: UIView) -> Float? {
        let id = ObjectIdentifier(view)
        if let cached = opacities[id] { return cached }
        var opacity: Float? = 1
        var layer: CALayer? = view.layer
        while let model = layer, let so_far = opacity {
            let shown = model.presentation() ?? model
            opacity = shown.isHidden ? nil : so_far * shown.opacity
            layer = model.superlayer
        }
        opacities[id] = opacity
        return opacity
    }
}
#endif
