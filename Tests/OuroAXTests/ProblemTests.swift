import Foundation
import OuroAX
import Testing

// Mirrors registry/ouro/ax/problem.test.mts and exit-codes in ourostack/ouro-ui.

private let shape = OuroAX.Problem(code: "needs-why", exit: 2, thing: "send", problem: "needs --why.", fix: #"tool send abc "hi" --why "<who asked>""#)

@Suite struct ProblemTests {
    @Test func theLine() {
        #expect(shape.line(tool: "tool") == #"tool: send: needs --why. Fix: tool send abc "hi" --why "<who asked>"."#)
        #expect(OuroAX.Problem(code: "c", exit: 1, thing: "x", problem: "gone", fix: nil).message == "x: gone.")
        #expect(OuroAX.Problem(code: "c", exit: 1, thing: "x", problem: "a\nb", fix: nil).line(tool: "t") == "t: x: a b.")
    }

    @Test func isAnErrorWithItsMessageAndJSON() throws {
        let error: any Error = shape
        #expect((error as? OuroAX.Problem)?.exit == 2)
        #expect(error.localizedDescription == shape.message)
        #expect(String(describing: shape) == shape.message)
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(shape)) as? NSDictionary
        #expect(body == ["code": "needs-why", "exit": 2, "thing": "send", "problem": "needs --why.", "fix": shape.fix!, "message": shape.message])
        let wrapped = try JSONSerialization.jsonObject(with: shape.errorJSON()) as? NSDictionary
        #expect(wrapped?["error"] as? NSDictionary == body)
    }

    @Test func didYouMean() {
        #expect(OuroAX.Problem.didYouMean("lim", in: ["limit", "ids"]) == "limit")
        #expect(OuroAX.Problem.didYouMean("limt", in: ["limit", "ids"]) == "limit")
        #expect(OuroAX.Problem.didYouMean("whyy", in: ["why", "agent"]) == "why")
        #expect(OuroAX.Problem.didYouMean("zzzzzz", in: ["limit", "ids"]) == nil)
        #expect(OuroAX.Problem.didYouMean("", in: ["a"]) == nil)
    }

    @Test func commandLineQuotesOnlyWhatAShellWouldSplit() {
        #expect(OuroAX.commandLine(["t", "look", "abc123#17", "--ids", "1,2", "<conversation>", "two words", #"say "hi" $x"#]) == #"t look abc123#17 --ids 1,2 <conversation> "two words" "say \"hi\" \$x""#)
    }

    @Test func exitTableRules() throws {
        let table = try OuroAX.ExitTable(OuroAX.ExitCode.base + [OuroAX.ExitCode.findings])
        #expect(table.line() == "Exit codes: 0 ok, 1 error, 2 usage, 3 findings.")
        #expect(try table.code("findings") == 3)
        #expect(throws: OuroAX.Problem.self) { try table.code("nope") }
        #expect(throws: OuroAX.Problem.self) { try OuroAX.ExitTable([.init(code: 1, name: "error", short: "e", meaning: "e")]) }
        #expect(throws: OuroAX.Problem.self) { try OuroAX.ExitTable([.init(code: 0, name: "fine", short: "ok", meaning: "ok"), OuroAX.ExitCode.base[1], OuroAX.ExitCode.base[2]]) }
        #expect(throws: OuroAX.Problem.self) { try OuroAX.ExitTable(Array(OuroAX.ExitCode.base.prefix(2))) }
        #expect(throws: OuroAX.Problem.self) { try OuroAX.ExitTable(OuroAX.ExitCode.base + [.init(code: 3, name: "ok", short: "x", meaning: "x")]) }
    }
}
