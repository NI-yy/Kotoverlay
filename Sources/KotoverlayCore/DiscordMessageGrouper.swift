import CoreGraphics
import Foundation

public struct DiscordMessageGrouper: Sendable {
    public var maximumVerticalGap: CGFloat
    public var maximumHorizontalDrift: CGFloat

    public init(
        maximumVerticalGap: CGFloat = 14,
        maximumHorizontalDrift: CGFloat = 24
    ) {
        self.maximumVerticalGap = max(0, maximumVerticalGap)
        self.maximumHorizontalDrift = max(0, maximumHorizontalDrift)
    }

    public func group(_ lines: [DetectedText]) -> [DetectedText] {
        let ordered = lines.sorted { lhs, rhs in
            if abs(lhs.bounds.y - rhs.bounds.y) > 4 {
                return lhs.bounds.y < rhs.bounds.y
            }
            return lhs.bounds.x < rhs.bounds.x
        }
        guard let first = ordered.first else { return [] }

        var groups: [LineGroup] = []
        var current = LineGroup(first)
        for line in ordered.dropFirst() {
            if canJoin(previousLine: current.lastLine, nextLine: line) {
                current.append(line)
            } else {
                groups.append(current)
                current = LineGroup(line)
            }
        }
        groups.append(current)
        return groups.map(\.detectedText)
    }

    private func canJoin(previousLine: DetectedText, nextLine: DetectedText) -> Bool {
        let previous = previousLine.bounds.cgRect
        let next = nextLine.bounds.cgRect
        let lineHeight = max(1, min(previous.height, next.height))
        let verticalGap = next.minY - previous.maxY
        let allowedGap = min(maximumVerticalGap, max(6, lineHeight * 0.85))
        guard verticalGap >= -lineHeight * 0.35,
              verticalGap <= allowedGap else {
            return false
        }

        let allowedDrift = min(maximumHorizontalDrift, max(10, lineHeight * 1.5))
        return abs(previous.minX - next.minX) <= allowedDrift
    }
}

private struct LineGroup {
    private var lines: [DetectedText]
    private(set) var lastLine: DetectedText

    init(_ line: DetectedText) {
        lines = [line]
        lastLine = line
    }

    mutating func append(_ line: DetectedText) {
        lines.append(line)
        lastLine = line
    }

    var detectedText: DetectedText {
        let rect = lines.dropFirst().reduce(lines[0].bounds.cgRect) {
            $0.union($1.bounds.cgRect)
        }
        return DetectedText(
            text: lines.map(\.text).joined(separator: " "),
            bounds: TextGeometry(rect),
            confidence: lines.map(\.confidence).min() ?? 1,
            author: lines.compactMap(\.author).first,
            visibleOrder: lines[0].visibleOrder
        )
    }
}
