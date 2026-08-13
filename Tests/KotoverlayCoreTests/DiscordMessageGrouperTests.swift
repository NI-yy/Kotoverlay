import Testing
@testable import KotoverlayCore

@Suite("Discord message grouping")
struct DiscordMessageGrouperTests {
    @Test("Combines aligned neighboring OCR lines into one translation request")
    func combinesMessageLines() throws {
        let grouped = DiscordMessageGrouper().group([
            line("The descriptor loads were not uniform.", x: 300, y: 100, width: 420),
            line("They could not be prefetched into GMEM,", x: 302, y: 122, width: 390),
            line("so every thread performed a full load.", x: 301, y: 144, width: 410)
        ])

        let message = try #require(grouped.only)
        #expect(message.text == "The descriptor loads were not uniform. They could not be prefetched into GMEM, so every thread performed a full load.")
        #expect(message.bounds.cgRect.minY == 100)
        #expect(message.bounds.cgRect.maxY == 162)
    }

    @Test("Keeps different messages separate across a header-sized gap")
    func separatesMessages() {
        let grouped = DiscordMessageGrouper().group([
            line("First shader message.", x: 300, y: 100),
            line("Second shader message.", x: 300, y: 145)
        ])

        #expect(grouped.map(\.text) == [
            "First shader message.", "Second shader message."
        ])
    }

    @Test("Keeps an indented reply or separate column independent")
    func separatesIndentedLines() {
        let grouped = DiscordMessageGrouper().group([
            line("Quoted shader message.", x: 340, y: 100),
            line("My response to the quote.", x: 300, y: 122)
        ])

        #expect(grouped.count == 2)
    }

    private func line(
        _ text: String,
        x: Double,
        y: Double,
        width: Double = 300
    ) -> DetectedText {
        DetectedText(
            text: text,
            bounds: TextGeometry(x: x, y: y, width: width, height: 18),
            confidence: 0.9,
            visibleOrder: Int(y)
        )
    }
}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}
