import Foundation
import Testing
@testable import KotoverlayCore

@Suite("Translation cache")
struct TranslationCacheTests {
    @Test("Memory cache evicts the least recently used entry")
    func memoryCacheIsBounded() async {
        let cache = InMemoryTranslationCache(maximumEntryCount: 2)
        let first = TranslationCacheKey(rawValue: "first")
        let second = TranslationCacheKey(rawValue: "second")
        let third = TranslationCacheKey(rawValue: "third")

        await cache.insert(CachedTranslation(translatedText: "1"), for: first)
        await cache.insert(CachedTranslation(translatedText: "2"), for: second)
        _ = await cache.value(for: first)
        await cache.insert(CachedTranslation(translatedText: "3"), for: third)

        #expect(await cache.value(for: second) == nil)
        #expect(await cache.value(for: first)?.translatedText == "1")
        #expect(await cache.value(for: third)?.translatedText == "3")
        #expect(await cache.entryCount() == 2)
    }

    @Test("Persistent cache prunes the oldest translation")
    func persistentCacheIsBounded() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("translations.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PersistentTranslationCache(fileURL: fileURL, maximumEntryCount: 2)
        let first = TranslationCacheKey(rawValue: "first")
        let second = TranslationCacheKey(rawValue: "second")
        let third = TranslationCacheKey(rawValue: "third")

        try await cache.insert(
            CachedTranslation(translatedText: "1", createdAt: Date(timeIntervalSince1970: 1)),
            for: first
        )
        try await cache.insert(
            CachedTranslation(translatedText: "2", createdAt: Date(timeIntervalSince1970: 2)),
            for: second
        )
        try await cache.insert(
            CachedTranslation(translatedText: "3", createdAt: Date(timeIntervalSince1970: 3)),
            for: third
        )

        #expect(try await cache.value(for: first) == nil)
        #expect(try await cache.value(for: second)?.translatedText == "2")
        #expect(try await cache.value(for: third)?.translatedText == "3")
        #expect(try await cache.entryCount() == 2)
    }

    @Test("Migrates the version 1 cache and persists version 2")
    func migratesVersionOne() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("translations.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data(#"{"version":1,"translations":{"legacy-key":"古い翻訳"}}"#.utf8)
            .write(to: fileURL)
        let cache = PersistentTranslationCache(fileURL: fileURL)
        let value = try await cache.value(for: TranslationCacheKey(rawValue: "legacy-key"))

        #expect(value?.translatedText == "古い翻訳")
        #expect(value?.createdAt == .distantPast)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        #expect(object["version"] as? Int == PersistentTranslationCache.currentVersion)
        #expect(object["entries"] != nil)
        #expect(object["translations"] == nil)
    }

    @Test("Layered cache reads persistent values into memory")
    func layeredReadThrough() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("translations.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistent = PersistentTranslationCache(fileURL: fileURL)
        let layered = LayeredTranslationCache(persistent: persistent)
        let key = TranslationCacheKey(rawValue: "key")
        let value = CachedTranslation(translatedText: "翻訳")

        try await layered.insert(value, for: key)
        let reopened = LayeredTranslationCache(
            persistent: PersistentTranslationCache(fileURL: fileURL)
        )
        #expect(try await reopened.value(for: key) == value)
        try await reopened.removeAll()
        #expect(try await reopened.value(for: key) == nil)
    }

    @Test("Persistent storage remains opt-in when disabled")
    func persistenceOptIn() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("translations.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = TranslationCacheKey(rawValue: "private-key")
        let cache = LayeredTranslationCache(
            persistent: PersistentTranslationCache(fileURL: fileURL),
            persistenceEnabled: false
        )

        try await cache.insert(CachedTranslation(translatedText: "メモリのみ"), for: key)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        await cache.setPersistenceEnabled(true)
        try await cache.insert(CachedTranslation(translatedText: "永続化"), for: key)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
