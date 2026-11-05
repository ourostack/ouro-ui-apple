import Foundation
import OuroAX
@testable import OuroReins
import Testing

// MARK: - A small app core to drive

@MainActor
private final class Counter: ReinsDrivable {
    var count = 0
    var pages: [String] = []
    var performed: [String] = []
    var later: Int?

    var reinsNode: ReinsNode {
        let top: ReinsNode = if let page = pages.last {
            ReinsNode("page", state: ["title": .string(page)], actions: [
                ReinsAction("goBack", "The page's own back, which wins over the stack's") { [unowned self] in
                    self.performed.append("page.goBack")
                    _ = self.pages.popLast()
                },
            ])
        } else {
            ReinsNode("home", state: ["count": .number(Double(count)), "later": later.map { .number(Double($0)) } ?? .null], actions: [
                ReinsAction("add", "Add to the count", input: Add.self) { [unowned self] in
                    self.performed.append("add")
                    self.count += $0.by
                },
                ReinsAction("open", "Open a page", input: Open.self) { [unowned self] in self.pages.append($0.title) },
                ReinsAction("explode", "Throws") { throw Boom() },
                ReinsAction("refuse", "Throws a problem") {
                    throw OuroAX.Problem(code: "not-now", exit: 2, thing: "refuse", problem: "not now", fix: "later")
                },
                ReinsAction("setLater", "Sets the count after a delay") { [unowned self] in
                    _ = Task { @MainActor in
                        try await Task.sleep(for: .milliseconds(30))
                        self.later = 7
                    }
                },
            ])
        }
        return ReinsNode("app", state: ["version": 1], child: .stack(depth: pages.count, goBack: { [unowned self] in
            self.performed.append("stack.goBack")
            _ = self.pages.popLast()
        }, child: top))
    }

    struct Add: ReinsInput { let by: Int }
    struct Open: ReinsInput { let title: String }
    struct Boom: Error {}
}

// MARK: - Schemas

private enum Size: String, CaseIterable, Codable, ReinsEnumerable { case small, large }
private struct Nested: Codable { let name: String; let tags: [String] }
private struct Everything: ReinsInput {
    let text: String
    let whole: Int
    let fraction: Double
    let flag: Bool
    let note: String?
    let size: Size
    let items: [Nested]
    let when: Date?
}
private struct Picky: ReinsInput {
    let id: String
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        guard !id.isEmpty else { throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "empty id") }
    }
    enum CodingKeys: String, CodingKey { case id }
}

@Suite("Input schemas")
struct SchemaTests {
    @Test("derives required, optional, nested, array, enum and date properties from Decodable")
    func derivesFromDecodable() {
        let schema = Everything.reinsSchema
        guard case .object(let properties, let required) = schema else {
            Issue.record("expected an object, got \(schema)")
            return
        }
        #expect(Set(required) == ["text", "whole", "fraction", "flag", "size", "items"])
        #expect(properties["text"] == .string)
        #expect(properties["whole"] == .integer)
        #expect(properties["fraction"] == .number)
        #expect(properties["flag"] == .boolean)
        #expect(properties["note"] == .string)
        #expect(properties["size"] == .oneOf(["small", "large"]))
        #expect(properties["when"] == .string)
        #expect(properties["items"] == .array(.object(properties: ["name": .string, "tags": .array(.string)], required: ["name", "tags"])))
    }

    @Test("a type that rejects placeholder values says why and how to fix it")
    func underivedSaysWhy() {
        guard case .underived(let reason) = Picky.reinsSchema else {
            Issue.record("expected underived, got \(Picky.reinsSchema)")
            return
        }
        #expect(reason.contains("declare `static var reinsSchema`"))
        #expect(Picky.reinsSchema.problems(in: ["id": "x"]).count == 1)
    }

    @Test("validation names the path of every problem")
    func validationPaths() {
        let schema = Everything.reinsSchema
        let problems = schema.problems(in: [
            "text": 3, "whole": 1.5, "fraction": 2, "flag": true, "size": "medium",
            "items": [["name": "a", "tags": ["x", 4]]], "extra": true,
        ])
        #expect(problems.contains("$.text: expected a string, got integer"))
        #expect(problems.contains("$.whole: expected an integer, got 1.5"))
        #expect(problems.contains(#"$.size: "medium" isn't one of "small", "large""#))
        #expect(problems.contains("$.items[0].tags[1]: expected a string, got integer"))
        #expect(problems.contains { $0.hasPrefix("$.extra: not a property of this input") })
        #expect(schema.problems(in: ["text": "t"]).contains("$.whole: required, missing"))
        #expect(!problems.contains { $0.hasPrefix("$.note") }, "an absent optional is fine")
    }

    @Test("the JSON Schema form closes objects and lists required keys in order")
    func jsonSchemaForm() {
        let json = ReinsSchema.object(properties: ["b": .integer, "a": .oneOf(["x"])], required: ["b", "a"]).json.json
        #expect(json == #"{"additionalProperties":false,"properties":{"a":{"enum":["x"],"type":"string"},"b":{"type":"integer"}},"required":["a","b"],"type":"object"}"#)
    }
}

// MARK: - Values

@Suite("Values")
struct ValueTests {
    @Test("encodes with sorted keys and whole numbers without a fraction")
    func stableEncoding() throws {
        let value: ReinsValue = ["b": 2, "a": [1.5, true, nil, "s"]]
        #expect(value.json == #"{"a":[1.5,true,null,"s"],"b":2}"#)
        #expect(try ReinsValue(json: value.json) == value)
        #expect(value["b"]?.intValue == 2)
        #expect(value["a"]?[0]?.intValue == nil)
    }
}

// MARK: - Sessions

@MainActor
@Suite("Sessions")
struct SessionTests {
    @Test("ls focuses the deepest node and gives each ancestor's state as context")
    func focusAndContext() {
        let app = Counter()
        let screen = ReinsSession(app).ls()
        #expect(screen.focus == "home")
        #expect(screen.path == ["app", "stack", "home"])
        #expect(screen.context["app"] == ["version": 1])
        #expect(screen.context["stack"] == ["depth": 0])
        #expect(screen.actionNames == ["add", "open", "explode", "refuse", "setLater"], "a stack at its root lends no goBack")
    }

    @Test("a navigator lends goBack to the focus, and the focus's own action of the same name wins")
    func lending() async {
        let app = Counter()
        let session = ReinsSession(app)
        let opened = await session.perform("open", input: ["title": "Soup"])
        #expect(opened.ok)
        #expect(opened.screen.focus == "page")
        #expect(opened.screen.actions.filter { $0.name == "goBack" }.map(\.from) == ["page"])
        _ = await session.perform("goBack")
        #expect(app.performed == ["page.goBack"])
    }

    @Test("an action the screen doesn't offer is refused with the valid ones, and nothing runs")
    func refusesUnavailable() async {
        let app = Counter()
        let reply = await ReinsSession(app).perform("goBack")
        #expect(!reply.ok)
        #expect(reply.error?.code == "action-unavailable")
        #expect(reply.error?.exit == 2)
        #expect(reply.error?.message == "do goBack: goBack isn't available on home. Fix: use one of: add, open, explode, refuse, setLater.")
        #expect(reply.screen.focus == "home")
        #expect(app.performed.isEmpty)
    }

    @Test("malformed input is refused before the view model sees it")
    func refusesInvalidInput() async {
        let app = Counter()
        let session = ReinsSession(app)
        let wrong = await session.perform("add", input: ["by": "two"])
        #expect(wrong.error?.code == "input-invalid")
        #expect(wrong.error?.problem == "$.by: expected an integer, got string")
        let missing = await session.perform("add")
        #expect(missing.error?.problem == "$.by: required, missing")
        let unexpected = await session.perform("explode", input: ["x": 1])
        #expect(unexpected.error?.code == "input-unexpected")
        #expect(app.performed.isEmpty)
        let ok = await session.perform("add", input: ["by": 2])
        #expect(ok.ok)
        #expect(ok.screen.state["count"] == 2)
    }

    @Test("a throwing action fails with action-failed, and a thrown Ouro AX problem passes through")
    func failures() async {
        let session = ReinsSession(Counter())
        let boom = await session.perform("explode")
        #expect(boom.error?.code == "action-failed")
        #expect(boom.error?.exit == 1)
        let refused = await session.perform("refuse")
        #expect(refused.error?.code == "not-now")
    }

    @Test("the transcript holds every do, refused ones too, as replayable lines")
    func transcript() async {
        let app = Counter()
        let session = ReinsSession(app)
        _ = await session.perform("add", input: ["by": 1])
        _ = await session.perform("nope")
        _ = await session.perform("open", input: ["title": "Soup"])
        #expect(session.transcript == [#"do add {"by":1}"#, "do nope", #"do open {"title":"Soup"}"#])

        let replay = Counter()
        let replaySession = ReinsSession(replay)
        for line in session.transcript { _ = await ReinsWire.handle(line, session: replaySession) }
        #expect(replaySession.ls() == session.ls())
    }
}

// MARK: - Journeys

@MainActor
@Suite("Journeys")
struct JourneyTests {
    @Test("a step polls until state that changes later arrives")
    func pollsForLaterState() async throws {
        let journey = ReinsJourney(ReinsSession(Counter()))
        try await journey.expect("home")
        let screen = try await journey.do("setLater", until: { $0.state["later"] == 7 }, "later is 7")
        #expect(screen.state["later"] == 7)
    }

    @Test("a failure says what it waited for, shows the last screen and the replay")
    func failureReads() async throws {
        let journey = ReinsJourney(ReinsSession(Counter()), timeout: .milliseconds(20))
        _ = try await journey.do("add", ["by": 1])
        do {
            try await journey.expect("page")
            Issue.record("expected a failure")
        } catch let failure as ReinsJourneyFailure {
            #expect(failure.description.hasPrefix("Waited for focus page."))
            #expect(failure.description.contains(#""focus" : "home""#))
            #expect(failure.description.hasSuffix(#"Replay:"# + "\n" + #"do add {"by":1}"#))
        }
        await #expect(throws: ReinsJourneyFailure.self) { try await journey.do("nope") }
    }
}

// MARK: - The wire

@MainActor
@Suite("Wire protocol")
struct WireTests {
    @Test("text and JSON requests get one JSON line each, with the id echoed")
    func forms() async throws {
        let session = ReinsSession(Counter())
        let ls = try ReinsValue(json: #require(await ReinsWire.handle("ls", session: session)))
        #expect(ls["ok"] == true)
        #expect(ls["screen"]?["focus"] == "home")
        let text = try ReinsValue(json: #require(await ReinsWire.handle(#"do add {"by":3}"#, session: session)))
        #expect(text["screen"]?["state"]?["count"] == 3)
        let json = try ReinsValue(json: #require(await ReinsWire.handle(#"{"id":"a","op":"do","action":"add","input":{"by":1}}"#, session: session)))
        #expect(json["id"] == "a")
        #expect(json["screen"]?["state"]?["count"] == 4)
        let help = try ReinsValue(json: #require(await ReinsWire.handle(#"{"id":2,"op":"help"}"#, session: session)))
        #expect(help["help"]?.arrayValue?.isEmpty == false)
    }

    @Test("blank and comment lines get no reply; a malformed one gets bad-request with the forms")
    func badLines() async throws {
        let session = ReinsSession(Counter())
        #expect(await ReinsWire.handle("   ", session: session) == nil)
        #expect(await ReinsWire.handle("# a note", session: session) == nil)
        for line in ["dance", "{nope", #"{"op":"jump"}"#, #"do add {"by":"#] {
            let reply = try ReinsValue(json: #require(await ReinsWire.handle(line, session: session)))
            #expect(reply["ok"] == false, "\(line)")
            #expect(reply["error"]?["code"] == "bad-request", "\(line)")
            #expect(reply["screen"]?["focus"] == "home", "a refusal still shows the screen: \(line)")
        }
    }

    @Test("serve answers lines in order")
    func serve() async throws {
        let session = ReinsSession(Counter())
        let lines = AsyncStream<String> { continuation in
            for line in ["ls", "", #"do add {"by":2}"#, "ls"] { continuation.yield(line) }
            continuation.finish()
        }
        var out: [String] = []
        try await ReinsWire.serve(lines, session: session) { out.append($0) }
        #expect(out.count == 3)
        #expect(try ReinsValue(json: out[2])["screen"]?["state"]?["count"] == 2)
    }
}
