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
        #if os(iOS)
        let app = XCUIApplication(bundleIdentifier: plan.bundleIdentifier)
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 30)
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
