import OuroHXTesting
import Testing

/// The HX component claims vendored from ouro-ui-core v0.13.1 (`components.claims.json`, pinned in
/// core-provenance.json) load, with the eight claims core's page lists.
@Suite struct ComponentClaimSetTests {
    @Test func theVendoredSetLoads() throws {
        let set = try OuroHXClaims.components()
        #expect(set.version == "0.4.0")
        #expect(set.claims.map(\.id) == ["target.touch", "motion.reduced", "name.spoken", "text.reflows", "contrast.text", "announce.urgency", "toast.action-stays", "dismiss.reachable"])
        let touch = try #require(set.claim("target.touch"))
        #expect(touch.tier == .must)
        #expect(touch.appliesTo == ["button", "empty", "alert", "sheet", "toast", "text-field", "segmented-control", "checkbox", "sync-status"])
        #expect(touch.checks["apple"]?.isEmpty == false)
        #expect(set.claim("announce.urgency")?.tier == .should)
    }
}
