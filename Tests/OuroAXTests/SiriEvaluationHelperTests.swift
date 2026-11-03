import OuroAX
import OuroAXTesting
import Testing

@Suite struct SiriEvaluationHelperTests {
    @Test func wordingsCoverTheFourKindsInOrder() {
        let w = OuroAXTesting.Wordings(
            direct: ["Add milk to my Spoonjoy list"],
            indirect: ["We're out of milk"],
            incomplete: ["Add something to my list"],
            unexpected: ["Add milk to my Spoonjoy list in Klingon"]
        )
        #expect(w.all.map(\.kind) == [.direct, .indirect, .incomplete, .unexpected])
        #expect(w.all.map(\.text).first == "Add milk to my Spoonjoy list")
        #expect(w.missingKinds.isEmpty)
        #expect(OuroAXTesting.Wordings(direct: ["x"]).missingKinds == [.indirect, .incomplete, .unexpected])
    }

    @Test func passRatesAreOverRepeatedRuns() throws {
        #expect(OuroAXTesting.recommendedRuns == 5)
        let rate = OuroAXTesting.PassRate(passes: [true, true, false, true, true])
        #expect(rate.runs == 5)
        #expect(rate.passed == 4)
        #expect(rate.value == 0.8)
        #expect(rate.meets(0.8))
        #expect(!rate.meets(0.9))
        #expect(rate.description == "4/5 runs passed (80%)")
        #expect(!OuroAXTesting.PassRate(passes: []).meets(0))
        let problem = try #require(rate.problem(scenario: "add milk", threshold: 0.9))
        #expect(problem.code == "pass-rate")
        #expect(problem.exit == 3)
        #expect(problem.message == "add milk: 4/5 runs passed (80%), under 90%. Fix: read the failing runs' transcripts and tighten the intent's title, description or app skill.")
        #expect(rate.problem(scenario: "add milk", threshold: 0.8) == nil)
    }
}
