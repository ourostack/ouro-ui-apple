import Foundation
import OuroAX
import Testing

// Mirrors registry/ouro/ax/outcome.test.mts in ourostack/ouro-ui, case for case, so the Swift envelope and the
// TypeScript one agree on shape and meaning.

private let at = "2026-10-30T20:00:00.000Z"
private let receipt = OuroAX.Receipt(id: "a1b2c3d4e5f6", at: at, by: "agent:planner", why: "Jo asked: tell Design sync I'm running late")
private let look = OuroAX.NextStep("tool look abc123 --json", why: "see whether the message is there")
private let err = OuroAX.Problem(code: "why", exit: 2, thing: "send", problem: "say why", fix: nil)

private func sent(_ change: (inout OuroAX.Outcome) -> Void = { _ in }) -> OuroAX.Outcome {
    var o = OuroAX.Outcome(
        action: "message.send",
        state: .done,
        summary: "Sent to Design sync.",
        effect: .others,
        audience: .init(only: false, who: "everyone in Design sync"),
        target: .init(kind: "conversation", id: "19:abc", name: "Design sync"),
        postcondition: .init(checked: true, holds: true, how: "the message is in the tool's copy of Design sync"),
        receipt: receipt,
        next: [look]
    )
    change(&o)
    return o
}

private func json(_ value: some Encodable) throws -> NSDictionary {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

@Suite struct OutcomeTests {
    @Test func honestDefaultsAndTheWireShape() throws {
        let o = OuroAX.Outcome(action: "draft.edit", state: .done, summary: "Draft saved.")
        let expected: NSDictionary = [
            "ax": "outcome/1", "action": "draft.edit", "effect": "private", "audience": ["only": true, "who": "only you"],
            "target": NSNull(), "state": "done", "summary": "Draft saved.",
            "postcondition": ["checked": false, "holds": NSNull(), "how": "not checked"], "receipt": NSNull(), "next": [Any](),
        ]
        #expect(try json(o) == expected)
        let h = OuroAX.Outcome(action: "x", state: .needsHuman, summary: "s", error: err, human: .init(reason: "2FA", resume: look))
        let body = try json(h)
        #expect(body["state"] as? String == "needs-human")
        #expect(body["error"] as? NSDictionary == ["code": "why", "exit": 2, "thing": "send", "problem": "say why", "fix": NSNull(), "message": "send: say why."])
        #expect((body["human"] as? NSDictionary)?["reason"] as? String == "2FA")
    }

    @Test func roundTripsThroughJSON() throws {
        let o = sent { $0.state = .refused; $0.error = err }
        let back = try JSONDecoder().decode(OuroAX.Outcome.self, from: JSONEncoder().encode(o))
        #expect(back == o)
        let fromTypeScript = #"{"ax":"outcome/1","action":"x","effect":"private","audience":{"only":true,"who":"only you"},"target":null,"state":"needs-human","summary":"s","postcondition":{"checked":false,"holds":null,"how":"not checked"},"receipt":null,"next":[{"command":"tool look","why":"w","sourceCheckout":true}],"human":{"reason":"r","resume":{"command":"tool look","why":"w"}}}"#
        let decoded = try JSONDecoder().decode(OuroAX.Outcome.self, from: Data(fromTypeScript.utf8))
        #expect(decoded.state == .needsHuman)
        #expect(decoded.next.first?.sourceCheckout == true)
        #expect(decoded.human?.resume.sourceCheckout == false)
    }

    @Test func validatePassesACheckedReceivedSendAndRejectsWhatIsNotAnEnvelope() throws {
        #expect(sent().validate() == .init(ok: true, errors: [], warnings: []))
        for v: Any in [NSNull(), [Any](), ["ax": "other"], ["ax": "outcome/1", "state": "maybe"]] as [Any] {
            #expect(OuroAX.Outcome.validate(jsonObject: v).errors.first?.hasPrefix("not an outcome/1 envelope") == true)
        }
    }

    @Test func validateNamesEveryBrokenField() throws {
        let good = try json(sent()).mutableCopy() as! NSMutableDictionary
        good["action"] = ""
        good["effect"] = "public"
        good["audience"] = ["only": "no", "who": ""]
        good["target"] = ["kind": "x"]
        good["summary"] = " "
        good["postcondition"] = ["checked": true]
        good["next"] = [["command": "x"]]
        good["receipt"] = ["id": ""]
        good["error"] = ["code": ""]
        #expect(OuroAX.Outcome.validate(jsonObject: good).errors == [
            "action is empty",
            #"effect is "private" or "others""#,
            "audience needs only (true or false) and who (words)",
            "target is null or { kind, id }",
            "summary is empty",
            "postcondition needs checked, holds (true, false or null) and how",
            "every next step needs a command and a why",
            "receipt needs id, at, by and why (or null)",
            "error needs a code and a message",
        ])
        let noAudience = try json(sent()).mutableCopy() as! NSMutableDictionary
        noAudience["audience"] = NSNull()
        #expect(OuroAX.Outcome.validate(jsonObject: noAudience).errors.first == "audience needs only (true or false) and who (words)")
        let badNext = try json(sent()).mutableCopy() as! NSMutableDictionary
        badNext["next"] = "x"
        badNext["postcondition"] = NSNull()
        #expect(OuroAX.Outcome.validate(jsonObject: badNext).errors == ["postcondition needs checked, holds (true, false or null) and how", "every next step needs a command and a why"])
    }

    @Test func theRules() {
        #expect(OuroAX.Outcome(action: "draft.edit", state: .done, summary: "s", postcondition: .init(checked: true, holds: true, how: "read back"), receipt: .init(id: receipt.id, at: at, by: receipt.by, why: nil)).validate().ok)
        #expect(sent { $0.audience = .onlyYou }.validate().errors.contains("an effect other people see cannot have an audience of only you"))
        #expect(sent { $0.postcondition = .init(checked: true, holds: false, how: "not there") }.validate().errors.contains("done, but the postcondition does not hold"))
        let unchecked = sent { $0.postcondition = .init(checked: false, holds: nil, how: "the window's report") }.validate()
        #expect(unchecked.ok)
        #expect(unchecked.warnings == ["done without an independent check: say what it rests on in postcondition.how"])
        #expect(sent { $0.error = err }.validate().errors.contains("done carries an error"))
        for state in [OuroAX.Outcome.State.queued, .uncertain] {
            let r = sent { $0.state = state; $0.postcondition = .init(checked: false, holds: nil, how: "not yet"); $0.receipt = nil; $0.next = [] }.validate()
            #expect(r.errors == ["\(state.rawValue) needs a receipt, so the request can be found again", "\(state.rawValue) needs a next step", "an effect other people see needs a receipt with a why"])
        }
        #expect(sent { $0.state = .uncertain }.validate().errors == ["uncertain, but the postcondition claims to know"])
        for state in [OuroAX.Outcome.State.refused, .failed] {
            let r = sent { $0.state = state; $0.next = [] }.validate()
            #expect(r.errors == ["\(state.rawValue) needs an error with a code and a message", "\(state.rawValue), but the postcondition says the effect holds"])
            #expect(r.warnings == ["\(state.rawValue) without a next step or a fix: say what to do instead"])
        }
        #expect(sent {
            $0.state = .refused; $0.receipt = nil; $0.next = []
            $0.error = OuroAX.Problem(code: "why", exit: 2, thing: "send", problem: "say why", fix: "tool send --why x")
            $0.postcondition = .init(checked: true, holds: false, how: "nothing was queued")
        }.validate().ok)
        #expect(sent { $0.state = .needsHuman }.validate().errors == ["needs-human needs human.reason and human.resume"])
        #expect(!sent { $0.state = .needsHuman; $0.human = .init(reason: "", resume: look) }.validate().ok)
        #expect(sent { $0.state = .needsHuman; $0.human = .init(reason: "Only the person turns writes on.", resume: look) }.validate().ok)
        #expect(sent { $0.state = .planned }.validate().errors == ["planned, but the postcondition says the effect holds"])
        #expect(sent { $0.state = .planned; $0.receipt = nil; $0.postcondition = .init(checked: false, holds: nil, how: "a plan") }.validate().ok)
        #expect(sent { $0.receipt = .init(id: receipt.id, at: at, by: receipt.by, why: " ") }.validate().errors == ["an effect other people see needs a receipt with a why"])
    }

    @Test func exitCodes() throws {
        let exits = try OuroAX.ExitTable(OuroAX.ExitCode.base + [.init(code: 3, name: "possibly done", short: "possibly done", meaning: "maybe")])
        #expect(try OuroAX.Outcome.State.allCases.map { state in try sent { $0.state = state }.exitCode(in: exits) } == [0, 0, 0, 0, 1, 2, 1])
        #expect(try sent { $0.state = .refused; $0.error = OuroAX.Problem(code: "why", exit: 3, thing: "send", problem: "say why", fix: nil) }.exitCode(in: exits) == 3)
        var names = OuroAX.Outcome.defaultExits
        names[.uncertain] = "possibly done"
        #expect(try sent { $0.state = .uncertain }.exitCode(in: exits, names: names) == 3)
    }

    @Test func text() {
        #expect(sent().text(tool: "tool") == "Sent to Design sync.\nChecked: the message is in the tool's copy of Design sync.\nReceipt: a1b2c3d4e5f6\nNext: tool look abc123 --json  (see whether the message is there)")
        let human = OuroAX.Outcome(action: "x", state: .needsHuman, summary: "Writes are off.", human: .init(reason: "Only the person turns writes on.", resume: look))
        #expect(human.text(tool: "tool") == "Writes are off.\nNeeds the person: Only the person turns writes on. Then: tool look abc123 --json")
        #expect(OuroAX.Outcome(action: "x", state: .refused, summary: "No.", error: .init(code: "why", exit: 2, thing: "send", problem: "say why", fix: "tool send --why x")).text(tool: "tool") == "tool: send: say why. Fix: tool send --why x.")
        #expect(sent { $0.state = .failed; $0.postcondition = .init(checked: true, holds: false, how: "not there.") }.text(tool: "tool").split(separator: "\n")[1] == "Checked: not there (it does not hold).")
        #expect(sent { $0.postcondition = .init(checked: false, holds: nil, how: "the window has not sent it yet") }.text(tool: "tool").split(separator: "\n")[1] == "Not checked yet: the window has not sent it yet.")
        #expect(sent { $0.postcondition = .init(checked: true, holds: nil, how: "not readable until the next sync") }.text(tool: "tool").split(separator: "\n")[1] == "Not checked yet: not readable until the next sync.")
    }

    @Test func genericAudienceIsWarned() {
        for who in ["other people", "Others.", " someone ", "Everyone", "users"] { #expect(OuroAX.Audience.isGeneric(who), "\(who)") }
        for who in [#"everyone in "Design sync""#, "Jo Park", "the organizer, Alex Example", "the team"] { #expect(!OuroAX.Audience.isGeneric(who), "\(who)") }
        let generic = sent { $0.audience = .init(only: false, who: "other people") }.validate()
        #expect(generic.ok)
        #expect(generic.warnings == [#"audience.who is "other people", which names no one: say who will see it, as the text does (everyone in "Design sync", Jo Park)"#])
        #expect(OuroAX.Outcome(action: "note", state: .done, summary: "Noted.", audience: .init(only: false, who: "someone"), postcondition: .init(checked: true, holds: true, how: "read back")).validate().warnings == [])
    }
}

@Suite struct ValidationParityTests {
    /// As in the TypeScript kit, `target` and `receipt` must be present (null is fine; missing is not).
    @Test func missingTargetOrReceiptFailsLikeTypeScript() throws {
        let good = try JSONSerialization.jsonObject(with: JSONEncoder().encode(OuroAX.Outcome(action: "x", state: .done, summary: "s"))) as! [String: Any]
        #expect(OuroAX.Outcome.validate(jsonObject: good).ok)
        var noTarget = good
        noTarget.removeValue(forKey: "target")
        #expect(OuroAX.Outcome.validate(jsonObject: noTarget).errors.contains("target is null or { kind, id }"))
        var noReceipt = good
        noReceipt.removeValue(forKey: "receipt")
        #expect(OuroAX.Outcome.validate(jsonObject: noReceipt).errors.contains("receipt needs id, at, by and why (or null)"))
    }
}
