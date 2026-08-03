import Foundation

public struct TranslationRequest: Equatable, Sendable {
    public let sourceText: String
    public let sourceLanguage: String
    public let targetLanguage: String

    public init(
        sourceText: String,
        sourceLanguage: String = "English",
        targetLanguage: String = "Japanese"
    ) {
        self.sourceText = sourceText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }
}

public protocol TranslationProvider: Sendable {
    func translationStream(
        for request: TranslationRequest
    ) -> AsyncThrowingStream<String, Error>
}
