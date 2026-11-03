import Foundation

extension OuroAX {
    /// What ``Outcome/validate()`` found. Problems that make an envelope untrustworthy are errors; honest gaps are
    /// warnings.
    public struct Validation: Sendable, Hashable {
        public var ok: Bool
        public var errors: [String]
        public var warnings: [String]

        public init(ok: Bool, errors: [String], warnings: [String]) {
            self.ok = ok
            self.errors = errors
            self.warnings = warnings
        }
    }
}

extension OuroAX.Outcome {
    /// Checks this outcome's meaning, not only its shape, by the same rules and in the same words as `ax-outcome`'s
    /// `validateOutcome`.
    public func validate() -> OuroAX.Validation {
        guard let data = try? JSONEncoder().encode(self), let object = try? JSONSerialization.jsonObject(with: data) else {
            return .init(ok: false, errors: ["the outcome does not encode as JSON"], warnings: [])
        }
        return Self.validate(jsonObject: object)
    }

    /// Checks any JSON value (from `JSONSerialization`) as an `outcome/1` envelope: a port of `validateOutcome`.
    /// - `done` never rests on a postcondition that failed; one not checked is a warning.
    /// - `refused` and `failed` carry an error and never claim the effect holds.
    /// - `queued` and `uncertain` carry a receipt and a next step, and `uncertain` cannot claim to know.
    /// - an effect other people see carries a receipt with a why, and an audience that is not only you.
    /// - `needs-human` carries the reason and the step that resumes.
    public static func validate(jsonObject value: Any) -> OuroAX.Validation {
        var errors: [String] = []
        var warnings: [String] = []
        let states = State.allCases.map(\.rawValue)
        guard let v = value as? [String: Any], v["ax"] as? String == OuroAX.outcomeVersion, let state = v["state"] as? String, states.contains(state) else {
            return .init(ok: false, errors: ["not an \(OuroAX.outcomeVersion) envelope: ax must be \"\(OuroAX.outcomeVersion)\" and state one of \(states.joined(separator: ", "))"], warnings: [])
        }
        if !isText(v["action"]) { errors.append("action is empty") }
        let effect = v["effect"] as? String
        if effect != "private" && effect != "others" { errors.append(#"effect is "private" or "others""#) }
        if let audience = v["audience"] as? [String: Any], let only = bool(audience["only"]), isText(audience["who"]) {
            let who = audience["who"] as! String
            if effect == "others" && only { errors.append("an effect other people see cannot have an audience of only you") }
            else if effect == "others" && OuroAX.Audience.isGeneric(who) {
                warnings.append(#"audience.who is "\#(who)", which names no one: say who will see it, as the text does (everyone in "Design sync", Jo Park)"#)
            }
        } else {
            errors.append("audience needs only (true or false) and who (words)")
        }
        if !(v["target"] is NSNull) {
            let t = v["target"] as? [String: Any]
            if !(t.map { isText($0["kind"]) && isText($0["id"]) } ?? false) { errors.append("target is null or { kind, id }") }
        }
        if !isText(v["summary"]) { errors.append("summary is empty") }
        let p = v["postcondition"] as? [String: Any]
        let pOk = p.map { bool($0["checked"]) != nil && ($0["holds"] is NSNull || bool($0["holds"]) != nil) && isText($0["how"]) } ?? false
        if !pOk { errors.append("postcondition needs checked, holds (true, false or null) and how") }
        let holds: Bool? = pOk ? bool(p?["holds"]) : nil
        let next = v["next"] as? [Any]
        if !(next?.allSatisfy(isStep) ?? false) { errors.append("every next step needs a command and a why") }
        let r = v["receipt"]
        let receipt = r as? [String: Any]
        let rOk = r is NSNull || (receipt.map { isText($0["id"]) && isText($0["at"]) && isText($0["by"]) && ($0["why"] is NSNull || $0["why"] is String) } ?? false)
        if !rOk { errors.append("receipt needs id, at, by and why (or null)") }
        let why = rOk ? receipt?["why"] : nil
        let hasReceipt = rOk && receipt != nil
        let hasNext = !(next ?? []).isEmpty
        let e = v["error"]
        let error = e as? [String: Any]
        let hasError = error.map { isText($0["code"]) && isText($0["message"]) } ?? false
        if e != nil && !hasError { errors.append("error needs a code and a message") }
        switch State(rawValue: state)! {
        case .done:
            if holds == false { errors.append("done, but the postcondition does not hold") }
            if pOk, bool(p?["checked"]) == false { warnings.append("done without an independent check: say what it rests on in postcondition.how") }
            if hasError { errors.append("done carries an error") }
        case .queued, .uncertain:
            if !hasReceipt { errors.append("\(state) needs a receipt, so the request can be found again") }
            if !hasNext { errors.append("\(state) needs a next step") }
            if state == "uncertain" && holds != nil { errors.append("uncertain, but the postcondition claims to know") }
        case .refused, .failed:
            if !hasError { errors.append("\(state) needs an error with a code and a message") }
            if holds == true { errors.append("\(state), but the postcondition says the effect holds") }
            if !hasNext && !(hasError && isText(error?["fix"])) { warnings.append("\(state) without a next step or a fix: say what to do instead") }
        case .needsHuman:
            let human = v["human"] as? [String: Any]
            if !(human.map { isText($0["reason"]) && isStep($0["resume"] as Any) } ?? false) { errors.append("needs-human needs human.reason and human.resume") }
        case .planned:
            if holds == true { errors.append("planned, but the postcondition says the effect holds") }
        }
        if effect == "others" && ["done", "queued", "uncertain"].contains(state) && !isText(why) {
            errors.append("an effect other people see needs a receipt with a why")
        }
        return .init(ok: errors.isEmpty, errors: errors, warnings: warnings)
    }

    private static func isText(_ value: Any?) -> Bool {
        guard let s = value as? String else { return false }
        return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A JSON boolean, never a number that happens to be 0 or 1.
    private static func bool(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    private static func isStep(_ value: Any) -> Bool {
        guard let s = value as? [String: Any] else { return false }
        return isText(s["command"]) && isText(s["why"])
    }
}
