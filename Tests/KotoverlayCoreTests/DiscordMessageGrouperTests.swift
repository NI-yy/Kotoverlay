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

    @Test("Groups consecutive Discord paragraphs until the next author header")
    func groupsAuthorBlock() {
        let filter = EnglishTextFilter()
        let grouped = DiscordMessageGrouper().group([
            line("Ben 昨日 15:47", x: 300, y: 100),
            line("I made a company email and registered it.", x: 300, y: 124),
            line("Then support sent me a ticket link.", x: 300, y: 146),
            line("It was a mildly frustrating experience.", x: 300, y: 205),
            line("MJP 2026/08/07 23:03", x: 300, y: 260),
            line("The descriptor loads were not uniform.", x: 300, y: 284),
            line("They could not be prefetched into GMEM.", x: 300, y: 306)
        ], filteringWith: filter)

        #expect(grouped.count == 2)
        #expect(grouped[0].text == "I made a company email and registered it. Then support sent me a ticket link. It was a mildly frustrating experience.")
        #expect(grouped[1].text == "The descriptor loads were not uniform. They could not be prefetched into GMEM.")
    }

    @Test("Drops an indented reply preview before the author header")
    func dropsReplyPreview() {
        let filter = EnglishTextFilter()
        let grouped = DiscordMessageGrouper().group([
            line("@Turtel/Vhans Anyone had acceleration structures remain?", x: 340, y: 100),
            line("Amelie 2026/08/27 5:34", x: 300, y: 124),
            line("Not as far as I am aware of.", x: 300, y: 148),
            line("But I am using the latest beta.", x: 300, y: 170)
        ], filteringWith: filter)

        #expect(grouped.map(\.text) == [
            "Not as far as I am aware of. But I am using the latest beta."
        ])
    }

    @Test("Keeps a non-indented message that begins with a mention")
    func keepsMentionMessage() {
        let filter = EnglishTextFilter()
        let grouped = DiscordMessageGrouper().group([
            line("@Dilute can you show the shader?", x: 300, y: 100),
            line("Ben 2026/08/27 15:47", x: 300, y: 145),
            line("Here is the shader.", x: 300, y: 169)
        ], filteringWith: filter)

        #expect(grouped.map(\.text) == [
            "@Dilute can you show the shader?",
            "Here is the shader."
        ])
    }

    @Test("Falls back to geometry when the author header is above the viewport")
    func fallsBackWithoutHeader() {
        let filter = EnglishTextFilter()
        let grouped = DiscordMessageGrouper().group([
            line("First visible message.", x: 300, y: 100),
            line("Second visible message.", x: 300, y: 160)
        ], filteringWith: filter)

        #expect(grouped.map(\.text) == ["First visible message.", "Second visible message."])
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
