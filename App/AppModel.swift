@preconcurrency import AppKit
import Combine
import CoreGraphics
import Foundation
import KotoverlayCore

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
    @Published private(set) var persistentCacheEnabled: Bool
    @Published private(set) var diagnosticsSummary = "No scan has completed."

    var canStart: Bool {
        screenRecordingGranted && ollamaReady && discordAvailable
    }

    private let provider: OllamaTranslationProvider
    private let cache: LayeredTranslationCache
    private let pipeline: LiveTranslationPipeline
    private var scanTask: Task<Void, Never>?
    private var latestPipelineTask: Task<Void, Never>?
    private var lastDiscordFrame: CGRect?

    private lazy var panelController = CompanionPanelController { [weak self] in
        self?.pause()
    }

    init() {
        let persistenceEnabled = UserDefaults.standard.bool(
            forKey: "persistentTranslationCacheEnabled"
        )
        let provider = OllamaTranslationProvider()
        let persistent = PersistentTranslationCache(fileURL: Self.cacheURL())
        let cache = LayeredTranslationCache(
            persistent: persistent,
            persistenceEnabled: persistenceEnabled
        )
        persistentCacheEnabled = persistenceEnabled
        self.provider = provider
        self.cache = cache
        pipeline = LiveTranslationPipeline(
            provider: provider,
            cache: cache,
            configuration: LivePipelineConfiguration(
                providerID: "ollama:qwen3:1.7b",
                promptVersion: "1",
                maximumConcurrentTranslations: 1
            )
        )
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
        Task { await pipeline.cancel() }
        panelController.hide()
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
                if let frame = lastDiscordFrame {
                    panelController.update(results: [], status: statusMessage, discordFrame: frame)
                }
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

    func copyDiagnostics() {
        let report = """
        Kotoverlay diagnostics
        running=\(isRunning)
        screenRecording=\(screenRecordingGranted)
        accessibility=\(accessibilityGranted)
        ollama=\(ollamaReady)
        discord=\(discordAvailable)
        persistentCache=\(persistentCacheEnabled)
        \(diagnosticsSummary)
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
            try await provider.healthCheck()
            ollamaReady = true
        } catch {
            ollamaReady = false
        }
        if !isRunning {
            statusMessage = canStart ? "Ready to start" : "Setup required"
        }
    }

    private func scanLoop() async {
        let clock = ContinuousClock()
        var changeDetector = FrameChangeDetector()

        while !Task.isCancelled {
            let started = clock.now
            do {
                let capture = try await DiscordWindowCapturer().capture()
                try Task.checkCancellation()
                discordAvailable = true
                lastDiscordFrame = capture.frame
                panelController.update(
                    results: results,
                    status: statusMessage,
                    discordFrame: capture.frame
                )

                if try changeDetector.hasMeaningfulChange(image: capture.image) {
                    let recognized = try await recognize(capture)
                    try Task.checkCancellation()
                    let observations = DiscordObservationFilter().filter(
                        recognized,
                        in: capture.frame
                    )
                    let texts = observations
                        .sorted(by: visualOrder)
                        .enumerated()
                        .map { DetectedText(observation: $0.element, visibleOrder: $0.offset) }
                    let snapshot = TextSnapshot(
                        contextID: "discord-window-\(capture.windowID)",
                        windowID: capture.windowID,
                        texts: texts
                    )
                    statusMessage = "Translating \(texts.count) OCR regions…"
                    latestPipelineTask = Task { [weak self] in
                        guard let self else { return }
                        let run = await self.pipeline.process(snapshot) { [weak self] partialResults in
                            guard let self else { return }
                            await self.applyProgress(partialResults, discordFrame: capture.frame)
                        }
                        self.apply(run, discordFrame: capture.frame)
                    }
                }
            } catch is CancellationError {
                break
            } catch let error as WindowCaptureError {
                handleCaptureError(error)
            } catch {
                statusMessage = "Capture or OCR failed; retrying…"
            }

            let elapsed = started.duration(to: clock.now)
            let interval = Duration.milliseconds(500)
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

    private func apply(_ run: PipelineRun, discordFrame: CGRect) {
        guard isRunning, !run.diagnostics.superseded else { return }
        results = run.results
        translationCount = run.results.count
        let failures = run.diagnostics.failureCounts.values.reduce(0, +)
        diagnosticsSummary = [
            "observed=\(run.diagnostics.observedCount)",
            "eligible=\(run.diagnostics.eligibleCount)",
            "duplicates=\(run.diagnostics.duplicateCount)",
            "cacheHits=\(run.diagnostics.cacheHitCount)",
            "translated=\(run.diagnostics.translatedCount)",
            "failures=\(failures)"
        ].joined(separator: " ")
        statusMessage = failures == 0
            ? "Showing \(run.results.count) translations"
            : "Showing \(run.results.count) translations; \(failures) failed"
        panelController.update(
            results: run.results,
            status: statusMessage,
            discordFrame: discordFrame
        )
    }

    private func applyProgress(_ partialResults: [TranslationResult], discordFrame: CGRect) {
        guard isRunning else { return }
        results = partialResults
        translationCount = partialResults.count
        statusMessage = "Showing \(partialResults.count) translations…"
        panelController.update(
            results: partialResults,
            status: statusMessage,
            discordFrame: discordFrame
        )
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
        default:
            statusMessage = "Discord capture unavailable; retrying…"
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
}
