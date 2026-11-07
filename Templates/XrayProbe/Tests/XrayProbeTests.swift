import Foundation
import OuroAXTesting
import OuroAXTestingProbe
import XCTest

/// Runs the plan in OURO_AX_PLAN against the app it names and prints the result between OURO-AX-PROBE markers,
/// which `ouro-ax-xray --probe <log>` reads. Set OURO_AX_DISPOSABLE=1 only on a device made for the run.
final class XrayProbeTests: XCTestCase {
    @MainActor
    func testProbe() async throws {
        #if canImport(AppIntentsTesting)
        guard #available(iOS 27.0, macOS 27.0, *) else { throw XCTSkip("AppIntentsTesting needs iOS 27 or macOS 27") }
        let env = ProcessInfo.processInfo.environment
        guard let plan = try XrayProbe.planFromEnvironment(env) else {
            throw XCTSkip("no plan: set TEST_RUNNER_OURO_AX_PLAN to the output of `ouro-ax-xray plan --app <path.app>`")
        }
        // XCTest must launch the app: that is what gives AppIntentsTesting a runner service in it to talk to.
        let app = XCUIApplication(bundleIdentifier: plan.bundleIdentifier)
        // A launch can fail inside XCTest (no process ID). Carry on past it to say so plainly, so the log and the
        // script's retry tell "the probe could not reach the app" from the app failing a claim.
        continueAfterFailure = true
        defer { app.terminate() }
        app.launch()
        guard app.wait(for: .runningForeground, timeout: 30) else {
            print("OURO-AX-PROBE-UNREACHED the app never reached the foreground (state \(app.state.rawValue)), so the probe could not reach it")
            XCTFail("the probe could not reach the app: it never reached the foreground (state \(app.state.rawValue))")
            return
        }
        continueAfterFailure = false
        #if os(iOS)
        let platform = "iOS"
        #else
        let platform = "macOS"
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let ranOn = env["OURO_AX_RAN_ON"] ?? "\(platform) \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let result = await XrayProbe.run(plan, ranOn: ranOn, refusalsAllowed: env[XrayProbe.disposableVariable] == "1")
        print(try result.logLines())
        XCTAssertFalse(result.steps.isEmpty, "the probe ran nothing")
        #else
        throw XCTSkip("this Xcode has no AppIntentsTesting")
        #endif
    }
}
