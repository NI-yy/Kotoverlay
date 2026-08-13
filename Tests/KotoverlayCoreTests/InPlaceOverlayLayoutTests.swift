import CoreGraphics
import Testing
@testable import KotoverlayCore

@Suite("In-place overlay layout")
struct InPlaceOverlayLayoutTests {
    @Test("Reprojects OCR bounds when Discord moves and resizes")
    func reprojectsBounds() throws {
        let sourceWindow = CGRect(x: 100, y: 50, width: 1_000, height: 800)
        let sourceText = CGRect(x: 300, y: 250, width: 400, height: 40)
        let currentWindow = CGRect(x: 1_100, y: 100, width: 500, height: 400)

        let mapped = try #require(InPlaceOverlayLayout.reproject(
            sourceText,
            from: sourceWindow,
            to: currentWindow
        ))

        #expect(mapped == CGRect(x: 1_200, y: 200, width: 200, height: 20))
    }

    @Test("Rejects invalid source and destination windows")
    func rejectsInvalidWindows() {
        #expect(InPlaceOverlayLayout.reproject(
            CGRect(x: 1, y: 1, width: 10, height: 10),
            from: .zero,
            to: CGRect(x: 0, y: 0, width: 100, height: 100)
        ) == nil)
    }

    @Test("Requires positive intersection with Discord and a display")
    func visibility() {
        let discord = CGRect(x: 100, y: 100, width: 800, height: 600)
        let displays = [
            CGRect(x: 0, y: 0, width: 1_000, height: 800),
            CGRect(x: 1_000, y: 0, width: 1_000, height: 800)
        ]

        #expect(InPlaceOverlayLayout.isVisible(
            CGRect(x: 850, y: 200, width: 100, height: 30),
            inside: discord,
            screenFrames: displays
        ))
        #expect(!InPlaceOverlayLayout.isVisible(
            CGRect(x: 1_200, y: 200, width: 100, height: 30),
            inside: discord,
            screenFrames: displays
        ))
    }

    @Test("Moves minor overlaps but drops overlays that would lose their source association")
    func resolvesCollisions() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frames = [
            CGRect(x: 100, y: 500, width: 400, height: 24),
            CGRect(x: 100, y: 480, width: 400, height: 24),
            CGRect(x: 100, y: 470, width: 400, height: 24)
        ]

        let resolved = InPlaceOverlayLayout.resolveCollisions(frames, inside: bounds)

        #expect(resolved[0] == frames[0])
        #expect(resolved[1]?.maxY == 498)
        #expect(resolved[2] == nil)
    }
}
