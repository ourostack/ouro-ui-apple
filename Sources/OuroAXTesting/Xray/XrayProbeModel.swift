import Foundation

extension AXXray {
    /// What the behaviour stage runs against a live app with AppIntentsTesting. `ouro-ax-xray plan` writes it from the
    /// metadata; the probe test bundle reads it, runs it and returns a `ProbeResult`. Every probe is a read, except
    /// the refusals, which run an intent with an entity reference nothing can match, and only when `refusals` is on.
    public struct ProbePlan: Codable, Sendable, Hashable {
        public struct EntityProbe: Codable, Sendable, Hashable {
            public var typeName: String
            public var indexed: Bool
            public var transferable: Bool
            public var stringSearchable: Bool
            public var enumerable: Bool
            public init(typeName: String, indexed: Bool, transferable: Bool, stringSearchable: Bool, enumerable: Bool) {
                self.typeName = typeName
                self.indexed = indexed
                self.transferable = transferable
                self.stringSearchable = stringSearchable
                self.enumerable = enumerable
            }
        }

        public struct RefusalProbe: Codable, Sendable, Hashable {
            public var intent: String
            /// The entity parameters it is given, each a made-up reference: parameter name to entity type.
            public var entityParameters: [String: String]
            public init(intent: String, entityParameters: [String: String]) {
                self.intent = intent
                self.entityParameters = entityParameters
            }
        }

        public var bundleIdentifier: String
        public var entities: [EntityProbe]
        public var refusals: [RefusalProbe]
        /// The identifier given to every made-up entity reference.
        public var missingIdentifier: String

        public init(bundleIdentifier: String, entities: [EntityProbe], refusals: [RefusalProbe], missingIdentifier: String = "ouro-ax-xray-missing-0") {
            self.bundleIdentifier = bundleIdentifier
            self.entities = entities
            self.refusals = refusals
            self.missingIdentifier = missingIdentifier
        }

        /// The plan for an inventory. Refusals are planned only for intents whose required parameters are all entities,
        /// so a refusal can only be about the missing entity; `refusals: false` plans none.
        public init(bundleIdentifier: String, inventory: Inventory, refusals: Bool) {
            self.init(
                bundleIdentifier: bundleIdentifier,
                entities: inventory.entities.filter { !$0.transient }.map {
                    EntityProbe(typeName: $0.typeName, indexed: $0.indexed, transferable: !$0.exportableTypes.isEmpty, stringSearchable: $0.stringSearchable, enumerable: $0.enumerable)
                },
                refusals: refusals ? inventory.intents.compactMap { intent in
                    let required = intent.parameters.filter { !$0.isOptional }
                    let entityParameters = intent.parameters.filter { $0.entityType != nil && !$0.isOptional }
                    guard !entityParameters.isEmpty, required.allSatisfy({ $0.entityType != nil }) else { return nil }
                    return RefusalProbe(intent: intent.identifier, entityParameters: Dictionary(uniqueKeysWithValues: entityParameters.map { ($0.name, $0.entityType!) }))
                } : []
            )
        }
    }

    /// What one behaviour run saw. Each step records whether it ran, what it returned and any error, as text.
    public struct ProbeResult: Codable, Sendable, Hashable {
        public struct Step: Codable, Sendable, Hashable {
            /// Entity type or intent identifier.
            public var subject: String
            /// suggested, all, matching, identifiers, spotlight, view-annotations, export-resolve, refusal.
            public var probe: String
            /// The number of things it returned; nil when it threw.
            public var count: Int?
            /// For a lookup, how many it asked for.
            public var asked: Int?
            public var error: String?
            public var note: String?
            public init(subject: String, probe: String, count: Int? = nil, asked: Int? = nil, error: String? = nil, note: String? = nil) {
                self.subject = subject
                self.probe = probe
                self.count = count
                self.asked = asked
                self.error = error
                self.note = note
            }
        }

        public var bundleIdentifier: String
        /// The OS and Xcode it ran on, such as "iOS 27.1 Simulator, Xcode 27.1 (27B...)".
        public var ranOn: String
        public var refusalsAllowed: Bool
        public var steps: [Step]
        public init(bundleIdentifier: String, ranOn: String, refusalsAllowed: Bool, steps: [Step]) {
            self.bundleIdentifier = bundleIdentifier
            self.ranOn = ranOn
            self.refusalsAllowed = refusalsAllowed
            self.steps = steps
        }

        public func step(_ subject: String, _ probe: String) -> Step? { steps.first { $0.subject == subject && $0.probe == probe } }

        /// The lines a probe prints so a runner can take its result out of a test log.
        public static let beginMarker = "OURO-AX-PROBE-BEGIN"
        public static let endMarker = "OURO-AX-PROBE-END"

        /// The result as one base64 line between the markers.
        public func logLines() throws -> String {
            let data = try JSONEncoder().encode(self)
            return "\(Self.beginMarker)\n\(data.base64EncodedString())\n\(Self.endMarker)"
        }

        /// The result a probe printed into a log, or nil when there is none.
        public static func fromLog(_ log: String) throws -> ProbeResult? {
            guard let begin = log.range(of: beginMarker + "\n"), let end = log.range(of: "\n" + endMarker, range: begin.upperBound..<log.endIndex) else { return nil }
            let line = log[begin.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = Data(base64Encoded: line) else { return nil }
            return try JSONDecoder().decode(ProbeResult.self, from: data)
        }
    }

    /// SiriEvaluations results, as a scenario set's run reports them: per scenario, its pass rate for each kind of
    /// expectation. The X-ray only reads this file; producing it needs a 27.3 beta OS (see SiriScenarioSet).
    public struct SiriResults: Codable, Sendable, Hashable {
        public struct Scenario: Codable, Sendable, Hashable {
            public var id: String
            /// Expectation kind (calls, finds, loads, onscreen, response) to passes over runs.
            public var passes: [String: [Bool]]
        }

        public var ranOn: String
        public var threshold: Double
        public var scenarios: [Scenario]
    }
}
