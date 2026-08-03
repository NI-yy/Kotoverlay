import Testing
@testable import KotoverlayCore

@Suite("English text filtering")
struct EnglishTextFilterTests {
    private let filter = EnglishTextFilter()

    @Test("Accepts English Discord and graphics text")
    func acceptsEnglish() {
        #expect(filter.accepts(candidate("Can Terminal.app do that?")))
        #expect(filter.accepts(candidate("The Metal shader crashed lol")))
    }

    @Test("Excludes Discord labels, code-only text, and non-English text")
    func excludesNoise() {
        #expect(filter.exclusionReason(for: candidate("Send a message")) == .interfaceLabel)
        #expect(filter.exclusionReason(for: candidate("let x = render();")) == .codeOnly)
        #expect(filter.exclusionReason(for: candidate("https://example.com")) == .codeOnly)
        #expect(filter.exclusionReason(for: candidate("これは日本語です")) == .notEnglish)
        #expect(filter.exclusionReason(for: candidate("Hi", confidence: 0.1)) == .lowConfidence)
    }

    private func candidate(_ text: String, confidence: Float = 1) -> DetectedText {
        DetectedText(
            text: text,
            bounds: TextGeometry(x: 0, y: 0, width: 100, height: 20),
            confidence: confidence,
            visibleOrder: 0
        )
    }
}
