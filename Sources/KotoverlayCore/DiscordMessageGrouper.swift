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
        let ordered = ordered(lines)
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

    public func group(
        _ lines: [DetectedText],
        filteringWith filter: EnglishTextFilter
    ) -> [DetectedText] {
        let ordered = ordered(lines)
        var groups: [LineGroup] = []
        var current: LineGroup?
        var insideAuthorBlock = false

        for line in ordered {
            if let boundary = boundaryRole(for: line.text) {
                flush(&current, into: &groups)
                insideAuthorBlock = boundary == .authorHeader
                continue
            }
            guard filter.accepts(line) else { continue }

            if var existing = current {
                if insideAuthorBlock || canJoin(previousLine: existing.lastLine, nextLine: line) {
                    existing.append(line)
                    current = existing
                } else {
                    groups.append(existing)
                    current = LineGroup(line)
                }
            } else {
                current = LineGroup(line)
            }
        }
        flush(&current, into: &groups)
        return groups.map(\.detectedText)
    }

    private func ordered(_ lines: [DetectedText]) -> [DetectedText] {
        lines.sorted { lhs, rhs in
            if abs(lhs.bounds.y - rhs.bounds.y) > 4 {
                return lhs.bounds.y < rhs.bounds.y
            }
            return lhs.bounds.x < rhs.bounds.x
        }
    }

    private func flush(_ current: inout LineGroup?, into groups: inout [LineGroup]) {
        if let current { groups.append(current) }
        current = nil
    }

    private func boundaryRole(for text: String) -> BoundaryRole? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasClock = trimmed.range(
            of: #"\b\d{1,2}:\d{2}\b"#,
            options: .regularExpression
        ) != nil
        let hasDayContext = trimmed.range(
            of: #"\b\d{4}/\d{1,2}/\d{1,2}\b|\b(?:today|yesterday)\b|今日|昨日"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let isExactClock = trimmed.range(
            of: #"^\d{1,2}:\d{2}$"#,
            options: .regularExpression
        ) != nil
        let latinWords = trimmed.lowercased().split { !$0.isLetter }.map(String.init)
        let looksLikeShortAuthorHeader = latinWords.count <= 3
            && !latinWords.contains(where: Self.conversationalHeaderWords.contains)
            && trimmed.count <= 80

        if hasClock && (hasDayContext || isExactClock || looksLikeShortAuthorHeader) {
            return .authorHeader
        }
        if hasDayContext { return .sectionDivider }
        return nil
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

private extension DiscordMessageGrouper {
    enum BoundaryRole {
        case authorHeader
        case sectionDivider
    }

    static let conversationalHeaderWords: Set<String> = [
        "at", "by", "for", "from", "in", "meet", "on", "since", "until"
    ]
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
