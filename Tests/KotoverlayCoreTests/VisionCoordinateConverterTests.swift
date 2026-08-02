import CoreGraphics
import Testing
@testable import KotoverlayCore

@Suite("Vision coordinate conversion")
struct VisionCoordinateConverterTests {
    @Test("Converts bottom-left Vision coordinates to top-left screen coordinates")
    func convertsCoordinateSystem() {
        let window = CGRect(x: 100, y: 50, width: 1_000, height: 800)
        let vision = CGRect(x: 0.1, y: 0.25, width: 0.4, height: 0.2)

        let result = VisionCoordinateConverter.screenRect(for: vision, in: window)

        #expect(abs(result.minX - 200) < 0.001)
        #expect(abs(result.minY - 490) < 0.001)
        #expect(abs(result.width - 400) < 0.001)
        #expect(abs(result.height - 160) < 0.001)
    }

    @Test("Preserves full-window bounds")
    func fullWindowBounds() {
        let window = CGRect(x: -300, y: 24, width: 1_440, height: 900)
        let result = VisionCoordinateConverter.screenRect(
            for: CGRect(x: 0, y: 0, width: 1, height: 1),
            in: window
        )
        #expect(result == window)
    }

    @Test("Recognition regions are clipped to normalized image bounds")
    func clipsRecognitionRegion() {
        let options = VisionRecognitionOptions(
            regionOfInterest: CGRect(x: -0.5, y: 0.25, width: 1, height: 1)
        )
        #expect(options.regionOfInterest == CGRect(x: 0, y: 0.25, width: 0.5, height: 0.75))
    }

    @Test("Maps region-relative observations back to the full image")
    func remapsRegionObservation() {
        let region = CGRect(x: 0.2, y: 0.08, width: 0.79, height: 0.86)
        let result = VisionCoordinateConverter.imageNormalizedRect(
            for: CGRect(x: 0, y: 0, width: 1, height: 1),
            in: region
        )
        #expect(result == region)
    }
}
