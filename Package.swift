// swift-tools-version: 6.1
// Ouro HX and Ouro AX for Apple platforms. See README.md, AGENTS.md and docs/decisions/.

import PackageDescription

// The floor is what the code needs for most of its API: Observation-era SwiftUI (`@Entry`, `sensoryFeedback`,
// `Color.resolve(in:)`). Newer APIs (the iOS 27.1 hinge, AppIntentsTesting, the Siri AI preview) sit behind
// `#available` and SDK checks (`canImport(_, _version:)`), so the floor never rises for one feature.
let platforms: [SupportedPlatform] = [.iOS(.v18), .macOS(.v15)]

// Swift 6 language mode gives complete strict concurrency checking; ExistentialAny on top.
let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "OuroUIApple",
    platforms: platforms,
    products: [
        .library(name: "OuroHX", targets: ["OuroHX"]),
        .library(name: "OuroHXTesting", targets: ["OuroHXTesting"]),
        .library(name: "OuroAX", targets: ["OuroAX"]),
        .library(name: "OuroAXTesting", targets: ["OuroAXTesting"]),
        .library(name: "OuroAXTestingProbe", targets: ["OuroAXTestingProbe"]),
        .executable(name: "ouro-ax-xray", targets: ["ouro-ax-xray"]),
        .executable(name: "ouro-ax-skills", targets: ["ouro-ax-skills"]),
        .executable(name: "ouro-devicehub", targets: ["ouro-devicehub"]),
        .plugin(name: "OuroAXSkillsLintPlugin", targets: ["OuroAXSkillsLintPlugin"]),
    ],
    targets: [
        // Ouro HX for Apple: tokens (vendored from ouro-ui-core), theme, colour, motion, haptics, fold posture.
        .target(name: "OuroHX", swiftSettings: strict),
        // Test helpers for apps that use OuroHX: snapshots, accessibility audits, the iPhone Duo hinge.
        .target(
            name: "OuroHXTesting",
            dependencies: ["OuroHX", "OuroDeviceHub"],
            // Ouro HX's component claims, vendored from ouro-ui-core and pinned in core-provenance.json.
            resources: [.copy("Resources/components.claims.json")],
            swiftSettings: strict
        ),
        // Drives Xcode's Device Hub through accessibility (macOS only). Shared by OuroHXTesting and ouro-devicehub.
        .target(name: "OuroDeviceHub", swiftSettings: strict),
        .executableTarget(name: "ouro-devicehub", dependencies: ["OuroDeviceHub"], swiftSettings: strict),

        // Ouro AX for Apple: outcomes, problems, exit codes, entity helpers, the App Intents package hook.
        .target(name: "OuroAX", swiftSettings: strict),
        // Siri evaluation helpers and the App Intents X-ray: claims (vendored from ouro-ui-core), the metadata reader,
        // checks, reports and Siri scenario sets. It never links AppIntentsTesting, so a host command can use it.
        .target(
            name: "OuroAXTesting",
            dependencies: ["OuroAX", "OuroAXSkillsLint"],
            resources: [.copy("Resources/apple.claims.json")],
            swiftSettings: strict
        ),
        // The X-ray's behaviour stage: runs a probe plan with AppIntentsTesting. It links into a test bundle (see
        // Templates/XrayProbe), because AppIntentsTesting runs only there.
        .target(name: "OuroAXTestingProbe", dependencies: ["OuroAXTesting"], swiftSettings: strict),
        .executableTarget(name: "ouro-ax-xray", dependencies: ["OuroAXTesting"], swiftSettings: strict),
        // The app-skills bundle linter. It runs on the host (the build-tool plugin runs it at build time), so it reads
        // files with Foundation only and reports with OuroAX.Problem.
        .target(name: "OuroAXSkillsLint", dependencies: ["OuroAX"], swiftSettings: strict),
        .executableTarget(name: "ouro-ax-skills", dependencies: ["OuroAXSkillsLint"], swiftSettings: strict),
        .plugin(
            name: "OuroAXSkillsLintPlugin",
            capability: .buildTool(),
            dependencies: ["ouro-ax-skills"]
        ),

        .testTarget(name: "OuroHXTests", dependencies: ["OuroHX", "OuroHXTesting"], swiftSettings: strict),
        .testTarget(name: "OuroAXTests", dependencies: ["OuroAX", "OuroAXTesting"], swiftSettings: strict),
        .testTarget(
            name: "OuroAXTestingTests",
            dependencies: ["OuroAXTesting"],
            resources: [.copy("Fixtures")],
            swiftSettings: strict
        ),
        .testTarget(
            name: "OuroAXSkillsLintTests",
            dependencies: ["OuroAXSkillsLint"],
            resources: [.copy("Fixtures")],
            swiftSettings: strict
        ),
    ],
    swiftLanguageModes: [.v6]
)
