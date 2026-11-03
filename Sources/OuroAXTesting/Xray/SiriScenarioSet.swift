import Foundation

extension AXXray {
    /// An app's SiriEvaluations scenarios as data: what a person says, of which kind, and what Siri should call, find
    /// or load. `swiftSource()` turns it into a test file behind `#if canImport(SiriEvaluations)`, so the same file
    /// compiles today and runs once the 27.3 SDK and a 27.3 beta OS are there.
    public struct SiriScenarioSet: Codable, Sendable, Hashable {
        /// A constraint on one parameter.
        public struct Match: Codable, Sendable, Hashable {
            public var equals: String?
            public var contains: String?
            /// The entity's type, for an entity parameter; with `identifier`, the one entity.
            public var entity: String?
            public var identifier: String?
            public init(equals: String? = nil, contains: String? = nil, entity: String? = nil, identifier: String? = nil) {
                self.equals = equals
                self.contains = contains
                self.entity = entity
                self.identifier = identifier
            }
        }

        public struct Call: Codable, Sendable, Hashable {
            public var intent: String
            public var parameters: [String: Match]?
            public init(intent: String, parameters: [String: Match]? = nil) {
                self.intent = intent
                self.parameters = parameters
            }
        }

        public struct Scenario: Codable, Sendable, Hashable {
            public var id: String
            public var kind: OuroAXTesting.Wordings.Kind
            /// What the person says, turn by turn; expectations apply to the last turn.
            public var turns: [String]
            public var calls: [Call]?
            /// Intents Siri must not run, or ask to confirm.
            public var disallowed: [String]?
            /// Entity types Siri should find.
            public var finds: [String]?
            /// App skills Siri must load.
            public var loads: [String]?
            /// Text Siri's reply should contain.
            public var response: String?
            /// What a person setting up the device must do first, such as "a recipe named Shakshuka exists".
            public var needs: String?
        }

        public var app: String
        public var bundleIdentifier: String
        public var threshold: Double
        public var runs: Int
        public var scenarios: [Scenario]

        /// Everything in the set that the app's metadata does not have, and wording kinds with no scenario.
        public func problems(against inventory: Inventory) -> [String] {
            var out: [String] = []
            let intents = Dictionary(inventory.intents.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
            let entities = Set(inventory.entities.map(\.typeName))
            var seen = Set<String>()
            for s in scenarios {
                if !seen.insert(s.id).inserted { out.append("\(s.id): the id is used twice") }
                if s.turns.isEmpty { out.append("\(s.id): has no turns") }
                for c in s.calls ?? [] {
                    guard let intent = intents[c.intent] else { out.append("\(s.id): calls \(c.intent), which the app does not have"); continue }
                    for (name, m) in c.parameters ?? [:] {
                        guard let p = intent.parameters.first(where: { $0.name == name }) else { out.append("\(s.id): \(c.intent) has no parameter \(name)"); continue }
                        if let e = m.entity, p.entityType != e { out.append("\(s.id): \(c.intent).\(name) takes \(p.entityType ?? "no entity"), not \(e)") }
                    }
                }
                for d in s.disallowed ?? [] where intents[d] == nil { out.append("\(s.id): disallows \(d), which the app does not have") }
                for f in s.finds ?? [] where !entities.contains(f) { out.append("\(s.id): finds \(f), which the app does not have") }
                if s.kind == .unexpected, !(s.calls ?? []).isEmpty { out.append("\(s.id): an unexpected request expects no call; use disallowed") }
            }
            let kinds = Set(scenarios.map(\.kind))
            for k in OuroAXTesting.Wordings.Kind.allCases where !kinds.contains(k) { out.append("no \(k.rawValue) scenario") }
            return out
        }

        static func swiftString(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
        }

        static func swiftName(_ s: String) -> String {
            let parts = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            let joined = parts.enumerated().map { i, p in (i == 0 ? p.prefix(1).lowercased() : p.prefix(1).uppercased()) + p.dropFirst() }.joined()
            return joined.first?.isNumber == true ? "s" + joined : joined
        }

        /// A Swift Testing file that runs every scenario through Siri, one test per scenario, and appends each run's
        /// pass rates to the file named by `OURO_AX_SIRI_RESULTS`, which `ouro-ax-xray --siri` reads.
        public func swiftSource() -> String {
            let q = Self.swiftString
            let typeName = Self.swiftName(app).prefix(1).uppercased() + Self.swiftName(app).dropFirst() + "SiriEvaluation"
            var intents = Set<String>(), entities = Set<String>(), skills = Set<String>()
            for s in scenarios {
                for c in s.calls ?? [] {
                    intents.insert(c.intent)
                    for m in (c.parameters ?? [:]).values { if let e = m.entity, m.identifier != nil { entities.insert(e) } }
                }
                (s.disallowed ?? []).forEach { intents.insert($0) }
                (s.finds ?? []).forEach { entities.insert($0) }
                (s.loads ?? []).forEach { skills.insert($0) }
            }
            func match(_ m: Match) -> String {
                if let e = m.entity, let id = m.identifier { return "\(Self.swiftName(e)).expectIdentifier(\(q(id)))" }
                if let v = m.equals { return ".equals(\(q(v)))" }
                if let v = m.contains { return ".contains(\(q(v)))" }
                return ".contains(\"\")"
            }
            func call(_ c: Call) -> String {
                let ps = (c.parameters ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key): \(match($0.value))" }
                return ps.isEmpty ? Self.swiftName(c.intent) : "\(Self.swiftName(c.intent)).expect(\(ps.joined(separator: ", ")))"
            }
            var out = [
                "// Generated by ouro-ax-xray from \(Self.swiftName(app))'s Siri scenario set. Edit the JSON, not this file.",
                "// Runs on a 27.3 beta OS on an Apple Intelligence device, from a test target signed by the app's team.",
                "#if canImport(SiriEvaluations)",
                "import Foundation",
                "import Testing",
                "import Evaluations",
                "import SiriEvaluations",
                "import AppIntentsTesting",
                "",
                "private let app = IntentDefinitions(bundleIdentifier: \(q(bundleIdentifier)))",
            ]
            out += intents.sorted().map { "private let \(Self.swiftName($0)) = app.intents[\(q($0))]" }
            out += entities.sorted().map { "private let \(Self.swiftName($0)) = app.entities[\(q($0))]" }
            out += skills.sorted().map { "private let \(Self.swiftName($0)) = app.skills[\(q($0))]" }
            out += [
                "",
                "struct \(typeName): Evaluation {",
                "    let name: String",
                "    let dataset: SiriScenarioLoader",
                "    func subject(from sample: SiriScenario) async throws -> SiriScenarioSubject { try await SiriService.run(scenario: sample) }",
                "    var evaluators: Evaluators { SiriExpectationEvaluator() }",
                "    func aggregateMetrics(using aggregator: inout MetricsAggregator) { Self.computeSiriMetrics(into: &aggregator) }",
                "}",
                "",
                "/// Appends one run's pass or fail per expectation kind to $OURO_AX_SIRI_RESULTS (JSON lines), for ouro-ax-xray --siri.",
                "private func record(_ id: String, _ passes: [String: Bool]) {",
                "    guard let path = ProcessInfo.processInfo.environment[\"OURO_AX_SIRI_RESULTS\"],",
                "          let line = try? JSONSerialization.data(withJSONObject: [\"id\": id, \"passes\": passes]) else { return }",
                "    if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }",
                "    guard let handle = FileHandle(forWritingAtPath: path) else { return }",
                "    handle.seekToEndOfFile()",
                "    handle.write(line + Data(\"\\n\".utf8))",
                "    try? handle.close()",
                "}",
                "",
                "@Suite(\(q("\(app) through Siri"))) struct \(typeName)Tests {",
            ]
            for s in scenarios {
                var body: [String] = []
                if let calls = s.calls, !calls.isEmpty { body += ["Calls {"] + calls.map { "    \(call($0))" } + ["}"] }
                if let d = s.disallowed, !d.isEmpty { body += ["Calls(.disallowed) {"] + d.map { "    \(Self.swiftName($0))" } + ["}"] }
                if let f = s.finds, !f.isEmpty { body += ["Finds {"] + f.map { "    \(Self.swiftName($0))" } + ["}"] }
                if let l = s.loads, !l.isEmpty { body += ["Loads(.required) {"] + l.map { "    \(Self.swiftName($0))" } + ["}"] }
                if let r = s.response { body.append("SiriResponse(.contains(\(q(r))))") }
                var turns = s.turns.dropLast().map { "                UserTurn(\(q($0)))" }
                let last = s.turns.last ?? ""
                if body.isEmpty { turns.append("                UserTurn(\(q(last)))") } else {
                    turns.append("                UserTurn(\(q(last))) {")
                    turns += body.map { "                    \($0)" }
                    turns.append("                }")
                }
                let metrics = [(s.calls?.isEmpty == false || s.disallowed?.isEmpty == false) ? "\"calls\": (result.aggregateValue(.mean(of: .intentsAllPass)) ?? 0) >= 1" : nil,
                               s.loads?.isEmpty == false ? "\"loads\": (result.aggregateValue(.mean(of: .skillsLoadedPass)) ?? 0) >= 1" : nil].compactMap { $0 }
                out += [
                    "    /// \(s.kind.rawValue)\(s.needs.map { ". Needs: \($0)" } ?? "")",
                    "    @Test(.evaluates(\(typeName)(name: \(q(s.id)), dataset: SiriScenarioLoader {",
                    "        SiriScenario {",
                ] + turns.map { String($0.dropFirst(4)) } + [
                    "        }",
                    "    })))",
                    "    func \(Self.swiftName(s.id))() async throws {",
                    "        let result = EvaluationContext.current.result",
                    "        record(\(q(s.id)), [\(metrics.isEmpty ? ":" : metrics.joined(separator: ", "))])",
                    "    }",
                    "",
                ]
            }
            out += ["}", "#endif", ""]
            return out.joined(separator: "\n")
        }
    }

    /// Reads the JSON lines the generated tests append, one run per line, into the X-ray's SiriEvaluations input.
    public static func siriResults(jsonLines: String, ranOn: String, threshold: Double) throws -> SiriResults {
        struct Line: Decodable { var id: String; var passes: [String: Bool] }
        var order: [String] = []
        var by: [String: [String: [Bool]]] = [:]
        for raw in jsonLines.split(separator: "\n") where !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            let line = try JSONDecoder().decode(Line.self, from: Data(raw.utf8))
            if by[line.id] == nil { order.append(line.id) }
            for (k, v) in line.passes { by[line.id, default: [:]][k, default: []].append(v) }
        }
        return SiriResults(ranOn: ranOn, threshold: threshold, scenarios: order.map { .init(id: $0, passes: by[$0]!) })
    }
}
