import CoreGraphics
import Foundation

public struct AXElementSnapshot: Equatable, Sendable {
    public let identifier: String
    public let role: String
    public let text: String?
    public let frame: CGRect?
    public let depth: Int

    public init(role: String, text: String?, frame: CGRect?, depth: Int, path: [Int]) {
        self.role = role
        self.text = text
        self.frame = frame
        self.depth = depth
        identifier = StableIdentifier.make(role: role, text: text, frame: frame, path: path)
    }
}

enum StableIdentifier {
    static func make(role: String, text: String?, frame: CGRect?, path: [Int]) -> String {
        let normalizedText = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            ?? ""
        let frameKey: String
        if let frame {
            frameKey = [frame.minX, frame.minY, frame.width, frame.height]
                .map { String(Int($0.rounded())) }
                .joined(separator: ",")
        } else {
            frameKey = "-"
        }
        let source = "\(role)|\(normalizedText)|\(frameKey)|\(path.map(String.init).joined(separator: "."))"
        return String(format: "%016llx", fnv1a64(source.utf8))
    }

    private static func fnv1a64<S: Sequence>(_ bytes: S) -> UInt64 where S.Element == UInt8 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
