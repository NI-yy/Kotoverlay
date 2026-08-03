import CoreGraphics
import CryptoKit
import Foundation

public struct TextGeometry: Codable, Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct DetectedText: Codable, Equatable, Hashable, Sendable {
    public let text: String
    public let bounds: TextGeometry
    public let confidence: Float
    public let author: String?
    public let visibleOrder: Int

    public init(
        text: String,
        bounds: TextGeometry,
        confidence: Float = 1,
        author: String? = nil,
        visibleOrder: Int
    ) {
        self.text = text
        self.bounds = bounds
        self.confidence = confidence
        self.author = author
        self.visibleOrder = visibleOrder
    }

    public init(observation: OCRObservation, visibleOrder: Int, author: String? = nil) {
        self.init(
            text: observation.text,
            bounds: TextGeometry(observation.screenRect),
            confidence: observation.confidence,
            author: author,
            visibleOrder: visibleOrder
        )
    }
}

public struct TextSnapshot: Equatable, Sendable {
    public let contextID: String
    public let windowID: UInt32
    public let texts: [DetectedText]

    public init(contextID: String, windowID: UInt32, texts: [DetectedText]) {
        self.contextID = contextID
        self.windowID = windowID
        self.texts = texts
    }
}

public struct MessageIdentity: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make(
        contextID: String,
        text: DetectedText,
        occurrence: Int
    ) -> MessageIdentity {
        let normalizedAuthor = MessageTextNormalizer.normalize(text.author ?? "")
        let normalizedText = MessageTextNormalizer.normalize(text.text)
        let material = "v1\u{1f}\(contextID)\u{1f}\(normalizedAuthor)\u{1f}\(normalizedText)\u{1f}\(occurrence)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return MessageIdentity(rawValue: digest.map { String(format: "%02x", $0) }.joined())
    }
}

public struct IdentifiedText: Equatable, Sendable {
    public let identity: MessageIdentity
    public let detected: DetectedText

    public init(identity: MessageIdentity, detected: DetectedText) {
        self.identity = identity
        self.detected = detected
    }
}

public struct TranslationResult: Codable, Equatable, Sendable {
    public let identity: MessageIdentity
    public let sourceText: String
    public let translatedText: String
    public let bounds: TextGeometry
    public let visibleOrder: Int
    public let cacheHit: Bool

    public init(
        identity: MessageIdentity,
        sourceText: String,
        translatedText: String,
        bounds: TextGeometry,
        visibleOrder: Int,
        cacheHit: Bool
    ) {
        self.identity = identity
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.bounds = bounds
        self.visibleOrder = visibleOrder
        self.cacheHit = cacheHit
    }
}

enum MessageTextNormalizer {
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}
