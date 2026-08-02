import CoreGraphics
import Testing
@testable import KotoverlayCore

@Suite("AX element snapshots")
struct AXElementSnapshotTests {
    @Test("Stable identifiers are deterministic")
    func deterministicIdentifier() {
        let first = AXElementSnapshot(role: "AXStaticText", text: "Hello   graphics\nprogrammers", frame: CGRect(x: 10.2, y: 20.4, width: 300.1, height: 24.2), depth: 4, path: [0, 3, 1])
        let second = AXElementSnapshot(role: "AXStaticText", text: " Hello graphics programmers ", frame: CGRect(x: 10.4, y: 20.3, width: 300.2, height: 24.4), depth: 4, path: [0, 3, 1])
        #expect(first.identifier == second.identifier)
    }

    @Test("Path changes produce a different identifier")
    func pathParticipatesInIdentifier() {
        let frame = CGRect(x: 10, y: 20, width: 300, height: 24)
        let first = AXElementSnapshot(role: "AXStaticText", text: "Hello", frame: frame, depth: 1, path: [0])
        let second = AXElementSnapshot(role: "AXStaticText", text: "Hello", frame: frame, depth: 1, path: [1])
        #expect(first.identifier != second.identifier)
    }
}
