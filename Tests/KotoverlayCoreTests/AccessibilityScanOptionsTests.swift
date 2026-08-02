import Testing
@testable import KotoverlayCore

@Suite("Accessibility scan options")
struct AccessibilityScanOptionsTests {
    @Test("Unsafe traversal bounds are clamped")
    func clampsBounds() {
        let options = AccessibilityScanOptions(maximumElements: 0, maximumDepth: -1, timeout: .seconds(-1), messagingTimeoutSeconds: 0)
        #expect(options.maximumElements == 1)
        #expect(options.maximumDepth == 0)
        #expect(options.timeout == .zero)
        #expect(options.messagingTimeoutSeconds == 0.01)
    }
}
