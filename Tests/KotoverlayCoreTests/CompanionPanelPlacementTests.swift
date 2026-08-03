import CoreGraphics
import Testing
@testable import KotoverlayCore

@Suite("Companion panel placement")
struct CompanionPanelPlacementTests {
    @Test("Converts ScreenCaptureKit coordinates to AppKit coordinates")
    func coordinateConversion() {
        let converted = ScreenCoordinateConverter.appKitRect(
            from: CGRect(x: 100, y: 50, width: 800, height: 600),
            mainScreenMaxY: 1080
        )
        #expect(converted == CGRect(x: 100, y: 430, width: 800, height: 600))
    }

    @Test("Places the panel on the right when space is available")
    func rightPlacement() {
        let frame = CompanionPanelPlacement.frame(
            beside: CGRect(x: 100, y: 100, width: 800, height: 700),
            panelSize: CGSize(width: 320, height: 600),
            visibleScreens: [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        )
        #expect(frame == CGRect(x: 908, y: 200, width: 320, height: 600))
    }

    @Test("Falls back to the left and clamps to the visible screen")
    func leftPlacement() {
        let frame = CompanionPanelPlacement.frame(
            beside: CGRect(x: 600, y: 20, width: 800, height: 850),
            panelSize: CGSize(width: 360, height: 1_000),
            visibleScreens: [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        )
        #expect(frame == CGRect(x: 232, y: 0, width: 360, height: 900))
    }
}
