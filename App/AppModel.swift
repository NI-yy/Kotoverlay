@preconcurrency import AppKit
import Combine
import CoreGraphics
import Foundation
import KotoverlayCore
import os

enum TranslationPresentationMode: String, CaseIterable, Identifiable {
    case companion
    case inPlace

    var id: String { rawValue }
    var title: String {
        switch self {
        case .companion: "Companion panel"
        case .inPlace: "In-place overlay"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var ollamaReady = false
    @Published private(set) var discordAvailable = false
    @Published private(set) var statusMessage = "Checking readiness…"
    @Published private(set) var translationCount = 0
    @Published private(set) var results: [TranslationResult] = []
    @Published private(set) var selectedModel: String
    @Published private(set) var installedModels: [String] = []
    @Published private(set) var persistentCacheEnabled: Bool
    @Published private(set) var presentationMode: TranslationPresentationMode
    @Published private(set) var alwaysShowOverlayOriginals: Bool
    @Published private(set) var diagnosticsSummary = "No scan has completed."

    var canStart: Bool {
        screenRecordingGranted && ollamaReady && discordAvailable
    }

    var ollamaReadinessDetail: String {
        if ollamaReady { return "Ready" }
        if installedModels.isEmpty { return "Unavailable" }
        return "Selected model is not installed"
    }

    private var provider: OllamaTranslationProvider
    private let cache: LayeredTranslationCache
    private var pipeline: LiveTranslationPipeline
    private var scanTask: Task<Void, Never>?
    private var latestPipelineTask: Task<Void, Never>?
    private var lastDiscordFrame: CGRect?
    private var lastDiscordWindowID: CGWindowID?
    private var resultsDiscordFrame: CGRect?
    private var performanceMetrics = RuntimePerformanceMetrics()
    private let performanceLog = OSLog(
        subsystem: "dev.niyy.Kotoverlay",
        category: "Performance"
    )

    private lazy var panelController = CompanionPanelController { [weak self] in
        self?.pause()
    }
    private lazy var overlayController = InPlaceOverlayController()

    init() {
        let persistenceEnabled = UserDefaults.standard.bool(
            forKey: "persistentTranslationCacheEnabled"
        )
        let storedMode = UserDefaults.standard.string(forKey: "translationPresentationMode")
        presentationMode = TranslationPresentationMode(rawValue: storedMode ?? "") ?? .companion
        alwaysShowOverlayOriginals = UserDefaults.standard.bool(
            forKey: "alwaysShowOverlayOriginals"
        )
        let initialModel = UserDefaults.standard.string(forKey: "selectedOllamaModel")
            ?? OllamaModelSelection.recommendedModel
        selectedModel = initialModel
        let provider = Self.makeProvider(model: initialModel)
        let persistent = PersistentTranslationCache(fileURL: Self.cacheURL())
        let cache = LayeredTranslationCache(
            persistent: persistent,
            persistenceEnabled: persistenceEnabled
        )
        persistentCacheEnabled = persistenceEnabled
        self.provider = provider
        self.cache = cache
        pipeline = Self.makePipeline(model: initialModel, provider: provider, cache: cache)
        overlayController.setAlwaysShowOriginals(alwaysShowOverlayOriginals)
    }

    func refreshReadiness() {
        Task { await refreshReadinessNow() }
    }

    func requestScreenRecordingPermission() {
        screenRecordingGranted = ScreenCapturePermission.requestIfNeeded()
        if !screenRecordingGranted {
            openPrivacySettings(anchor: "Privacy_ScreenCapture")
        }
        refreshReadiness()
    }

    func requestAccessibilityPermission() {
        accessibilityGranted = AccessibilityPermission.requestIfNeeded()
        refreshReadiness()
    }

    func start() {
        guard !isRunning else { return }
        guard canStart else {
            statusMessage = "Resolve the required readiness items first."
            refreshReadiness()
            return
        }
        isRunning = true
        performanceMetrics.reset()
        statusMessage = "Watching Discord…"
        scanTask = Task { [weak self] in
            await self?.scanLoop()
        }
    }

    func pause() {
        guard isRunning || scanTask != nil else { return }
        isRunning = false
        scanTask?.cancel()
        scanTask = nil
        latestPipelineTask?.cancel()
        latestPipelineTask = nil
        let currentPipeline = pipeline
        Task { await currentPipeline.cancel() }
        panelController.hide()
        overlayController.clear()
        statusMessage = "Paused"
    }

    func retry() {
        pause()
        Task {
            await refreshReadinessNow()
            if canStart { start() }
        }
    }

    func clearCache() {
        Task {
            do {
                try await cache.removeAll()
                results = []
                translationCount = 0
                statusMessage = "Translation cache cleared."
                presentCurrentResults()
            } catch {
                statusMessage = "Could not clear the local cache."
            }
        }
    }

    func setPersistentCacheEnabled(_ enabled: Bool) {
        persistentCacheEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "persistentTranslationCacheEnabled")
        Task {
            await cache.setPersistenceEnabled(enabled)
            statusMessage = enabled
                ? "Persistent translation cache enabled."
                : "Persistent translation cache disabled."
        }
    }

    func setSelectedModel(_ model: String) {
        guard installedModels.contains(model), selectedModel != model else { return }
        pause()
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "selectedOllamaModel")
        provider = Self.makeProvider(model: model)
        pipeline = Self.makePipeline(model: model, provider: provider, cache: cache)
        results = []
        translationCount = 0
        resultsDiscordFrame = nil
        statusMessage = "Model changed to \(model). Ready to start."
        refreshReadiness()
    }

    func setPresentationMode(_ mode: TranslationPresentationMode) {
        guard presentationMode != mode else { return }
        presentationMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "translationPresentationMode")
        presentCurrentResults()
    }

    func setAlwaysShowOverlayOriginals(_ enabled: Bool) {
        alwaysShowOverlayOriginals = enabled
        UserDefaults.standard.set(enabled, forKey: "alwaysShowOverlayOriginals")
        overlayController.setAlwaysShowOriginals(enabled)
    }

    func copyDiagnostics() {
        let report = """
        Kotoverlay diagnostics
        running=\(isRunning)
        screenRecording=\(screenRecordingGranted)
        accessibility=\(accessibilityGranted)
        ollama=\(ollamaReady)
        selectedModel=\(selectedModel)
        installedModels=\(installedModels.joined(separator: ","))
        discord=\(discordAvailable)
        persistentCache=\(persistentCacheEnabled)
        cacheLimits=memory:\(TranslationCacheCapacity.memory),persistent:\(TranslationCacheCapacity.persistent)
        candidateLimit=\(LivePipelineConfiguration.defaultMaximumCandidatesPerSnapshot)
        \(diagnosticsSummary)
        \(performanceMetrics.diagnosticsLines().joined(separator: "\n"))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        statusMessage = "Content-free diagnostics copied."
    }

    private func refreshReadinessNow() async {
        screenRecordingGranted = ScreenCapturePermission.isGranted
        accessibilityGranted = AccessibilityPermission.isGranted
        discordAvailable = !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.hnc.Discord"
        ).isEmpty
        do {
            let models = try await provider.availableModels()
            installedModels = OllamaModelSelection.installedNames(from: models)
            let storedModel = UserDefaults.standard.string(forKey: "selectedOllamaModel")
            let initialModel = OllamaModelSelection.initialModel(
                storedModel: storedModel,
                installedModels: installedModels
            )
            if initialModel != selectedModel {
                selectedModel = initialModel
                provider = Self.makeProvider(model: initialModel)
                pipeline = Self.makePipeline(
                    model: initialModel,
                    provider: provider,
                    cache: cache
                )
                UserDefaults.standard.set(initialModel, forKey: "selectedOllamaModel")
            }
            ollamaReady = installedModels.contains(selectedModel)
        } catch {
            installedModels = []
            ollamaReady = false
        }
        if !isRunning {
            statusMessage = canStart ? "Ready to start" : "Setup required"
        }
    }

    private func scanLoop() async {
        let clock = ContinuousClock()
        var changeDetector = FrameChangeDetector()
        var scanSchedule = AdaptiveScanSchedule()
        var captureBackoff = RetryBackoff()
        var ollamaBackoff = RetryBackoff()

        while !Task.isCancelled {
            let started = clock.now
            var interval = scanSchedule.activeInterval

            if !ollamaReady {
                await refreshReadinessNow()
                guard !Task.isCancelled else { break }
                if !ollamaReady {
                    statusMessage = "Waiting for Ollama to restart…"
                    interval = ollamaBackoff.nextDelay()
                    let elapsed = started.duration(to: clock.now)
                    if elapsed < interval {
                        try? await Task.sleep(for: interval - elapsed)
                    }
                    continue
                }
                ollamaBackoff.reset()
                changeDetector = FrameChangeDetector()
                scanSchedule.reset()
                statusMessage = "Ollama reconnected; resuming…"
            }

            do {
                let capture = try await measure(
                    stage: .capture,
                    signpostName: "Discord capture"
                ) {
                    try await DiscordWindowCapturer().capture()
                }
                try Task.checkCancellation()
                discordAvailable = true
                lastDiscordFrame = capture.frame
                lastDiscordWindowID = capture.windowID
                presentCurrentResults()

                let changed = try changeDetector.hasMeaningfulChange(image: capture.image)
                performanceMetrics.recordFrame(changed: changed)
                interval = scanSchedule.interval(afterMeaningfulChange: changed)
                if changed {
                    let recognized = try await measure(
                        stage: .ocr,
                        signpostName: "Vision OCR"
                    ) {
                        try await recognize(capture)
                    }
                    try Task.checkCancellation()
                    let observations = DiscordObservationFilter().filter(
                        recognized,
                        in: capture.frame
                    )
                    let recognizedLines = observations
                        .sorted(by: visualOrder)
                        .enumerated()
                        .map { DetectedText(observation: $0.element, visibleOrder: $0.offset) }
                    let filter = EnglishTextFilter()
                    let texts = DiscordMessageGrouper().group(
                        recognizedLines,
                        filteringWith: filter
                    )
                    let snapshot = TextSnapshot(
                        contextID: "discord-window-\(capture.windowID)",
                        windowID: capture.windowID,
                        texts: texts
                    )
                    statusMessage = "Translating \(texts.count) OCR regions…"
                    let currentPipeline = pipeline
                    latestPipelineTask?.cancel()
                    latestPipelineTask = Task { [weak self] in
                        guard let self else { return }
                        let run = await self.measure(
                            stage: .translation,
                            signpostName: "Local translation"
                        ) {
                            await currentPipeline.process(snapshot) { [weak self] partialResults in
                                guard let self else { return }
                                await self.applyProgress(
                                    partialResults,
                                    discordFrame: capture.frame
                                )
                            }
                        }
                        self.apply(run, discordFrame: capture.frame)
                    }
                }
                captureBackoff.reset()
            } catch is CancellationError {
                break
            } catch let error as WindowCaptureError {
                performanceMetrics.recordFailure()
                handleCaptureError(error)
                interval = captureBackoff.nextDelay()
            } catch {
                performanceMetrics.recordFailure()
                statusMessage = "Capture or OCR failed; retrying…"
                interval = captureBackoff.nextDelay()
            }

            let elapsed = started.duration(to: clock.now)
            if elapsed < interval {
                try? await Task.sleep(for: interval - elapsed)
            }
        }
    }

    private func recognize(_ capture: CapturedWindow) async throws -> [OCRObservation] {
        try await Task.detached(priority: .userInitiated) {
            try VisionTextRecognizer().recognize(
                image: capture.image,
                windowFrame: capture.frame,
                options: VisionRecognitionOptions(
                    level: .accurate,
                    minimumConfidence: 0.45,
                    regionOfInterest: DiscordOCRRegion.messageContent
                )
            )
        }.value
    }

    private func measure<T>(
        stage: RuntimeMetricStage,
        signpostName: StaticString,
        operation: () async throws -> T
    ) async rethrows -> T {
        let clock = ContinuousClock()
        let started = clock.now
        let signpostID = OSSignpostID(log: performanceLog)
        os_signpost(
            .begin,
            log: performanceLog,
            name: signpostName,
            signpostID: signpostID
        )
        defer {
            os_signpost(
                .end,
                log: performanceLog,
                name: signpostName,
                signpostID: signpostID
            )
            performanceMetrics.record(
                stage: stage,
                duration: started.duration(to: clock.now)
            )
        }
        return try await operation()
    }

    private func apply(_ run: PipelineRun, discordFrame: CGRect) {
        guard isRunning, !run.diagnostics.superseded else { return }
        results = run.results
        resultsDiscordFrame = discordFrame
        translationCount = run.results.count
        let failures = run.diagnostics.failureCounts.values.reduce(0, +)
        let providerFailures = run.diagnostics.failureCounts[.providerUnavailable, default: 0]
        diagnosticsSummary = [
            "observed=\(run.diagnostics.observedCount)",
            "eligible=\(run.diagnostics.eligibleCount)",
            "duplicates=\(run.diagnostics.duplicateCount)",
            "backpressureDrops=\(run.diagnostics.backpressureDropCount)",
            "cacheHits=\(run.diagnostics.cacheHitCount)",
            "translated=\(run.diagnostics.translatedCount)",
            "failures=\(failures)"
        ].joined(separator: " ")
        if providerFailures > 0 {
            ollamaReady = false
            statusMessage = "Waiting for Ollama to restart…"
        } else {
            statusMessage = failures == 0
                ? "Showing \(run.results.count) translations"
                : "Showing \(run.results.count) translations; \(failures) failed"
        }
        presentCurrentResults()
    }

    private func applyProgress(_ partialResults: [TranslationResult], discordFrame: CGRect) {
        guard isRunning else { return }
        results = partialResults
        resultsDiscordFrame = discordFrame
        translationCount = partialResults.count
        statusMessage = "Showing \(partialResults.count) translations…"
        presentCurrentResults()
    }

    private func handleCaptureError(_ error: WindowCaptureError) {
        switch error {
        case .permissionRequired:
            screenRecordingGranted = false
            pause()
            statusMessage = "Screen Recording permission is required."
        case .applicationNotFound, .windowNotFound:
            discordAvailable = false
            statusMessage = "Waiting for a visible Discord window…"
            panelController.hide()
            overlayController.hideAll()
        default:
            statusMessage = "Discord capture unavailable; retrying…"
        }
    }

    private func presentCurrentResults() {
        guard isRunning,
              let currentDiscordFrame = lastDiscordFrame,
              let discordWindowID = lastDiscordWindowID else {
            panelController.hide()
            overlayController.hideAll()
            return
        }
        switch presentationMode {
        case .companion:
            overlayController.clear()
            panelController.update(
                results: results,
                status: statusMessage,
                discordFrame: currentDiscordFrame
            )
        case .inPlace:
            panelController.hide()
            guard let sourceDiscordFrame = resultsDiscordFrame else {
                overlayController.hideAll()
                return
            }
            overlayController.update(
                results: results,
                sourceDiscordFrame: sourceDiscordFrame,
                currentDiscordFrame: currentDiscordFrame,
                discordWindowID: discordWindowID,
                discordIsFrontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    == "com.hnc.Discord"
            )
        }
    }

    private func visualOrder(_ lhs: OCRObservation, _ rhs: OCRObservation) -> Bool {
        if lhs.screenRect.minY == rhs.screenRect.minY {
            return lhs.screenRect.minX < rhs.screenRect.minX
        }
        return lhs.screenRect.minY < rhs.screenRect.minY
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func cacheURL() -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("Kotoverlay", isDirectory: true)
            .appendingPathComponent("translations-v2.json")
    }

    private static func makeProvider(model: String) -> OllamaTranslationProvider {
        OllamaTranslationProvider(
            configuration: try! OllamaConfiguration(model: model)
        )
    }

    private static func makePipeline(
        model: String,
        provider: OllamaTranslationProvider,
        cache: LayeredTranslationCache
    ) -> LiveTranslationPipeline {
        LiveTranslationPipeline(
            provider: provider,
            cache: cache,
            configuration: LivePipelineConfiguration(
                providerID: "ollama:\(model)",
                promptVersion: "2",
                maximumConcurrentTranslations: 1,
                maximumCandidatesPerSnapshot:
                    LivePipelineConfiguration.defaultMaximumCandidatesPerSnapshot
            )
        )
    }
}
