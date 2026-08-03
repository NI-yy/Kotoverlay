import CryptoKit
import Foundation

public struct TranslationCacheKey: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make(
        identity: MessageIdentity,
        sourceLanguage: String,
        targetLanguage: String,
        providerID: String,
        promptVersion: String
    ) -> TranslationCacheKey {
        let material = [
            "v1", identity.rawValue, sourceLanguage, targetLanguage,
            providerID, promptVersion
        ].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(material.utf8))
        return TranslationCacheKey(
            rawValue: digest.map { String(format: "%02x", $0) }.joined()
        )
    }
}

public struct CachedTranslation: Codable, Equatable, Sendable {
    public let translatedText: String
    public let createdAt: Date

    public init(translatedText: String, createdAt: Date = Date()) {
        self.translatedText = translatedText
        self.createdAt = createdAt
    }
}

public protocol TranslationCache: Sendable {
    func value(for key: TranslationCacheKey) async throws -> CachedTranslation?
    func insert(_ value: CachedTranslation, for key: TranslationCacheKey) async throws
    func removeAll() async throws
}

public actor InMemoryTranslationCache: TranslationCache {
    private var values: [TranslationCacheKey: CachedTranslation]

    public init(values: [TranslationCacheKey: CachedTranslation] = [:]) {
        self.values = values
    }

    public func value(for key: TranslationCacheKey) -> CachedTranslation? {
        values[key]
    }

    public func insert(_ value: CachedTranslation, for key: TranslationCacheKey) {
        values[key] = value
    }

    public func removeAll() {
        values.removeAll(keepingCapacity: false)
    }
}

public enum PersistentTranslationCacheError: Error, LocalizedError, Equatable, Sendable {
    case malformedFile
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .malformedFile:
            "The translation cache file is malformed."
        case let .unsupportedVersion(version):
            "Translation cache version \(version) is not supported."
        }
    }
}

public actor PersistentTranslationCache: TranslationCache {
    public static let currentVersion = 2

    private let fileURL: URL
    private var values: [String: CachedTranslation] = [:]
    private var loaded = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func value(for key: TranslationCacheKey) throws -> CachedTranslation? {
        try loadIfNeeded()
        return values[key.rawValue]
    }

    public func insert(_ value: CachedTranslation, for key: TranslationCacheKey) throws {
        try loadIfNeeded()
        values[key.rawValue] = value
        try persist()
    }

    public func removeAll() throws {
        try loadIfNeeded()
        values.removeAll(keepingCapacity: false)
        try persist()
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            loaded = true
            return
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()

        guard let header = try? decoder.decode(CacheHeader.self, from: data) else {
            throw PersistentTranslationCacheError.malformedFile
        }
        switch header.version {
        case Self.currentVersion:
            guard let envelope = try? decoder.decode(CacheEnvelope.self, from: data) else {
                throw PersistentTranslationCacheError.malformedFile
            }
            values = envelope.entries
            loaded = true
        case 1:
            guard let legacy = try? decoder.decode(LegacyCacheEnvelope.self, from: data) else {
                throw PersistentTranslationCacheError.malformedFile
            }
            values = legacy.translations.mapValues {
                CachedTranslation(translatedText: $0, createdAt: .distantPast)
            }
            try persist()
            loaded = true
        default:
            throw PersistentTranslationCacheError.unsupportedVersion(header.version)
        }
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(
            CacheEnvelope(version: Self.currentVersion, entries: values)
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

public actor LayeredTranslationCache: TranslationCache {
    private let memory: InMemoryTranslationCache
    private let persistent: PersistentTranslationCache

    public init(
        memory: InMemoryTranslationCache = InMemoryTranslationCache(),
        persistent: PersistentTranslationCache
    ) {
        self.memory = memory
        self.persistent = persistent
    }

    public func value(for key: TranslationCacheKey) async throws -> CachedTranslation? {
        if let value = await memory.value(for: key) {
            return value
        }
        if let value = try await persistent.value(for: key) {
            await memory.insert(value, for: key)
            return value
        }
        return nil
    }

    public func insert(_ value: CachedTranslation, for key: TranslationCacheKey) async throws {
        try await persistent.insert(value, for: key)
        await memory.insert(value, for: key)
    }

    public func removeAll() async throws {
        try await persistent.removeAll()
        await memory.removeAll()
    }
}

private struct CacheHeader: Decodable {
    let version: Int
}

private struct CacheEnvelope: Codable {
    let version: Int
    let entries: [String: CachedTranslation]
}

private struct LegacyCacheEnvelope: Decodable {
    let version: Int
    let translations: [String: String]
}
