import CoreGraphics
import OuroHX
import Testing

private let tall = CGSize(width: 600, height: 800)
private let wide = CGSize(width: 800, height: 600)

@Suite struct FoldPostureTests {
    @Test func noHingeIsOnePage() {
        #expect(OuroFoldPosture.resolve(size: tall, hinge: .none, regions: []) == .single)
        #expect(OuroFoldPosture.resolve(size: CGSize(width: 1200, height: 800), hinge: .none, regions: []) == .single)
    }

    @Test func closedIsClosed() {
        #expect(OuroFoldPosture.resolve(size: tall, hinge: .closed, regions: [.init(frame: CGRect(x: 0, y: 399, width: 600, height: 2), isActive: true)]) == .closed)
    }

    @Test func anActiveHorizontalFoldStandsAsATabletop() throws {
        let posture = OuroFoldPosture.resolve(size: tall, hinge: .partiallyOpen(angleDegrees: 100), regions: [.init(frame: CGRect(x: 0, y: 390, width: 600, height: 20), isActive: true)])
        let split = try #require(posture.tabletop)
        #expect(split.source == .hardware)
        // A 20 pt fold widens to the 48 pt margin band, centred.
        #expect(split.fold == CGRect(x: 0, y: 376, width: 600, height: 48))
        #expect(split.first == CGRect(x: 0, y: 0, width: 600, height: 376))
        #expect(split.second == CGRect(x: 0, y: 424, width: 600, height: 376))
    }

    @Test func aBentHingeUsesAnInactiveFoldsRealPosition() throws {
        let split = try #require(OuroFoldPosture.resolve(size: tall, hinge: .partiallyOpen(angleDegrees: 100), regions: [.init(frame: CGRect(x: 0, y: 380, width: 600, height: 2), isActive: false)]).tabletop)
        #expect(split.source == .hardware)
        #expect(split.fold.midY == 381)
    }

    @Test func betweenTabletopAndFlatItStaysATabletop() {
        #expect(OuroFoldPosture.resolve(size: tall, hinge: .partiallyOpen(angleDegrees: 145), regions: []).tabletop != nil)
        #expect(OuroFoldPosture.resolve(size: tall, hinge: .partiallyOpen(angleDegrees: 150), regions: []) == .single)
    }

    @Test func anInactiveHorizontalFoldIsNotATabletop() {
        #expect(OuroFoldPosture.resolve(size: tall, hinge: .fullyOpen, regions: [.init(frame: CGRect(x: 0, y: 399, width: 600, height: 2), isActive: false)]) == .single)
    }

    @Test func aBentHingeWithNoRegionSplitsAtTheMiddle() throws {
        let split = try #require(OuroFoldPosture.resolve(size: tall, hinge: .partiallyOpen(angleDegrees: 90), regions: []).tabletop)
        #expect(split.source == .screenMiddle)
        #expect(split.fold == CGRect(x: 0, y: 376, width: 600, height: 48))
        // Too shallow a bend to stand on, or no angle while fully open: one page.
        #expect(OuroFoldPosture.resolve(size: tall, hinge: .partiallyOpen(angleDegrees: 40), regions: []) == .single)
        #expect(OuroFoldPosture.resolve(size: tall, hinge: .partiallyOpen(angleDegrees: 160), regions: []) == .single)
        #expect(OuroFoldPosture.resolve(size: tall, hinge: .fullyOpen, regions: []) == .single)
    }

    @Test func aVerticalFoldOpensABookEvenWhenInactive() throws {
        let posture = OuroFoldPosture.resolve(size: wide, hinge: .fullyOpen, regions: [.init(frame: CGRect(x: 399, y: 0, width: 2, height: 600), isActive: false)])
        let split = try #require(posture.book)
        #expect(split.fold == CGRect(x: 376, y: 0, width: 48, height: 600))
        #expect(split.first == CGRect(x: 0, y: 0, width: 376, height: 600))
        #expect(split.second == CGRect(x: 424, y: 0, width: 376, height: 600))
    }

    @Test func anActiveRegionWinsOverAnInactiveOne() throws {
        let posture = OuroFoldPosture.resolve(size: wide, hinge: .fullyOpen, regions: [
            .init(frame: CGRect(x: 300, y: 0, width: 2, height: 600), isActive: false),
            .init(frame: CGRect(x: 399, y: 0, width: 2, height: 600), isActive: true),
        ])
        #expect(try #require(posture.book).fold.midX == 400)
    }

    @Test func panesShorterThanTheMinimumFallBackToOnePage() {
        let small = CGSize(width: 400, height: 500)
        #expect(OuroFoldPosture.resolve(size: small, hinge: .partiallyOpen(angleDegrees: 90), regions: []) == .single)
    }

    @Test func aRegionOutsideTheContainerIsIgnored() {
        #expect(OuroFoldPosture.resolve(size: wide, hinge: .fullyOpen, regions: [.init(frame: CGRect(x: 1200, y: 0, width: 2, height: 600), isActive: true)]) == .single)
    }

    @Test func theBendDeepensAsTheHingeCloses() {
        #expect(OuroHinge.none.bend == 0)
        #expect(OuroHinge.fullyOpen.bend == 0)
        #expect(OuroHinge.partiallyOpen(angleDegrees: 180).bend == 0)
        #expect(OuroHinge.partiallyOpen(angleDegrees: 135).bend == 0.5)
        #expect(OuroHinge.partiallyOpen(angleDegrees: 60).bend == 1)
    }
}
