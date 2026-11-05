import Foundation
public import OuroAX

/// The line protocol, the same on stdin and stdout, the debug socket and in tests.
///
/// Each request is one line, as JSON or as text:
///
/// ```
/// ls
/// do openRecipe {"id":"r1"}
/// {"id":1,"op":"ls"}
/// {"id":2,"op":"do","action":"openRecipe","input":{"id":"r1"}}
/// ```
///
/// Each reply is one line of JSON with sorted keys: `{"id":…,"ok":true,"screen":{…}}`, or with `"ok":false` and an
/// `"error"` in Ouro AX's problem shape. `id` is echoed when the request had one. A blank line or one starting with `#`
/// gets no reply.
public enum ReinsWire {
    /// Handles one request line; nil for a blank or comment line.
    @MainActor
    public static func handle(_ line: String, session: ReinsSession) async -> String? {
        await respond(line, session: session).map(encode)
    }

    /// What `help` answers: the protocol in a few lines, so an agent that finds the socket can learn it from the socket.
    public static let help: [String] = [
        "ls: the focused screen: focus, path, state, context (ancestor states) and actions (with input JSON Schema)",
        "do <action> [json]: run an action on the focused screen; refused with the valid actions when it isn't offered",
        #"JSON form: {"id":1,"op":"ls"} or {"id":2,"op":"do","action":"<name>","input":{...}}; id is echoed"#,
        "every reply is one JSON line: {ok, screen} or {ok:false, error:{code,exit,thing,problem,fix,message}, screen}",
        "error codes: action-unavailable, input-invalid, input-unexpected, action-failed, bad-request",
    ]

    @MainActor
    static func respond(_ line: String, session: ReinsSession) async -> Response? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.hasPrefix("#") { return nil }
        let request: Request
        switch parse(text) {
        case .success(let parsed): request = parsed
        case .failure(let failure):
            return Response(id: failure.id, ok: false, error: failure.problem, screen: session.ls())
        }
        switch request.op {
        case .ls:
            return Response(id: request.id, ok: true, error: nil, screen: session.ls())
        case .help:
            return Response(id: request.id, ok: true, error: nil, screen: session.ls(), help: help)
        case .do(let action, let input):
            let reply = await session.perform(action, input: input)
            return Response(id: request.id, ok: reply.ok, error: reply.error, screen: reply.screen)
        }
    }

    /// Serves every line from `lines` in order, writing each reply with `write`.
    @MainActor
    public static func serve<Lines: AsyncSequence>(
        _ lines: Lines,
        session: ReinsSession,
        write: (String) -> Void
    ) async throws where Lines.Element == String {
        for try await line in lines {
            if let reply = await handle(line, session: session) { write(reply) }
        }
    }

    struct Request {
        enum Op { case ls, help, `do`(String, ReinsValue?) }
        var id: ReinsValue?
        var op: Op
    }

    struct Response: Encodable {
        var id: ReinsValue?
        var ok: Bool
        var error: OuroAX.Problem?
        var screen: ReinsScreen
        var help: [String]? = nil
    }

    struct ParseFailure: Error {
        var id: ReinsValue?
        var problem: OuroAX.Problem
    }

    static func parse(_ text: String) -> Result<Request, ParseFailure> {
        if text.hasPrefix("{") {
            guard let value = try? ReinsValue(json: text) else {
                return .failure(ParseFailure(problem: ReinsProblem.badRequest("the line starts with { but isn't JSON")))
            }
            switch value["op"]?.stringValue {
            case "ls":
                return .success(Request(id: value["id"], op: .ls))
            case "help":
                return .success(Request(id: value["id"], op: .help))
            case "do":
                guard let action = value["action"]?.stringValue, !action.isEmpty else {
                    return .failure(ParseFailure(id: value["id"], problem: ReinsProblem.badRequest("a do request needs an \"action\" string")))
                }
                return .success(Request(id: value["id"], op: .do(action, value["input"])))
            default:
                return .failure(ParseFailure(id: value["id"], problem: ReinsProblem.badRequest("\"op\" must be \"ls\", \"do\" or \"help\"")))
            }
        }
        let parts = text.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        switch parts.first {
        case "ls" where parts.count == 1:
            return .success(Request(id: nil, op: .ls))
        case "help" where parts.count == 1:
            return .success(Request(id: nil, op: .help))
        case "do" where parts.count >= 2:
            guard parts.count == 3 else { return .success(Request(id: nil, op: .do(parts[1], nil))) }
            guard let input = try? ReinsValue(json: parts[2]) else {
                return .failure(ParseFailure(problem: ReinsProblem.badRequest("the input after `do \(parts[1])` isn't JSON: \(parts[2])")))
            }
            return .success(Request(id: nil, op: .do(parts[1], input)))
        default:
            return .failure(ParseFailure(problem: ReinsProblem.badRequest("unknown request `\(text)`")))
        }
    }

    static func encode(_ response: Response) -> String {
        if let data = try? ReinsValue.encoder.encode(response) { return String(decoding: data, as: UTF8.self) }
        // Never an empty line: a reply that can't be encoded says so, keeping the request's id.
        let fallback = Response(id: response.id, ok: false, error: OuroAX.Problem(code: "reply-unencodable", exit: 1, thing: "reply", problem: "the reply couldn't be encoded as JSON", fix: "keep node state to plain JSON values"),
                                screen: ReinsScreen(focus: response.screen.focus, path: response.screen.path, state: .null, context: [:], actions: []))
        return String(decoding: (try? ReinsValue.encoder.encode(fallback)) ?? Data(#"{"ok":false}"#.utf8), as: UTF8.self)
    }

    /// Splits bytes into request lines at `\n` only (a trailing `\r` is dropped), the same on stdin and the socket. JSON
    /// strings may hold U+2028 and U+2029, so splitting on every Unicode line break would cut a valid request in two.
    static func lines<Bytes: AsyncSequence>(_ bytes: Bytes) -> AsyncThrowingStream<String, any Error> where Bytes.Element == UInt8, Bytes: Sendable {
        AsyncThrowingStream { continuation in
            let task = Task {
                var pending: [UInt8] = []
                do {
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            continuation.yield(line(pending))
                            pending.removeAll(keepingCapacity: true)
                        } else {
                            pending.append(byte)
                        }
                    }
                    if !pending.isEmpty { continuation.yield(line(pending)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func line(_ bytes: some Collection<UInt8>) -> String {
        var text = String(decoding: bytes, as: UTF8.self)
        if text.hasSuffix("\r") { text.removeLast() }
        return text
    }
}

/// A headless `ls`/`do` command line for an app's core, in a few lines of the app's own executable target:
///
/// ```swift
/// @main struct SpoonjoyReins {
///     static func main() async { await ReinsCommandLine.run(ReinsSession(root: { app.reinsNode })) }
/// }
/// ```
///
/// With arguments, each one is a request line (`spoonjoy-reins ls 'do openRecipe {"id":"r1"}' ls`). Without, it reads
/// requests from stdin until it ends. It exits 0 when every request succeeded, 2 when one was refused, and 1 when an
/// action failed, so a script can tell the two apart. With `blockNetwork` (the default) it runs under
/// ``ReinsNetworkGuard`` and exits 3, listing the requests on stderr, when anything tried to reach the network. Build
/// the session inside `makeSession`, so the guard is already up when the app's stores and sessions are made.
public enum ReinsCommandLine {
    @MainActor
    public static func run(
        arguments: [String] = Array(CommandLine.arguments.dropFirst()),
        blockNetwork: Bool = true,
        settle: Duration = .zero,
        _ makeSession: @MainActor () async throws -> ReinsSession
    ) async -> Never {
        let guardrail = blockNetwork ? await ReinsNetworkGuard.begin() : nil
        let session: ReinsSession
        do {
            session = try await makeSession()
        } catch {
            guardrail?.end()
            FileHandle.standardError.write(Data("reins: couldn't build the session: \(error)\n".utf8))
            exit(1)
        }
        let worst = await serve(session, arguments: arguments)
        // Let work the last action scheduled (a debounced save or sync) start, so a late request is caught too.
        if settle > .zero { try? await Task.sleep(for: settle) }
        if let attempts = guardrail?.end(), !attempts.isEmpty {
            FileHandle.standardError.write(Data("reins: \(ReinsNetworkGuard.problem(attempts).message)\n".utf8))
            exit(3)
        }
        exit(worst)
    }

    /// Serves `session` with no network guard; prefer ``run(arguments:blockNetwork:settle:_:)``.
    @MainActor
    public static func run(_ session: ReinsSession, arguments: [String] = Array(CommandLine.arguments.dropFirst())) async -> Never {
        exit(await serve(session, arguments: arguments))
    }

    @MainActor
    static func serve(_ session: ReinsSession, arguments: [String]) async -> Int32 {
        var worst: Int32 = 0
        func run(_ line: String) async {
            guard let response = await ReinsWire.respond(line, session: session) else { return }
            print(ReinsWire.encode(response))
            fflush(stdout)
            if let error = response.error { worst = worst == 1 ? 1 : (error.exit == 1 ? 1 : 2) }
        }
        if arguments.isEmpty {
            do {
                for try await line in ReinsWire.lines(FileHandle.standardInput.bytes) { await run(line) }
            } catch {
                FileHandle.standardError.write(Data("reins: reading stdin failed: \(error)\n".utf8))
                exit(1)
            }
        } else {
            for line in arguments { await run(line) }
        }
        return worst
    }
}
