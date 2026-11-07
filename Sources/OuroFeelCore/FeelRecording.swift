import Foundation

/// What a UI test and the in-app recorder (`OuroFeelRecorder`) agree on: the launch variable naming the folder they
/// share, the Darwin notifications that start and stop a film, and the files in that folder.
public enum FeelRecording {
    /// The launch environment key that holds the shared folder.
    public static let directoryVariable = "OURO_FEEL_RECORD_DIR"
    public static let startNotification = "bot.ouro.feel.record.start"
    public static let stopNotification = "bot.ouro.feel.record.stop"
    /// The request the test writes before it posts start.
    public static let requestFile = "request.json"
    /// The marker the app writes once it is recording, and the film it writes when it stops. Both carry the request's
    /// id, so a film that a timed-out request finishes late is never read as the next request's.
    public static func recordingFile(_ id: String) -> String { "recording-\(id)" }
    public static func filmFile(_ id: String) -> String { "film-\(id).json" }
    public static let timedBy = "the app's display (an in-app sample every frame, CADisplayLink)"

    /// What the test asks the app to film.
    public struct Request: Codable, Equatable, Sendable {
        public var id: String
        public var keys: [String]
        public init(id: String = UUID().uuidString, keys: [String]) {
            self.id = id
            self.keys = keys
        }
    }
}
