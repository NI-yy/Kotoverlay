import Foundation

public enum TextExclusionReason: String, Codable, Equatable, Sendable {
    case empty
    case lowConfidence
    case interfaceLabel
    case metadata
    case codeOnly
    case notEnglish
}

public struct EnglishTextFilter: Sendable {
    public var minimumConfidence: Float
    public var minimumLetters: Int

    public init(minimumConfidence: Float = 0.45, minimumLetters: Int = 3) {
        self.minimumConfidence = minimumConfidence
        self.minimumLetters = minimumLetters
    }

    public func exclusionReason(for candidate: DetectedText) -> TextExclusionReason? {
        let trimmed = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard candidate.confidence >= minimumConfidence else { return .lowConfidence }
        guard !Self.interfaceLabels.contains(MessageTextNormalizer.normalize(trimmed)) else {
            return .interfaceLabel
        }
        guard !isDiscordMetadata(trimmed) else { return .metadata }
        guard !isCodeOnly(trimmed) else { return .codeOnly }
        guard isLikelyEnglish(trimmed) else { return .notEnglish }
        return nil
    }

    public func accepts(_ candidate: DetectedText) -> Bool {
        exclusionReason(for: candidate) == nil
    }

    private func isLikelyEnglish(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let latinLetters = scalars.filter {
            (65...90).contains($0.value) || (97...122).contains($0.value)
        }.count
        guard latinLetters >= minimumLetters else { return false }

        let allLetters = scalars.filter { CharacterSet.letters.contains($0) }.count
        guard allLetters > 0, Double(latinLetters) / Double(allLetters) >= 0.6 else {
            return false
        }

        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        if words.contains(where: Self.commonEnglishWords.contains) {
            return true
        }
        return words.contains { $0.count >= 4 }
    }

    private func isCodeOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("http://")
            || trimmed.hasPrefix("https://") || trimmed.hasPrefix("@") {
            return !trimmed.contains(where: \Character.isWhitespace)
        }
        let hasStatementPunctuation = trimmed.contains(";")
            || trimmed.contains("{") || trimmed.contains("}")
        let hasCodeExpression = trimmed.contains("=") || trimmed.contains("()")
            || trimmed.contains("->")
        if hasStatementPunctuation && hasCodeExpression { return true }

        let codePrefixes = ["class ", "enum ", "func ", "import ", "let ", "struct ", "var "]
        return codePrefixes.contains(where: trimmed.hasPrefix) && hasCodeExpression
    }

    private func isDiscordMetadata(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        let hasConversationalWord = words.contains(where: Self.commonEnglishWords.contains)
        if text.hasPrefix("@"), words.count <= 3, !hasConversationalWord {
            return true
        }
        if text.contains("→"), words.count <= 4, !hasConversationalWord {
            return true
        }
        if text.contains("@"), text.contains("+"), words.count <= 5, !hasConversationalWord {
            return true
        }
        let patterns = [
            #"\b\d{4}/\d{1,2}/\d{1,2}\b"#,
            #"\b(?:today|yesterday)\s+(?:at\s+)?\d{1,2}:\d{2}\b"#,
            #"^\d{1,2}:\d{2}$"#
        ]
        return patterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static let interfaceLabels: Set<String> = [
        "add reaction", "edit channel", "friends", "inbox", "mark as read",
        "members", "message", "new messages", "notification settings",
        "pinned messages", "search", "send a message", "threads"
    ]

    private static let commonEnglishWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "can", "did",
        "do", "does", "for", "from", "had", "has", "have", "here", "how",
        "i", "if", "in", "is", "it", "my", "not", "of", "on", "or",
        "so", "that", "the", "this", "to", "use", "was", "we", "what",
        "when", "with", "would", "you", "your"
    ]
}
