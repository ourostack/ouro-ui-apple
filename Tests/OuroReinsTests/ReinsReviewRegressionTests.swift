import Foundation
import OuroAX
@testable import OuroReins
import Testing

// Regressions for the independent review of PR #20: each test names the finding it pins.

private struct Tree: ReinsInput { let name: String; let kids: [Tree] }
private struct Linked: ReinsInput { let name: String; let next: Box? }
private final class Box: Decodable, @unchecked Sendable { let inner: Linked? }
private enum Plain: String, Codable { case one, two }
private struct WithPlain: ReinsInput { let plain: Plain }
private struct Kinds: ReinsInput {
    let tags: [String: Int]
    let price: Decimal
    let when: Date
    let link: URL
    let token: UUID
    let blob: Data
}

private struct TaggedID: RawRepresentable, Codable, Sendable { let rawValue: String }
private enum Level: Int, Codable { case low, high }
private struct Wrappers: ReinsInput { let id: TaggedID; let level: Level }

@Suite("Review regressions: schemas")
struct ReviewSchemaTests {
    @Test("raw-value wrappers and Int enums still derive; only a failing String enum gets the ReinsEnumerable hint")
    func rawValueTypes() {
        #expect(Wrappers.reinsSchema == .object(properties: ["id": .string, "level": .integer], required: ["id", "level"]))
    }

    @Test("a recursive input is underived with a reason, not a crash")
    func recursiveTypes() {
        guard case .underived(let reason) = Tree.reinsSchema else { Issue.record("expected underived"); return }
        #expect(reason.contains("contains itself"))
        guard case .underived = Linked.reinsSchema else { Issue.record("expected underived through an optional class"); return }
    }

    @Test("a raw-value enum that isn't ReinsEnumerable says to conform it")
    func rawEnumMessage() {
        guard case .underived(let reason) = WithPlain.reinsSchema else { Issue.record("expected underived"); return }
        #expect(reason.contains("ReinsEnumerable"))
    }

    @Test("dictionaries, Decimal, Date, URL, UUID and Data derive schemas the decoder accepts")
    func kinds() throws {
        let schema = Kinds.reinsSchema
        let json = schema.json
        #expect(json["properties"]?["tags"] == ["type": "object", "additionalProperties": ["type": "integer"]])
        #expect(json["properties"]?["price"] == ["type": "number"])
        #expect(json["properties"]?["when"]?["format"] == "date-time")
        #expect(json["properties"]?["link"]?["format"] == "uri")
        #expect(json["properties"]?["token"]?["format"] == "uuid")
        #expect(json["properties"]?["blob"]?["contentEncoding"] == "base64")
        let input: ReinsValue = [
            "tags": ["a": 1, "b": 2], "price": 9.5, "when": "2026-11-05T12:00:00Z", "link": "https://spoonjoy.app",
            "token": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "blob": "aGk=",
        ]
        #expect(schema.problems(in: input).isEmpty)
        let decoded = try input.decode(as: Kinds.self)
        #expect(decoded.tags["b"] == 2)
        #expect(decoded.blob == Data("hi".utf8))
        #expect(schema.problems(in: ["tags": ["a": "x"], "price": 1, "when": "yesterday", "link": "x", "token": "nope", "blob": "aGk="]) == [
            "$.tags.a: expected an integer, got string",
            "$.token: \"nope\" isn't a valid uuid string",
            "$.when: \"yesterday\" isn't a valid date-time string",
        ])
    }

    @Test("an integer too large to hold exactly is refused as invalid input")
    func hugeIntegers() {
        #expect(ReinsSchema.integer.problems(in: .number(1e300)) == ["$: expected an integer, got 1e+300"])
    }
}

@MainActor
private final class Gauge: ReinsDrivable {
    var reinsNode: ReinsNode {
        .stack(depth: 1, goBack: {}, child: .stack(depth: 0, goBack: {}, child: ReinsNode("gauge", state: ["ratio": .number(.nan)])))
    }
}

@MainActor
@Suite("Review regressions: wire")
struct ReviewWireTests {
    @Test("a NaN in state encodes as null and never empties the reply")
    func nonFinite() async throws {
        let reply = try #require(await ReinsWire.handle("ls", session: ReinsSession(Gauge())))
        #expect(try ReinsValue(json: reply)["screen"]?["state"]?["ratio"] == .null)
    }

    @Test("a JSON request with a bad op or missing action keeps its id")
    func idSurvivesParseFailures() async throws {
        let session = ReinsSession(Gauge())
        let badOp = try ReinsValue(json: try #require(await ReinsWire.handle(#"{"id":5,"op":"jump"}"#, session: session)))
        #expect(badOp["id"] == 5)
        #expect(badOp["error"]?["code"] == "bad-request")
        let noAction = try ReinsValue(json: try #require(await ReinsWire.handle(#"{"id":"x","op":"do"}"#, session: session)))
        #expect(noAction["id"] == "x")
    }

    @Test("nested navigators of the same name get distinct context keys")
    func nestedContext() {
        let screen = ReinsSession(Gauge()).ls()
        #expect(screen.path == ["stack", "stack.2", "gauge"])
        #expect(screen.context["stack"]?["depth"] == 1)
        #expect(screen.context["stack.2"]?["depth"] == 0)
        #expect(screen.actions.first { $0.name == "goBack" }?.from == "stack")
    }

    @Test("lines split at \\n only, so a JSON string holding U+2028 stays one request")
    func lineSplitting() async throws {
        let bytes = Array("ls\r\n{\"id\":1,\"op\":\"ls\",\"note\":\"a\u{2028}b\"}\nhelp".utf8)
        var lines: [String] = []
        for try await line in ReinsWire.lines(AsyncBytes(bytes)) { lines.append(line) }
        #expect(lines == ["ls", "{\"id\":1,\"op\":\"ls\",\"note\":\"a\u{2028}b\"}", "help"])
    }
}

private struct AsyncBytes: AsyncSequence, Sendable {
    typealias Element = UInt8
    let bytes: [UInt8]
    init(_ bytes: [UInt8]) { self.bytes = bytes }
    struct AsyncIterator: AsyncIteratorProtocol {
        var index = 0
        let bytes: [UInt8]
        mutating func next() async -> UInt8? {
            guard index < bytes.count else { return nil }
            defer { index += 1 }
            return bytes[index]
        }
    }
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(bytes: bytes) }
}

// In the serialized guard suite: the guard is process-wide, so no other guard test may run beside these.
extension NetworkGuardTests {
    @MainActor
    @Test("two main-actor journeys that both block the network take turns instead of deadlocking", .timeLimit(.minutes(1)))
    func mainActorGuardsTakeTurns() async throws {
        let log = Log()
        let first = Task { @MainActor in
            try await ReinsNetworkGuard.withNetworkBlocked {
                log.order.append("first in")
                try await Task.sleep(for: .milliseconds(50))
                log.order.append("first out")
            }
        }
        let second = Task { @MainActor in
            try await ReinsNetworkGuard.withNetworkBlocked {
                log.order.append("second in")
                try await Task.sleep(for: .milliseconds(10))
                log.order.append("second out")
            }
        }
        try await first.value
        try await second.value
        let order = log.order
        #expect(order.count == 4)
        #expect(order[0].hasSuffix("in") && order[1].hasSuffix("out") && order[2].hasSuffix("in") && order[3].hasSuffix("out"),
                "one guard at a time: \(order)")
    }

    @MainActor private final class Log { var order: [String] = [] }

    @Test("file: URLs load under the guard and aren't recorded")
    func fileURLsPass() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("reins-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: file)
        try await ReinsNetworkGuard.withNetworkBlocked {
            let (data, _) = try await URLSession.shared.data(from: file)
            #expect(data == Data("{}".utf8))
        }
    }
}

#if DEBUG && canImport(Darwin)
@MainActor
private final class Slow: ReinsDrivable {
    var reinsNode: ReinsNode {
        ReinsNode("slow", actions: [ReinsAction("wait", "Takes a moment") { try await Task.sleep(for: .milliseconds(200)) }])
    }
}

@Suite("Review regressions: debug socket")
struct ReviewSocketTests {
    @MainActor
    @Test("a client that hangs up before its reply doesn't kill the process, and the server keeps serving")
    func hangUpBeforeReply() async throws {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("reins-\(UUID().uuidString.prefix(8)).sock")
        let server = ReinsSocketServer(session: ReinsSession(Slow()), path: path)
        try server.start()
        defer { server.stop() }
        try await Task.detached {
            let fd = try Self.connect(path)
            let out = Array("do wait\n".utf8)
            _ = out.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            close(fd)
        }.value
        try await Task.sleep(for: .milliseconds(400))
        let reply = try await Task.detached { () throws -> String in
            let fd = try Self.connect(path)
            defer { close(fd) }
            let out = Array("ls".utf8)  // no newline: answered at end of input
            _ = out.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            shutdown(fd, SHUT_WR)
            var buffer = [UInt8](repeating: 0, count: 65536)
            var data: [UInt8] = []
            while true {
                let n = read(fd, &buffer, buffer.count)
                guard n > 0 else { break }
                data += buffer[0..<n]
            }
            return String(decoding: data, as: UTF8.self)
        }.value
        #expect(reply.contains(#""focus":"slow""#))
    }

    @MainActor
    @Test("start refuses a path that's too long, a non-socket file at the path, and a second start")
    func startRefusals() throws {
        let long = "/tmp/" + String(repeating: "x", count: 120) + ".sock"
        #expect(throws: POSIXError(.ENAMETOOLONG)) { try ReinsSocketServer(session: ReinsSession(Slow()), path: long).start() }

        let file = (NSTemporaryDirectory() as NSString).appendingPathComponent("reins-\(UUID().uuidString.prefix(8)).txt")
        try Data("keep me".utf8).write(to: URL(fileURLWithPath: file))
        #expect(throws: POSIXError(.EADDRINUSE)) { try ReinsSocketServer(session: ReinsSession(Slow()), path: file).start() }
        #expect(FileManager.default.contents(atPath: file) == Data("keep me".utf8))

        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("reins-\(UUID().uuidString.prefix(8)).sock")
        let server = ReinsSocketServer(session: ReinsSession(Slow()), path: path)
        try server.start()
        defer { server.stop() }
        #expect(throws: POSIXError(.EALREADY)) { try server.start() }
        #expect(throws: POSIXError(.EADDRINUSE), "a second app must not take over a live server's socket") {
            try ReinsSocketServer(session: ReinsSession(Slow()), path: path).start()
        }
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test("the default path fits a socket address")
    func defaultPathFits() {
        #expect(ReinsSocketServer.defaultPath.utf8.count <= ReinsSocketServer.maximumPathBytes)
    }

    nonisolated private static func connect(_ path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { close(fd); throw POSIXError(.ECONNREFUSED) }
        return fd
    }
}
#endif
