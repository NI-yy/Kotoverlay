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

public enum TranslationCacheCapacity {
    public static let memory = 512
    public static let persistent = 2_000
}

public actor InMemoryTranslationCache: TranslationCache {
    private var values: [TranslationCacheKey: CachedTranslation]
    private var accessOrder: [TranslationCacheKey: UInt64]
    private var accessCounter: UInt64
    public let maximumEntryCount: Int

    public init(
        values: [TranslationCacheKey: CachedTranslation] = [:],
        maximumEntryCount: Int = TranslationCacheCapacity.memory
    ) {
        let limit = max(1, maximumEntryCount)
        let retained = values
            .sorted(by: Self.olderEntryFirst)
            .suffix(limit)
        self.values = Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
        self.accessOrder = Dictionary(
            uniqueKeysWithValues: retained.enumerated().map { index, entry in
                (entry.key, UInt64(index + 1))
            }
        )
        self.accessCounter = UInt64(retained.count)
        self.maximumEntryCount = limit
    }

    public func value(for key: TranslationCacheKey) -> CachedTranslation? {
        guard let value = values[key] else { return nil }
        markAccessed(key)
        return value
    }

    public func insert(_ value: CachedTranslation, for key: TranslationCacheKey) {
        values[key] = value
        markAccessed(key)
        pruneIfNeeded()
    }

    public func removeAll() {
        values.removeAll(keepingCapacity: false)
        accessOrder.removeAll(keepingCapacity: false)
        accessCounter = 0
    }

    public func entryCount() -> Int {
        values.count
    }

    private func markAccessed(_ key: TranslationCacheKey) {
        accessCounter &+= 1
        if accessCounter == 0 {
            let orderedKeys = accessOrder
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value { return lhs.key.rawValue < rhs.key.rawValue }
                    return lhs.value < rhs.value
                }
                .map(\.key)
            accessOrder = Dictionary(
                uniqueKeysWithValues: orderedKeys.enumerated().map { index, existingKey in
                    (existingKey, UInt64(index + 1))
                }
            )
            accessCounter = UInt64(orderedKeys.count + 1)
        }
        accessOrder[key] = accessCounter
    }

    private func pruneIfNeeded() {
        let overflow = values.count - maximumEntryCount
        guard overflow > 0 else { return }
        let keysToRemove = accessOrder
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key.rawValue < rhs.key.rawValue }
                return lhs.value < rhs.value
            }
            .prefix(overflow)
            .map(\.key)
        for key in keysToRemove {
            values.removeValue(forKey: key)
            accessOrder.removeValue(forKey: key)
        }
    }

    private static func olderEntryFirst(
        _ lhs: Dictionary<TranslationCacheKey, CachedTranslation>.Element,
        _ rhs: Dictionary<TranslationCacheKey, CachedTranslation>.Element
    ) -> Bool {
        if lhs.value.createdAt == rhs.value.createdAt {
            return lhs.key.rawValue < rhs.key.rawValue
        }
        return lhs.value.createdAt < rhs.value.createdAt
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
    public let maximumEntryCount: Int
    private var values: [String: CachedTranslation] = [:]
    private var loaded = false

    public init(
        fileURL: URL,
        maximumEntryCount: Int = TranslationCacheCapacity.persistent
    ) {
        self.fileURL = fileURL
        self.maximumEntryCount = max(1, maximumEntryCount)
    }

    public func value(for key: TranslationCacheKey) throws -> CachedTranslation? {
        try loadIfNeeded()
        return values[key.rawValue]
    }

    public func insert(_ value: CachedTranslation, for key: TranslationCacheKey) throws {
        try loadIfNeeded()
        values[key.rawValue] = value
        pruneIfNeeded()
        try persist()
    }

    public func removeAll() throws {
        try loadIfNeeded()
        values.removeAll(keepingCapacity: false)
        try persist()
    }

    public func entryCount() throws -> Int {
        try loadIfNeeded()
        return values.count
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
            if pruneIfNeeded() {
                try persist()
            }
        case 1:
            guard let legacy = try? decoder.decode(LegacyCacheEnvelope.self, from: data) else {
                throw PersistentTranslationCacheError.malformedFile
            }
            values = legacy.translations.mapValues {
                CachedTranslation(translatedText: $0, createdAt: .distantPast)
            }
            loaded = true
            pruneIfNeeded()
            try persist()
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

    @discardableResult
    private func pruneIfNeeded() -> Bool {
        let overflow = values.count - maximumEntryCount
        guard overflow > 0 else { return false }
        let keysToRemove = values
            .sorted { lhs, rhs in
                if lhs.value.createdAt == rhs.value.createdAt { return lhs.key < rhs.key }
                return lhs.value.createdAt < rhs.value.createdAt
            }
            .prefix(overflow)
            .map(\.key)
        for key in keysToRemove {
            values.removeValue(forKey: key)
        }
        return true
    }
}

public actor LayeredTranslationCache: TranslationCache {
    private let memory: InMemoryTranslationCache
    private let persistent: PersistentTranslationCache
    private var persistenceEnabled: Bool

    public init(
        memory: InMemoryTranslationCache = InMemoryTranslationCache(),
        persistent: PersistentTranslationCache,
        persistenceEnabled: Bool = true
    ) {
        self.memory = memory
        self.persistent = persistent
        self.persistenceEnabled = persistenceEnabled
    }

    public func setPersistenceEnabled(_ enabled: Bool) {
        persistenceEnabled = enabled
    }

    public func value(for key: TranslationCacheKey) async throws -> CachedTranslation? {
        if let value = await memory.value(for: key) {
            return value
        }
        if persistenceEnabled, let value = try await persistent.value(for: key) {
            await memory.insert(value, for: key)
            return value
        }
        return nil
    }

    public func insert(_ value: CachedTranslation, for key: TranslationCacheKey) async throws {
        if persistenceEnabled {
            try await persistent.insert(value, for: key)
        }
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
