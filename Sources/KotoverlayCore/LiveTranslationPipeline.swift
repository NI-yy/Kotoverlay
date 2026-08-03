import Foundation

public struct LivePipelineConfiguration: Equatable, Sendable {
    public var providerID: String
    public var promptVersion: String
    public var maximumConcurrentTranslations: Int

    public init(
        providerID: String = "ollama:qwen3:1.7b",
        promptVersion: String = "1",
        maximumConcurrentTranslations: Int = 1
    ) {
        self.providerID = providerID
        self.promptVersion = promptVersion
        self.maximumConcurrentTranslations = max(1, maximumConcurrentTranslations)
    }
}

public enum PipelineFailureCategory: String, Codable, Equatable, Hashable, Sendable {
    case cancelled
    case providerUnavailable
    case timeout
    case malformedResponse
    case cache
    case other
}

public struct PipelineDiagnostics: Codable, Equatable, Sendable {
    public let observedCount: Int
    public let eligibleCount: Int
    public let excludedCounts: [TextExclusionReason: Int]
    public let duplicateCount: Int
    public let cacheHitCount: Int
    public let translatedCount: Int
    public let failureCounts: [PipelineFailureCategory: Int]
    public let superseded: Bool

    public init(
        observedCount: Int,
        eligibleCount: Int,
        excludedCounts: [TextExclusionReason: Int],
        duplicateCount: Int,
        cacheHitCount: Int,
        translatedCount: Int,
        failureCounts: [PipelineFailureCategory: Int],
        superseded: Bool
    ) {
        self.observedCount = observedCount
        self.eligibleCount = eligibleCount
        self.excludedCounts = excludedCounts
        self.duplicateCount = duplicateCount
        self.cacheHitCount = cacheHitCount
        self.translatedCount = translatedCount
        self.failureCounts = failureCounts
        self.superseded = superseded
    }
}

public struct PipelineRun: Equatable, Sendable {
    public let results: [TranslationResult]
    public let diagnostics: PipelineDiagnostics

    public init(results: [TranslationResult], diagnostics: PipelineDiagnostics) {
        self.results = results
        self.diagnostics = diagnostics
    }
}

public actor LiveTranslationPipeline {
    private let provider: any TranslationProvider
    private let cache: any TranslationCache
    private let filter: EnglishTextFilter
    private let configuration: LivePipelineConfiguration
    private var generation: UInt64 = 0
    private var activeJob: Task<PipelineRun, Never>?

    public init(
        provider: any TranslationProvider,
        cache: any TranslationCache = InMemoryTranslationCache(),
        filter: EnglishTextFilter = EnglishTextFilter(),
        configuration: LivePipelineConfiguration = LivePipelineConfiguration()
    ) {
        self.provider = provider
        self.cache = cache
        self.filter = filter
        self.configuration = configuration
    }

    public func process(_ snapshot: TextSnapshot) async -> PipelineRun {
        generation &+= 1
        let runGeneration = generation
        activeJob?.cancel()

        let provider = self.provider
        let cache = self.cache
        let filter = self.filter
        let configuration = self.configuration
        let task = Task {
            await PipelineWorker.run(
                snapshot: snapshot,
                provider: provider,
                cache: cache,
                filter: filter,
                configuration: configuration
            )
        }
        activeJob = task
        let run = await task.value
        guard runGeneration == generation else {
            return PipelineRun(
                results: [],
                diagnostics: run.diagnostics.supersededCopy()
            )
        }
        activeJob = nil
        return run
    }

    public func cancel() {
        generation &+= 1
        activeJob?.cancel()
        activeJob = nil
    }
}

private enum PipelineWorker {
    struct Candidate: Sendable {
        let identified: IdentifiedText
        let cacheKey: TranslationCacheKey
    }

    struct Outcome: Sendable {
        let result: TranslationResult?
        let failure: PipelineFailureCategory?
    }

    static func run(
        snapshot: TextSnapshot,
        provider: any TranslationProvider,
        cache: any TranslationCache,
        filter: EnglishTextFilter,
        configuration: LivePipelineConfiguration
    ) async -> PipelineRun {
        let filtered = filterAndIdentify(snapshot: snapshot, filter: filter)
        var cacheHits: [TranslationResult] = []
        var pending: [Candidate] = []
        var failures: [PipelineFailureCategory: Int] = [:]

        for identified in filtered.identified.sorted(by: newestFirst) {
            guard !Task.isCancelled else {
                failures[.cancelled, default: 0] += 1
                break
            }
            let key = TranslationCacheKey.make(
                identity: identified.identity,
                sourceLanguage: "English",
                targetLanguage: "Japanese",
                providerID: configuration.providerID,
                promptVersion: configuration.promptVersion
            )
            do {
                if let cached = try await cache.value(for: key) {
                    cacheHits.append(makeResult(
                        identified: identified,
                        translatedText: cached.translatedText,
                        cacheHit: true
                    ))
                } else {
                    pending.append(Candidate(identified: identified, cacheKey: key))
                }
            } catch {
                failures[.cache, default: 0] += 1
                pending.append(Candidate(identified: identified, cacheKey: key))
            }
        }

        let outcomes = await translate(
            pending,
            provider: provider,
            cache: cache,
            limit: configuration.maximumConcurrentTranslations
        )
        var translated: [TranslationResult] = []
        for outcome in outcomes {
            if let result = outcome.result { translated.append(result) }
            if let failure = outcome.failure { failures[failure, default: 0] += 1 }
        }

        let results = (cacheHits + translated).sorted {
            $0.visibleOrder < $1.visibleOrder
        }
        return PipelineRun(
            results: results,
            diagnostics: PipelineDiagnostics(
                observedCount: snapshot.texts.count,
                eligibleCount: filtered.identified.count,
                excludedCounts: filtered.excluded,
                duplicateCount: filtered.duplicateCount,
                cacheHitCount: cacheHits.count,
                translatedCount: translated.count,
                failureCounts: failures,
                superseded: Task.isCancelled
            )
        )
    }

    private static func filterAndIdentify(
        snapshot: TextSnapshot,
        filter: EnglishTextFilter
    ) -> (
        identified: [IdentifiedText],
        excluded: [TextExclusionReason: Int],
        duplicateCount: Int
    ) {
        var excluded: [TextExclusionReason: Int] = [:]
        var accepted: [DetectedText] = []
        var exactSignatures: Set<String> = []
        var duplicateCount = 0

        for text in snapshot.texts.sorted(by: { $0.visibleOrder < $1.visibleOrder }) {
            if let reason = filter.exclusionReason(for: text) {
                excluded[reason, default: 0] += 1
                continue
            }
            let signature = duplicateSignature(text)
            guard exactSignatures.insert(signature).inserted else {
                duplicateCount += 1
                continue
            }
            accepted.append(text)
        }

        var occurrences: [String: Int] = [:]
        let identified = accepted.map { text in
            let occurrenceKey = [
                MessageTextNormalizer.normalize(text.author ?? ""),
                MessageTextNormalizer.normalize(text.text)
            ].joined(separator: "\u{1f}")
            let occurrence = occurrences[occurrenceKey, default: 0]
            occurrences[occurrenceKey] = occurrence + 1
            return IdentifiedText(
                identity: MessageIdentity.make(
                    contextID: snapshot.contextID,
                    text: text,
                    occurrence: occurrence
                ),
                detected: text
            )
        }
        return (identified, excluded, duplicateCount)
    }

    private static func duplicateSignature(_ text: DetectedText) -> String {
        let bounds = text.bounds
        return [
            MessageTextNormalizer.normalize(text.text),
            String(format: "%.1f", bounds.x),
            String(format: "%.1f", bounds.y),
            String(format: "%.1f", bounds.width),
            String(format: "%.1f", bounds.height)
        ].joined(separator: "\u{1f}")
    }

    private static func newestFirst(_ lhs: IdentifiedText, _ rhs: IdentifiedText) -> Bool {
        lhs.detected.visibleOrder > rhs.detected.visibleOrder
    }

    private static func translate(
        _ candidates: [Candidate],
        provider: any TranslationProvider,
        cache: any TranslationCache,
        limit: Int
    ) async -> [Outcome] {
        await withTaskGroup(of: Outcome.self, returning: [Outcome].self) { group in
            var nextIndex = 0
            var outcomes: [Outcome] = []

            func addNext() {
                guard nextIndex < candidates.count, !Task.isCancelled else { return }
                let candidate = candidates[nextIndex]
                nextIndex += 1
                group.addTask {
                    await translateOne(candidate, provider: provider, cache: cache)
                }
            }

            for _ in 0..<min(limit, candidates.count) { addNext() }
            while let outcome = await group.next() {
                outcomes.append(outcome)
                addNext()
            }
            return outcomes
        }
    }

    private static func translateOne(
        _ candidate: Candidate,
        provider: any TranslationProvider,
        cache: any TranslationCache
    ) async -> Outcome {
        do {
            try Task.checkCancellation()
            var output = ""
            for try await chunk in provider.translationStream(
                for: TranslationRequest(sourceText: candidate.identified.detected.text)
            ) {
                try Task.checkCancellation()
                output += chunk
            }
            guard !output.isEmpty else { return Outcome(result: nil, failure: .malformedResponse) }
            do {
                try await cache.insert(CachedTranslation(translatedText: output), for: candidate.cacheKey)
            } catch {
                return Outcome(
                    result: makeResult(
                        identified: candidate.identified,
                        translatedText: output,
                        cacheHit: false
                    ),
                    failure: .cache
                )
            }
            return Outcome(
                result: makeResult(
                    identified: candidate.identified,
                    translatedText: output,
                    cacheHit: false
                ),
                failure: nil
            )
        } catch is CancellationError {
            return Outcome(result: nil, failure: .cancelled)
        } catch let error as OllamaError {
            return Outcome(result: nil, failure: category(for: error))
        } catch {
            return Outcome(result: nil, failure: .other)
        }
    }

    private static func makeResult(
        identified: IdentifiedText,
        translatedText: String,
        cacheHit: Bool
    ) -> TranslationResult {
        TranslationResult(
            identity: identified.identity,
            sourceText: identified.detected.text,
            translatedText: translatedText,
            bounds: identified.detected.bounds,
            visibleOrder: identified.detected.visibleOrder,
            cacheHit: cacheHit
        )
    }

    private static func category(for error: OllamaError) -> PipelineFailureCategory {
        switch error {
        case .serverUnavailable, .modelNotInstalled:
            .providerUnavailable
        case .timedOut:
            .timeout
        case .malformedModelResponse, .malformedStream, .incompleteStream,
             .emptyTranslation, .protectedTokenLost:
            .malformedResponse
        default:
            .other
        }
    }
}

private extension PipelineDiagnostics {
    func supersededCopy() -> PipelineDiagnostics {
        var failures = failureCounts
        failures[.cancelled, default: 0] += 1
        return PipelineDiagnostics(
            observedCount: observedCount,
            eligibleCount: eligibleCount,
            excludedCounts: excludedCounts,
            duplicateCount: duplicateCount,
            cacheHitCount: cacheHitCount,
            translatedCount: translatedCount,
            failureCounts: failures,
            superseded: true
        )
    }
}
