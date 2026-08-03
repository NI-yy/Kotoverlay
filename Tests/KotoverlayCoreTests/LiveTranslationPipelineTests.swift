import Foundation
import Testing
@testable import KotoverlayCore

@Suite("Live translation pipeline")
struct LiveTranslationPipelineTests {
    @Test("Translates newest visible messages first and presents them in visual order")
    func newestFirst() async {
        let recorder = RequestRecorder()
        let provider = MockTranslationProvider { request in
            makeStream {
                await recorder.record(request.sourceText)
                return "訳:\(request.sourceText)"
            }
        }
        let pipeline = LiveTranslationPipeline(provider: provider)
        let run = await pipeline.process(snapshot([
            detected("old message here", order: 0, y: 100),
            detected("middle message here", order: 1, y: 200),
            detected("new message here", order: 2, y: 300)
        ]))

        #expect(await recorder.requests == [
            "new message here", "middle message here", "old message here"
        ])
        #expect(run.results.map(\.visibleOrder) == [0, 1, 2])
        #expect(run.diagnostics.translatedCount == 3)
    }

    @Test("Deduplicates one OCR snapshot and reuses cached translations")
    func deduplicatesAndCaches() async {
        let recorder = RequestRecorder()
        let provider = MockTranslationProvider { request in
            makeStream {
                await recorder.record(request.sourceText)
                return "キャッシュ対象"
            }
        }
        let pipeline = LiveTranslationPipeline(provider: provider)
        let duplicate = detected("The shader crashed", order: 0, y: 100)
        let input = snapshot([duplicate, duplicate])

        let first = await pipeline.process(input)
        let second = await pipeline.process(input)

        #expect(await recorder.requests.count == 1)
        #expect(first.diagnostics.duplicateCount == 1)
        #expect(first.diagnostics.translatedCount == 1)
        #expect(second.diagnostics.cacheHitCount == 1)
        #expect(second.results.first?.cacheHit == true)
    }

    @Test("A new channel generation cancels stale translation work")
    func cancelsStaleWork() async {
        let probe = CancellationRecorder()
        let provider = MockTranslationProvider { request in
            if request.sourceText == "old channel message" {
                return makeCancellableStream(probe: probe)
            }
            return makeStream { "新しいチャンネル" }
        }
        let pipeline = LiveTranslationPipeline(provider: provider)
        let oldTask = Task {
            await pipeline.process(snapshot([
                detected("old channel message", order: 0, y: 100)
            ], contextID: "old-channel"))
        }
        for _ in 0..<100 where !(await probe.started) {
            try? await Task.sleep(for: .milliseconds(5))
        }

        let newRun = await pipeline.process(snapshot([
            detected("new channel message", order: 0, y: 100)
        ], contextID: "new-channel"))
        let oldRun = await oldTask.value
        for _ in 0..<100 where !(await probe.cancelled) {
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(await probe.cancelled)
        #expect(oldRun.results.isEmpty)
        #expect(oldRun.diagnostics.superseded)
        #expect(newRun.results.map(\.translatedText) == ["新しいチャンネル"])
    }

    @Test("Diagnostics contain counts and categories but no message content")
    func diagnosticsAreContentFree() async throws {
        let provider = MockTranslationProvider { _ in makeStream { "翻訳" } }
        let pipeline = LiveTranslationPipeline(provider: provider)
        let run = await pipeline.process(snapshot([
            detected("The private source message", order: 0, y: 100),
            detected("Send a message", order: 1, y: 200)
        ]))
        let data = try JSONEncoder().encode(run.diagnostics)
        let encoded = try #require(String(data: data, encoding: .utf8))

        #expect(!encoded.contains("private"))
        #expect(!encoded.contains("Send a message"))
        #expect(run.diagnostics.observedCount == 2)
        #expect(run.diagnostics.excludedCounts[.interfaceLabel] == 1)
    }

    @Test("Bounds concurrent translations at the configured limit")
    func boundedConcurrency() async {
        let probe = ConcurrencyRecorder()
        let provider = MockTranslationProvider { _ in
            makeStream {
                await probe.enter()
                try? await Task.sleep(for: .milliseconds(30))
                await probe.leave()
                return "翻訳"
            }
        }
        let pipeline = LiveTranslationPipeline(
            provider: provider,
            configuration: LivePipelineConfiguration(maximumConcurrentTranslations: 2)
        )
        _ = await pipeline.process(snapshot([
            detected("first English message", order: 0, y: 100),
            detected("second English message", order: 1, y: 200),
            detected("third English message", order: 2, y: 300),
            detected("fourth English message", order: 3, y: 400)
        ]))

        #expect(await probe.maximumActive == 2)
    }

    @Test("Publishes each completed translation before the full run finishes")
    func progressiveResults() async {
        let progress = ProgressRecorder()
        let provider = MockTranslationProvider { request in
            makeStream {
                try? await Task.sleep(for: .milliseconds(10))
                return "訳:\(request.sourceText)"
            }
        }
        let pipeline = LiveTranslationPipeline(provider: provider)

        let run = await pipeline.process(snapshot([
            detected("old message here", order: 0, y: 100),
            detected("new message here", order: 1, y: 200)
        ])) { results in
            await progress.record(results.map(\.visibleOrder))
        }

        #expect(await progress.snapshots == [[1], [0, 1]])
        #expect(run.results.map(\.visibleOrder) == [0, 1])
    }

    private func snapshot(
        _ texts: [DetectedText],
        contextID: String = "graphics/metal"
    ) -> TextSnapshot {
        TextSnapshot(contextID: contextID, windowID: 42, texts: texts)
    }

    private func detected(_ text: String, order: Int, y: Double) -> DetectedText {
        DetectedText(
            text: text,
            bounds: TextGeometry(x: 400, y: y, width: 300, height: 30),
            visibleOrder: order
        )
    }
}

private final class MockTranslationProvider: TranslationProvider, @unchecked Sendable {
    private let handler: @Sendable (TranslationRequest) -> AsyncThrowingStream<String, Error>

    init(handler: @escaping @Sendable (TranslationRequest) -> AsyncThrowingStream<String, Error>) {
        self.handler = handler
    }

    func translationStream(
        for request: TranslationRequest
    ) -> AsyncThrowingStream<String, Error> {
        handler(request)
    }
}

private actor RequestRecorder {
    private(set) var requests: [String] = []

    func record(_ request: String) {
        requests.append(request)
    }
}

private actor CancellationRecorder {
    private(set) var started = false
    private(set) var cancelled = false

    func markStarted() { started = true }
    func markCancelled() { cancelled = true }
}

private actor ConcurrencyRecorder {
    private var active = 0
    private(set) var maximumActive = 0

    func enter() {
        active += 1
        maximumActive = max(maximumActive, active)
    }

    func leave() {
        active -= 1
    }
}

private actor ProgressRecorder {
    private(set) var snapshots: [[Int]] = []

    func record(_ visibleOrders: [Int]) {
        snapshots.append(visibleOrders)
    }
}

private func makeStream(
    operation: @escaping @Sendable () async -> String
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            continuation.yield(await operation())
            continuation.finish()
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
    }
}

private func makeCancellableStream(
    probe: CancellationRecorder
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            await probe.markStarted()
            do {
                try await Task.sleep(for: .seconds(5))
                continuation.yield("古い翻訳")
                continuation.finish()
            } catch is CancellationError {
                await probe.markCancelled()
                continuation.finish(throwing: CancellationError())
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
    }
}
