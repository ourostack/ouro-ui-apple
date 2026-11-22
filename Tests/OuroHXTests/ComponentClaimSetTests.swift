import OuroHXTesting
import Testing

/// The HX component claims vendored from ouro-ui-core v1.9.0 (`components.claims.json`, pinned in
/// core-provenance.json) load, with the nine claims core's page lists.
@Suite struct ComponentClaimSetTests {
    @Test func theVendoredSetLoads() throws {
        let set = try OuroHXClaims.components()
        #expect(set.version == "0.9.0")
        #expect(set.claims.map(\.id) == ["target.touch", "motion.reduced", "name.spoken", "text.reflows", "contrast.text", "announce.urgency", "toast.action-stays", "dismiss.reachable", "content.holds-still"])
        let touch = try #require(set.claim("target.touch"))
        #expect(touch.tier == .must)
        #expect(touch.appliesTo.starts(with: ["button", "empty", "alert", "sheet", "toast", "text-field", "segmented-control", "checkbox", "sync-status"]))
        #expect(set.claim("content.holds-still")?.appliesTo == ["immersive-controls"])
        #expect(touch.checks["apple"]?.isEmpty == false)
        #expect(set.claim("announce.urgency")?.tier == .should)
    }
}
