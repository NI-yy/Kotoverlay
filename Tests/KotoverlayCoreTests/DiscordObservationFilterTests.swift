import CoreGraphics
import Testing
@testable import KotoverlayCore

@Suite("Discord observation filtering")
struct DiscordObservationFilterTests {
    @Test("Removes a dense right-side member column while retaining message lines")
    func removesMemberColumn() {
        let window = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let observations = [
            observation("A long message that reaches the right side", x: 220, y: 200, width: 700),
            observation("DragonSlayer0531", x: 870, y: 100),
            observation("Shivoa", x: 870, y: 140),
            observation("Moderator", x: 870, y: 180)
        ]

        let filtered = DiscordObservationFilter().filter(observations, in: window)
        #expect(filtered.map(\.text) == ["A long message that reaches the right side"])
    }

    @Test("Does not crop sparse right-side message content")
    func retainsSparseRightContent() {
        let window = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let observations = [
            observation("message continuation", x: 870, y: 200),
            observation("another message", x: 220, y: 250)
        ]

        #expect(
            DiscordObservationFilter().filter(observations, in: window) == observations
        )
    }

    private func observation(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat = 100
    ) -> OCRObservation {
        OCRObservation(
            text: text,
            confidence: 1,
            normalizedRect: .zero,
            screenRect: CGRect(x: x, y: y, width: width, height: 20)
        )
    }
}
