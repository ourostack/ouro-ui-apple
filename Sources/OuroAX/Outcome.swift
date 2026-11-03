public import Foundation

extension OuroAX {
    /// The version tag every outcome carries as `ax`.
    public static let outcomeVersion = "outcome/1"

    /// Whether an action touches only the person's own space or reaches other people.
    public enum Effect: String, Codable, Sendable, Hashable {
        case `private`
        case others
    }

    /// Who can see an effect, in words a person reads.
    public struct Audience: Codable, Sendable, Hashable {
        public var only: Bool
        public var who: String

        public init(only: Bool, who: String) {
            self.only = only
            self.who = who
        }

        public static let onlyYou = Audience(only: true, who: "only you")

        /// Whether `who` names no one in particular ("other people", "someone", "everyone").
        public static func isGeneric(_ who: String) -> Bool {
            who.trimmingCharacters(in: .whitespacesAndNewlines)
                .wholeMatch(of: /(?i)(?:other people|others|people|someone|somebody|anyone|anybody|everyone|everybody|the audience|recipients|users?)\.?/) != nil
        }
    }

    /// A thing an agent holds a reference to. `id` is what the tool takes back.
    public struct Ref: Codable, Sendable, Hashable {
        public var kind: String
        public var id: String
        public var name: String?

        public init(kind: String, id: String, name: String? = nil) {
            self.kind = kind
            self.id = id
            self.name = name
        }
    }

    /// The check that the effect holds, made apart from the transport's answer. `holds` is nil while it cannot be
    /// observed yet; `how` names what was read.
    public struct Postcondition: Codable, Sendable, Hashable {
        public var checked: Bool
        public var holds: Bool?
        public var how: String

        public init(checked: Bool, holds: Bool?, how: String) {
            self.checked = checked
            self.holds = holds
            self.how = how
        }

        public static let notChecked = Postcondition(checked: false, holds: nil, how: "not checked")

        private enum CodingKeys: String, CodingKey { case checked, holds, how }
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(checked, forKey: .checked)
            if let holds { try c.encode(holds, forKey: .holds) } else { try c.encodeNil(forKey: .holds) }
            try c.encode(how, forKey: .how)
        }
    }

    /// A durable record of the request: the id that finds it again, when (ISO 8601), by whom and why.
    public struct Receipt: Codable, Sendable, Hashable {
        public var id: String
        public var at: String
        public var by: String
        public var why: String?

        public init(id: String, at: String, by: String, why: String?) {
            self.id = id
            self.at = at
            self.by = by
            self.why = why
        }

        public init(id: String, at date: Date, by: String, why: String?) {
            self.init(id: id, at: date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)), by: by, why: why)
        }

        private enum CodingKeys: String, CodingKey { case id, at, by, why }
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(at, forKey: .at)
            try c.encode(by, forKey: .by)
            if let why { try c.encode(why, forKey: .why) } else { try c.encodeNil(forKey: .why) }
        }
    }

    /// One next valid action: an exact command, and why an agent would run it.
    public struct NextStep: Codable, Sendable, Hashable {
        public var command: String
        public var why: String
        /// The step works only in a source checkout; without it a step may not ask for a developer command.
        public var sourceCheckout: Bool

        public init(_ command: String, why: String, sourceCheckout: Bool = false) {
            self.command = command
            self.why = why
            self.sourceCheckout = sourceCheckout
        }

        private enum CodingKeys: String, CodingKey { case command, why, sourceCheckout }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            command = try c.decode(String.self, forKey: .command)
            why = try c.decode(String.self, forKey: .why)
            sourceCheckout = try c.decodeIfPresent(Bool.self, forKey: .sourceCheckout) ?? false
        }
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(command, forKey: .command)
            try c.encode(why, forKey: .why)
            if sourceCheckout { try c.encode(true, forKey: .sourceCheckout) }
        }
    }

    /// Why only a person can go on, and the step that resumes once they have.
    public struct Human: Codable, Sendable, Hashable {
        public var reason: String
        public var resume: NextStep

        public init(reason: String, resume: NextStep) {
            self.reason = reason
            self.resume = resume
        }
    }

    /// What an action returns: what became of it, who can see it, whether that was checked, how to find it again
    /// and what to run next. The JSON is `ax-outcome`'s `outcome/1`, field for field.
    public struct Outcome: Codable, Sendable, Hashable {
        /// What became of an action.
        public enum State: String, Codable, Sendable, Hashable, CaseIterable {
            /// It happened; the postcondition says how that is known.
            case done
            /// Accepted, not performed yet; the receipt and next steps follow it.
            case queued
            /// A dry run; nothing happened.
            case planned
            /// Only a person can take the next step; `human` says why and how to resume. `needs-human` on the wire.
            case needsPerson = "needs-human"
            /// It may or may not have happened; reconcile before any retry.
            case uncertain
            /// Checked and not done, with the reason; nothing happened.
            case refused
            /// Tried and proven not done.
            case failed
        }

        public var ax: String = OuroAX.outcomeVersion
        public var action: String
        public var effect: Effect
        public var audience: Audience
        public var target: Ref?
        public var state: State
        public var summary: String
        public var postcondition: Postcondition
        public var receipt: Receipt?
        public var next: [NextStep]
        public var error: Problem?
        public var human: Human?

        /// An outcome with honest defaults: private, only you, nothing checked, no receipt and no next steps. Pass what
        /// is known; ``validate()`` says what is missing.
        public init(
            action: String,
            state: State,
            summary: String,
            effect: Effect = .private,
            audience: Audience = .onlyYou,
            target: Ref? = nil,
            postcondition: Postcondition = .notChecked,
            receipt: Receipt? = nil,
            next: [NextStep] = [],
            error: Problem? = nil,
            human: Human? = nil
        ) {
            self.action = action
            self.state = state
            self.summary = summary
            self.effect = effect
            self.audience = audience
            self.target = target
            self.postcondition = postcondition
            self.receipt = receipt
            self.next = next
            self.error = error
            self.human = human
        }

        private enum CodingKeys: String, CodingKey { case ax, action, effect, audience, target, state, summary, postcondition, receipt, next, error, human }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ax = try c.decode(String.self, forKey: .ax)
            guard ax == OuroAX.outcomeVersion else {
                throw DecodingError.dataCorruptedError(forKey: .ax, in: c, debugDescription: "not an \(OuroAX.outcomeVersion) envelope")
            }
            action = try c.decode(String.self, forKey: .action)
            effect = try c.decode(Effect.self, forKey: .effect)
            audience = try c.decode(Audience.self, forKey: .audience)
            target = try c.decodeIfPresent(Ref.self, forKey: .target)
            state = try c.decode(State.self, forKey: .state)
            summary = try c.decode(String.self, forKey: .summary)
            postcondition = try c.decode(Postcondition.self, forKey: .postcondition)
            receipt = try c.decodeIfPresent(Receipt.self, forKey: .receipt)
            next = try c.decode([NextStep].self, forKey: .next)
            error = try c.decodeIfPresent(Problem.self, forKey: .error)
            human = try c.decodeIfPresent(Human.self, forKey: .human)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(ax, forKey: .ax)
            try c.encode(action, forKey: .action)
            try c.encode(effect, forKey: .effect)
            try c.encode(audience, forKey: .audience)
            if let target { try c.encode(target, forKey: .target) } else { try c.encodeNil(forKey: .target) }
            try c.encode(state, forKey: .state)
            try c.encode(summary, forKey: .summary)
            try c.encode(postcondition, forKey: .postcondition)
            if let receipt { try c.encode(receipt, forKey: .receipt) } else { try c.encodeNil(forKey: .receipt) }
            try c.encode(next, forKey: .next)
            try c.encodeIfPresent(error, forKey: .error)
            try c.encodeIfPresent(human, forKey: .human)
        }

        /// Exit code names by state: done, queued, planned and needs-person exit `ok`; a refusal `usage`; a failure or an
        /// uncertain result `error`.
        public static let defaultExits: [State: String] = [
            .done: "ok", .queued: "ok", .planned: "ok", .needsPerson: "ok", .uncertain: "error", .refused: "usage", .failed: "error",
        ]

        /// The exit code this outcome gives: a refusal's or failure's own error exit, else its state's name in the table.
        public func exitCode(in table: ExitTable, names: [State: String] = Outcome.defaultExits) throws -> Int {
            if state == .refused || state == .failed, let error { return error.exit }
            return try table.code(names[state] ?? "error")
        }

        /// The outcome as text for a person: the summary, what was checked, what only the person can do, then the next
        /// steps. A refusal or failure with an error is its one error line.
        public func text(tool: String) -> String {
            if state == .refused || state == .failed, let error { return error.line(tool: tool) }
            var lines = [summary]
            let how = postcondition.how.replacing(/[.\s]+$/, with: "")
            if postcondition.checked, let holds = postcondition.holds {
                lines.append("Checked: \(how)\(holds ? "" : " (it does not hold)").")
            } else if how != "not checked" {
                lines.append("Not checked yet: \(how).")
            }
            if let receipt { lines.append("Receipt: \(receipt.id)") }
            if let human { lines.append("Needs the person: \(human.reason.replacing(/[.\s]+$/, with: "")). Then: \(human.resume.command)") }
            for step in next { lines.append("Next: \(step.command)  (\(step.why))") }
            return lines.joined(separator: "\n")
        }
    }
}
