#if canImport(XCTest)
public import Foundation
public import OuroDeviceHub
public import XCTest

/// Folds, opens and turns the iPhone Duo simulator from inside a UI test, through a Mac running
/// `ouro-devicehub serve <dir>`. Generalized from Spoonjoy's `DuoHinge`: the environment variable and timeout are
/// yours to set, and app-specific requests go through ``send(_:file:line:)``.
@MainActor
public final class OuroDuoHinge {
    public enum Posture: String, Sendable {
        case closed = "Closed"
        case open = "Open"
        case partiallyOpen = "Partially Open"
    }

    /// A press reopens Device Hub, finds the button and waits eight seconds for the simulator to settle.
    public var timeout: TimeInterval
    private var channel: OuroDuoRequests

    /// - Parameter variable: the environment variable holding the request directory. Pass it to the test runner as
    ///   `TEST_RUNNER_<variable>`.
    public init(variable: String = OuroDuoRequests.defaultVariable, timeout: TimeInterval = 90) throws {
        self.timeout = timeout
        channel = OuroDuoRequests(directory: try OuroDuoRequests.directory(variable: variable))
    }

    public func set(_ posture: Posture, file: StaticString = #filePath, line: UInt = #line) throws {
        try send(posture.rawValue, file: file, line: line)
    }

    /// A quarter turn clockwise, as Device Hub's Rotate Right. `XCUIDevice.orientation` does not turn the inner screen.
    public func rotateRight(file: StaticString = #filePath, line: UInt = #line) throws {
        try send("Rotate Right", file: file, line: line)
    }

    /// The Mac's screenshot of every Duo display, saved as `shots/<name>.png` in the request directory.
    public func shot(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try send("shot \(name)", file: file, line: line)
    }

    /// Sends any request and fails the test unless the driver answers "ok" within ``timeout``.
    public func send(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let request = try channel.write(text)
        let path = request.done.path
        let answered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: path) }, object: nil)
        let waited = XCTWaiter().wait(for: [answered], timeout: timeout)
        XCTAssertEqual(waited, .completed, "The posture driver did not answer \"\(text)\" within \(Int(timeout)) seconds.", file: file, line: line)
        guard waited == .completed else { return }
        XCTAssertEqual(try OuroDuoRequests.outcome(of: request), "ok", "The posture driver could not do \"\(text)\".", file: file, line: line)
    }
}
#endif
