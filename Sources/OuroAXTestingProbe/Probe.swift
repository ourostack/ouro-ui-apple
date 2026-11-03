// The X-ray's behaviour stage. It runs a probe plan against a live app with AppIntentsTesting, out of process and by
// bundle identifier, and returns what it saw. It runs inside a test bundle (Templates/XrayProbe), because that is
// where AppIntentsTesting runs, and with an Xcode whose AppIntentsTesting matches the OS (see the decision record).
public import OuroAXTesting

#if canImport(AppIntentsTesting)
import AppIntents
import AppIntentsTesting
import Foundation

@available(iOS 27.0, macOS 27.0, *)
public enum XrayProbe {
    /// The environment variable that carries the plan, base64 JSON. A test plan sets `TEST_RUNNER_OURO_AX_PLAN`, which
    /// xcodebuild passes to the test process without the prefix.
    public static let planVariable = "OURO_AX_PLAN"
    /// Set to 1 to allow refusal runs; only on a device made for the run.
    public static let disposableVariable = "OURO_AX_DISPOSABLE"

    /// The plan from the environment, or nil when there is none.
    public static func planFromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> AXXray.ProbePlan? {
        guard let text = environment[planVariable], let data = Data(base64Encoded: text) else { return nil }
        return try JSONDecoder().decode(AXXray.ProbePlan.self, from: data)
    }

    static func describe(_ error: any Error) -> String {
        let localized = (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
        return localized.isEmpty ? String(describing: error) : localized
    }

    /// Runs the plan. Every entity probe is a read. Refusal runs happen only when `refusalsAllowed`, and give each
    /// intent entity references made up so nothing can match them.
    public static func run(_ plan: AXXray.ProbePlan, ranOn: String, refusalsAllowed: Bool) async -> AXXray.ProbeResult {
        let defs = IntentDefinitions(bundleIdentifier: plan.bundleIdentifier)
        var steps: [AXXray.ProbeResult.Step] = []
        for e in plan.entities {
            let def = defs.entities[e.typeName]
            var seen: [AnyAppEntity] = []
            do {
                let suggested = try await def.suggestedEntities()
                seen += suggested
                steps.append(.init(subject: e.typeName, probe: "suggested", count: suggested.count))
            } catch { steps.append(.init(subject: e.typeName, probe: "suggested", error: describe(error))) }
            if e.enumerable {
                do {
                    let all = try await def.allEntities()
                    seen += all
                    steps.append(.init(subject: e.typeName, probe: "all", count: all.count))
                } catch { steps.append(.init(subject: e.typeName, probe: "all", error: describe(error))) }
            }
            var ids: [String] = []
            for x in seen where !ids.contains(x.identifier.instanceIdentifier) && ids.count < 10 { ids.append(x.identifier.instanceIdentifier) }
            if ids.isEmpty {
                steps.append(.init(subject: e.typeName, probe: "identifiers", count: 0, asked: 0))
            } else {
                do {
                    let found = try await def.entities(identifiers: ids)
                    let got = Set(found.map(\.identifier.instanceIdentifier)).intersection(ids).count
                    steps.append(.init(subject: e.typeName, probe: "identifiers", count: got, asked: ids.count))
                } catch { steps.append(.init(subject: e.typeName, probe: "identifiers", asked: ids.count, error: describe(error))) }
            }
            if e.indexed {
                do { steps.append(.init(subject: e.typeName, probe: "spotlight", count: try await def.spotlightQuery(nil).count)) }
                catch { steps.append(.init(subject: e.typeName, probe: "spotlight", error: describe(error))) }
            }
            do { steps.append(.init(subject: e.typeName, probe: "view-annotations", count: try await def.viewAnnotations().count)) }
            catch { steps.append(.init(subject: e.typeName, probe: "view-annotations", error: describe(error))) }
            if e.transferable, let first = seen.first {
                do {
                    let file = try await first.exported(as: nil)
                    let back = try await def.resolved(from: file)
                    steps.append(back.identifier == first.identifier
                        ? .init(subject: e.typeName, probe: "export-resolve", note: "exported \(first.identifier.instanceIdentifier) as \(file.type?.identifier ?? "a file") and read it back")
                        : .init(subject: e.typeName, probe: "export-resolve", error: "exported \(first.identifier.instanceIdentifier), but it read back as \(back.identifier.instanceIdentifier)"))
                } catch { steps.append(.init(subject: e.typeName, probe: "export-resolve", error: "export or read-back threw: \(describe(error))")) }
            }
        }
        if refusalsAllowed {
            for r in plan.refusals {
                let refs = r.entityParameters.sorted { $0.key < $1.key }.map { ($0.key, defs.entities[$0.value].makeReference(identifier: plan.missingIdentifier) as (any IntentValueExpressing)?) }
                let make = defs.intents[r.intent].makeIntent
                let intent: AnyAppIntent
                switch refs.count {
                case 1: intent = make.dynamicallyCall(withKeywordArguments: [refs[0].0: refs[0].1])
                case 2: intent = make.dynamicallyCall(withKeywordArguments: [refs[0].0: refs[0].1, refs[1].0: refs[1].1])
                default:
                    steps.append(.init(subject: r.intent, probe: "refusal-skipped", note: "takes \(refs.count) entities; the probe gives at most two"))
                    continue
                }
                do {
                    _ = try await intent.run()
                    steps.append(.init(subject: r.intent, probe: "refusal", note: "ran"))
                } catch {
                    steps.append(.init(subject: r.intent, probe: "refusal", error: describe(error), note: String(describing: error)))
                }
            }
        }
        return .init(bundleIdentifier: plan.bundleIdentifier, ranOn: ranOn, refusalsAllowed: refusalsAllowed, steps: steps)
    }
}
#endif
