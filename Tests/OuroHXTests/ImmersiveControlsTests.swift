@testable import OuroHX
import SwiftUI
import Testing

/// Controls over immersive content (`.ouroImmersiveControls`) stand in the bands the hardware takes and never on the
/// content's layout. The geometry is the folded iPhone Duo's cover screen as iOS 27.2's simulator reports it (466 by
/// 678 points, a status column of 84 by 82 at the top trailing corner with the camera in it), an iPad's and an iPhone's.
@Suite struct ImmersiveControlsTests {
    typealias Placement = OuroImmersiveControlsPlacement
    let cover = CGSize(width: 466, height: 678)
    let column = CGRect(x: 382, y: 0, width: 84, height: 82)
    let camera = CGRect(x: 399.7, y: 29.3, width: 37, height: 37)

    @Test("the top bar stands beside the camera's housing, at the top of the screen")
    func topBarBesideTheHousing() {
        let p = Placement.resolve(size: cover, safeArea: EdgeInsets(), occlusions: [column, camera], topHeight: 44, bottomHeight: 44)
        #expect(p.top == CGRect(x: 16, y: 8, width: 382 - 16 - 16, height: 44))
        #expect(!p.top.intersects(column) && !p.top.intersects(camera))
    }

    @Test("the bottom bar uses the width under the housing")
    func bottomBarUsesTheWidthUnderTheHousing() {
        // Reported as a trailing safe inset too: the housing explains it, and the housing is far above this bar.
        let safe = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 84)
        let p = Placement.resolve(size: cover, safeArea: safe, occlusions: [column, camera], topHeight: 44, bottomHeight: 44)
        #expect(p.bottom == CGRect(x: 16, y: 678 - 8 - 44, width: 466 - 32, height: 44))
        #expect(p.top.maxX <= 382 - 16)
    }

    @Test("bars sit in the safe area's bands: under the status bar, over the home indicator")
    func barsInTheSafeAreaBands() {
        let iPad = Placement.resolve(size: CGSize(width: 1032, height: 1376), safeArea: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0),
                                     topHeight: 44, bottomHeight: 50)
        #expect(iPad.top == CGRect(x: 16, y: 24, width: 1000, height: 44))
        #expect(iPad.bottom == CGRect(x: 16, y: 1376 - 13 - 50, width: 1000, height: 50))
    }

    @Test("a side inset with nothing reported in it is kept: an iPhone on its side keeps clear of its island")
    func unexplainedInsetIsKept() {
        let p = Placement.resolve(size: CGSize(width: 874, height: 402), safeArea: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62),
                                  topHeight: 44, bottomHeight: 44)
        #expect(p.top.minX == 62 + 16 && p.top.maxX == 874 - 62 - 16)
        #expect(p.bottom.minX == 62 + 16 && p.bottom.maxX == 874 - 62 - 16)
    }

    @Test("a housing across the middle of the top puts the top bar below it")
    func housingAcrossTheMiddle() {
        let island = CGRect(x: 140, y: 11, width: 126, height: 37)
        let p = Placement.resolve(size: CGSize(width: 402, height: 874), safeArea: EdgeInsets(), occlusions: [island], topHeight: 44, bottomHeight: 44)
        #expect(p.top.minY == island.maxY + 8)
        #expect(p.top.minX == 16 && p.top.width == 402 - 32)
    }

    @Test("a band the safe area already holds (an iPad's status bar) leaves the top bar at the safe area's top")
    func bandInsideTheSafeArea() {
        let status = CGRect(x: 0, y: 0, width: 1032, height: 32)
        let p = Placement.resolve(size: CGSize(width: 1032, height: 1376), safeArea: EdgeInsets(top: 32, leading: 0, bottom: 20, trailing: 0),
                                  occlusions: [status], topHeight: 44, bottomHeight: 44)
        #expect(p.top == CGRect(x: 16, y: 32, width: 1000, height: 44))
        #expect(p.bottom == CGRect(x: 16, y: 1376 - 13 - 44, width: 1000, height: 44))
    }

    @Test("the bottom bar rests on the home indicator, in the band it takes, never above the safe area's whole foot")
    func bottomBarOnTheHomeIndicator() {
        let phone = Placement.resolve(size: CGSize(width: 466, height: 678), safeArea: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 0),
                                      topHeight: 44, bottomHeight: 44)
        #expect(phone.bottom == CGRect(x: 16, y: 678 - 13 - 44, width: 466 - 32, height: 44))
        #expect(OuroImmersiveControlsMetrics.homeIndicatorBand == 13)
        // A screen with no home indicator keeps the edge gap.
        let bare = Placement.resolve(size: CGSize(width: 466, height: 678), safeArea: EdgeInsets(), topHeight: 44, bottomHeight: 44)
        #expect(bare.bottom == CGRect(x: 16, y: 678 - 8 - 44, width: 466 - 32, height: 44))
    }

    @Test("bars slide in from their own edges, and crossfade under Reduce Motion")
    func motion() {
        #expect(OuroImmersiveControlsMetrics.appearance(.top, reduceMotion: false) == .move(edge: .top))
        #expect(OuroImmersiveControlsMetrics.appearance(.bottom, reduceMotion: false) == .move(edge: .bottom))
        #expect(OuroImmersiveControlsMetrics.appearance(.top, reduceMotion: true) == .fade)
        #expect(OuroImmersiveControlsMetrics.appearance(.bottom, reduceMotion: true).step(reduceMotion: true)
                == .crossfade(duration: OuroTokens.Duration.base))
    }

    /// The modifier draws the bars in an overlay, which is sized to the content and never changes its layout: the
    /// content measures the same with the bars up and down.
    #if os(macOS)
    @MainActor @Test("showing the bars leaves the content's size and place alone")
    func contentHoldsStill() {
        func measured(_ shown: Bool) -> CGSize {
            let content = Color.clear.frame(width: 300, height: 500)
                .ouroImmersiveControls(isPresented: shown) { Text("Close") } bottom: { Text("Share") }
            let host = NSHostingController(rootView: content)
            return host.sizeThatFits(in: CGSize(width: 1000, height: 1000))
        }
        #expect(measured(false) == CGSize(width: 300, height: 500))
        #expect(measured(true) == measured(false))
    }
    #endif
}
