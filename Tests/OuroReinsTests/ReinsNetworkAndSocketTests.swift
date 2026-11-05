import Foundation
import OuroAX
@testable import OuroReins
import Testing

/// The guard is process-wide, so these run one at a time. No request here can reach the network: every URL is under
/// `.invalid` (RFC 2606), and every request is made while a guard is active or through a blocking configuration.
@Suite("Network guard", .serialized)
struct NetworkGuardTests {
    private static let url = URL(string: "https://reins-guard.example.invalid/v1/recipes?page=1")!

    private static func load(_ session: URLSession, _ url: URL = url) async -> (any Error)? {
        do {
            _ = try await session.data(from: url)
            return nil
        } catch {
            return error
        }
    }

    @Test("URLSession.shared fails at once, and the attempt is recorded even though the app caught the error")
    func sharedSessionIsBlocked() async throws {
        let guardrail = ReinsNetworkGuard.begin()
        defer { guardrail.end() }
        let error = await Self.load(.shared)
        #expect((error as? URLError)?.code == .notConnectedToInternet)
        #expect(guardrail.attempts == [.init(method: "GET", url: Self.url.absoluteString)])
        #expect(throws: (any Error).self) { try guardrail.check() }
        do {
            try guardrail.check()
        } catch let problem as OuroAX.Problem {
            #expect(problem.code == "network-attempted")
            #expect(problem.message == "behavior session: 1 network request attempted: GET \(Self.url.absoluteString). Fix: inject a fixture for each one through the type's constructor.")
        }
    }

    @Test("sessions made from .default and .ephemeral while the guard is active are blocked and recorded too")
    func freshDefaultSessionsAreBlocked() async {
        let guardrail = ReinsNetworkGuard.begin()
        defer { guardrail.end() }
        for configuration in [URLSessionConfiguration.default, .ephemeral] {
            let error = await Self.load(URLSession(configuration: configuration))
            #expect((error as? URLError)?.code == .notConnectedToInternet)
        }
        #expect(guardrail.attempts.count == 2)
    }

    @Test("a session from a blocking configuration fails even with no guard active")
    func blockingConfigurationAlwaysFails() async {
        let session = URLSession(configuration: ReinsNetworkGuard.blocking())
        let error = await Self.load(session)
        #expect((error as? URLError)?.code == .notConnectedToInternet)
        #expect(!ReinsNetworkGuard.isActive)
    }

    @Test("withNetworkBlocked throws network-attempted after the body, and passes a clean body's result through")
    func withNetworkBlocked() async throws {
        let clean = try await ReinsNetworkGuard.withNetworkBlocked { 42 }
        #expect(clean == 42)
        await #expect(throws: OuroAX.Problem.self) {
            try await ReinsNetworkGuard.withNetworkBlocked {
                _ = await Self.load(.shared)
            }
        }
        #expect(!ReinsNetworkGuard.isActive, "the guard ends even when the body's attempt throws")
    }

    @Test("ending the guard returns its attempts and clears them")
    func endClears() async {
        let guardrail = ReinsNetworkGuard.begin()
        _ = await Self.load(URLSession(configuration: ReinsNetworkGuard.blocking()))
        #expect(guardrail.end().count == 1)
        #expect(guardrail.attempts.isEmpty)
        #expect(guardrail.end().isEmpty, "a second end is harmless")
        let after = URLSessionConfiguration.default.protocolClasses ?? []
        #expect(!after.contains { $0 == ReinsBlockingURLProtocol.self }, "with no guard active, .default is the system's own")
    }
}

#if DEBUG && canImport(Darwin)
@MainActor
private final class Tally: ReinsDrivable {
    var count = 0
    var reinsNode: ReinsNode {
        ReinsNode("tally", state: ["count": .number(Double(count))], actions: [
            ReinsAction("bump", "Add one") { [unowned self] in self.count += 1 },
        ])
    }
}

@Suite("Debug socket")
struct SocketTests {
    @MainActor
    @Test("serves the line protocol on a Unix socket and removes it on stop")
    func servesLines() async throws {
        let tally = Tally()
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("reins-\(UUID().uuidString.prefix(8)).sock")
        let server = ReinsSocketServer(session: ReinsSession(tally), path: path)
        try server.start()
        #expect(FileManager.default.fileExists(atPath: path))

        let replies = try await Task.detached { try Self.exchange(path: path, lines: ["ls", "do bump", "do nope"]) }.value
        #expect(replies.count == 3)
        #expect(try ReinsValue(json: replies[0])["screen"]?["focus"] == "tally")
        #expect(try ReinsValue(json: replies[1])["screen"]?["state"]?["count"] == 1)
        #expect(try ReinsValue(json: replies[2])["error"]?["code"] == "action-unavailable")
        #expect(tally.count == 1, "the socket drives the same object the screen is bound to")

        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    /// A blocking client, as `nc -U` is: sends each line and reads one reply line for it.
    nonisolated private static func exchange(path: String, lines: [String]) throws -> [String] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }
        var replies: [String] = []
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        for line in lines {
            let out = Array((line + "\n").utf8)
            _ = out.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            while !pending.contains(UInt8(ascii: "\n")) {
                let n = read(fd, &buffer, buffer.count)
                guard n > 0 else { throw POSIXError(.ECONNRESET) }
                pending.append(contentsOf: buffer[0..<n])
            }
            let newline = pending.firstIndex(of: UInt8(ascii: "\n"))!
            replies.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
            pending.removeSubrange(pending.startIndex...newline)
        }
        return replies
    }
}
#endif
