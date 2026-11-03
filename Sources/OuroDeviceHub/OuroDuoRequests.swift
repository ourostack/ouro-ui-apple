import Foundation

/// The file protocol between a UI test on the iPhone Duo simulator and the Mac that moves its hinge. Only Device Hub,
/// on the Mac, can fold the simulator, so the test writes `NN.request` holding what to do ("Partially Open", "Rotate
/// Right", "shot <name>") and waits for `NN.done` holding "ok" or why not. From Spoonjoy's `DuoHinge`.
public struct OuroDuoRequests: Sendable {
    public static let defaultVariable = "OURO_DUO_POSTURE_DIR"

    public struct Request: Equatable, Sendable {
        public var request: URL
        public var done: URL
        public var text: String
    }

    public struct MissingDirectory: Error, CustomStringConvertible {
        public let variable: String
        public var description: String {
            "\(variable) is not set. Pass the driver's request directory to the test as TEST_RUNNER_\(variable)."
        }
    }

    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// The request directory named by `variable` in `environment`.
    public static func directory(variable: String = defaultVariable, in environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        guard let path = environment[variable], !path.isEmpty else { throw MissingDirectory(variable: variable) }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Writes the next numbered request, one past the highest already in the directory, so a second channel (a new
    /// test's `OuroDuoHinge`) never reuses a number an earlier request was answered under.
    public mutating func write(_ text: String) throws -> Request {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let sequence = (names.compactMap { $0.hasSuffix(".request") ? Int($0.dropLast(8)) : nil }.max() ?? 0) + 1
        let base = directory.appendingPathComponent(String(format: "%02d", sequence))
        let request = Request(request: base.appendingPathExtension("request"), done: base.appendingPathExtension("done"), text: text)
        try Data(text.utf8).write(to: request.request, options: .atomic)
        return request
    }

    /// Requests with no answer yet, oldest first.
    public static func pending(in directory: URL) -> [Request] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".request") }.sorted().compactMap { name in
            let request = directory.appendingPathComponent(name)
            let done = request.deletingPathExtension().appendingPathExtension("done")
            guard !FileManager.default.fileExists(atPath: done.path),
                  let text = try? String(contentsOf: request, encoding: .utf8) else { return nil }
            return Request(request: request, done: done, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public static func answer(_ request: Request, _ outcome: String) throws {
        try Data((outcome + "\n").utf8).write(to: request.done, options: .atomic)
    }

    public static func outcome(of request: Request) throws -> String {
        try String(contentsOf: request.done, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The Mac side: answers pending requests by pressing Device Hub's buttons.
public enum OuroDuoDriver {
    /// The Device Hub buttons a request may press.
    public static let buttons: Set<String> = ["Open", "Closed", "Partially Open", "Rotate Right", "Rotate Left"]

    /// Answers every pending request with `press` (a Device Hub button) and returns how many it answered. Other
    /// requests (an app's own, like Spoonjoy's "session") are answered "unsupported" so the test fails fast instead
    /// of waiting out its timeout.
    @discardableResult
    public static func handlePending(in directory: URL, press: (String) -> Bool) -> Int {
        var handled = 0
        for request in OuroDuoRequests.pending(in: directory) {
            let outcome: String
            if buttons.contains(request.text) {
                outcome = press(request.text) ? "ok" : "failed: could not press \(request.text)"
            } else if request.text.hasPrefix("shot ") {
                outcome = shot(String(request.text.dropFirst(5)), in: directory)
            } else {
                outcome = "unsupported: \(request.text)"
            }
            if (try? OuroDuoRequests.answer(request, outcome)) != nil { handled += 1 }
        }
        return handled
    }

    /// Saves the Mac's screenshot (every Duo display) as `shots/<name>.png` beside the requests.
    static func shot(_ name: String, in directory: URL) -> String {
        #if os(macOS)
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let shots = directory.appendingPathComponent("shots")
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", shots.appendingPathComponent("\(safe).png").path]
        do { try p.run() } catch { return "failed: \(error.localizedDescription)" }
        p.waitUntilExit()
        return p.terminationStatus == 0 ? "ok" : "failed: screencapture exited \(p.terminationStatus)"
        #else
        return "unsupported: shots need the Mac"
        #endif
    }
}
