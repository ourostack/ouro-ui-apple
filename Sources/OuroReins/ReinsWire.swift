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
        case .failure(let problem):
            return Response(id: nil, ok: false, error: problem, screen: session.ls())
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

    static func parse(_ text: String) -> Result<Request, OuroAX.Problem> {
        if text.hasPrefix("{") {
            guard let value = try? ReinsValue(json: text) else {
                return .failure(ReinsProblem.badRequest("the line starts with { but isn't JSON"))
            }
            switch value["op"]?.stringValue {
            case "ls":
                return .success(Request(id: value["id"], op: .ls))
            case "help":
                return .success(Request(id: value["id"], op: .help))
            case "do":
                guard let action = value["action"]?.stringValue, !action.isEmpty else {
                    return .failure(ReinsProblem.badRequest("a do request needs an \"action\" string"))
                }
                return .success(Request(id: value["id"], op: .do(action, value["input"])))
            default:
                return .failure(ReinsProblem.badRequest("\"op\" must be \"ls\", \"do\" or \"help\""))
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
                return .failure(ReinsProblem.badRequest("the input after `do \(parts[1])` isn't JSON: \(parts[2])"))
            }
            return .success(Request(id: nil, op: .do(parts[1], input)))
        default:
            return .failure(ReinsProblem.badRequest("unknown request `\(text)`"))
        }
    }

    static func encode(_ response: Response) -> String {
        String(decoding: (try? ReinsValue.encoder.encode(response)) ?? Data(), as: UTF8.self)
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
/// action failed, so a script can tell the two apart. A blocked network attempt is the session's to report (see
/// ``ReinsNetworkGuard``), not a reply's.
public enum ReinsCommandLine {
    @MainActor
    public static func run(_ session: ReinsSession, arguments: [String] = Array(CommandLine.arguments.dropFirst())) async -> Never {
        var worst: Int32 = 0
        func run(_ line: String) async {
            guard let response = await ReinsWire.respond(line, session: session) else { return }
            print(ReinsWire.encode(response))
            fflush(stdout)
            if let error = response.error { worst = worst == 1 ? 1 : (error.exit == 1 ? 1 : 2) }
        }
        if arguments.isEmpty {
            do {
                for try await line in FileHandle.standardInput.bytes.lines { await run(line) }
            } catch {
                FileHandle.standardError.write(Data("reins: reading stdin failed: \(error)\n".utf8))
                exit(1)
            }
        } else {
            for line in arguments { await run(line) }
        }
        exit(worst)
    }
}
