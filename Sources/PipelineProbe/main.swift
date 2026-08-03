@preconcurrency import AppKit
import CoreGraphics
import Foundation
import KotoverlayCore

private struct Arguments {
    var prompt = false
    var showContent = false
    var watch = false
    var intervalSeconds = 0.5
    var iterations: Int?
    var useFastRecognition = false
    var bundleIdentifier = "com.hnc.Discord"
    var minimumConfidence: Float = 0.45
    var model = "qwen3:1.7b"
    var timeoutSeconds = 30.0
    var cachePath: String?

    static func parse(_ values: [String]) throws -> Arguments {
        var result = Arguments()
        var index = 0
        while index < values.count {
            switch values[index] {
            case "--prompt": result.prompt = true
            case "--show-content": result.showContent = true
            case "--watch": result.watch = true
            case "--fast": result.useFastRecognition = true
            case "--help", "-h":
                printUsage()
                exit(EXIT_SUCCESS)
            case "--bundle-id":
                result.bundleIdentifier = try next(values, index: &index, flag: "--bundle-id")
            case "--model":
                result.model = try next(values, index: &index, flag: "--model")
            case "--cache":
                result.cachePath = try next(values, index: &index, flag: "--cache")
            case "--interval":
                let raw = try next(values, index: &index, flag: "--interval")
                guard let value = Double(raw), value >= 0.5 else {
                    throw ArgumentError.invalidValue("--interval")
                }
                result.intervalSeconds = value
            case "--iterations":
                let raw = try next(values, index: &index, flag: "--iterations")
                guard let value = Int(raw), value > 0 else {
                    throw ArgumentError.invalidValue("--iterations")
                }
                result.iterations = value
            case "--min-confidence":
                let raw = try next(values, index: &index, flag: "--min-confidence")
                guard let value = Float(raw), (0...1).contains(value) else {
                    throw ArgumentError.invalidValue("--min-confidence")
                }
                result.minimumConfidence = value
            case "--timeout":
                let raw = try next(values, index: &index, flag: "--timeout")
                guard let value = Double(raw), value >= 0.1 else {
                    throw ArgumentError.invalidValue("--timeout")
                }
                result.timeoutSeconds = value
            default:
                throw ArgumentError.unknownFlag(values[index])
            }
            index += 1
        }
        return result
    }

    private static func next(
        _ values: [String],
        index: inout Int,
        flag: String
    ) throws -> String {
        index += 1
        guard index < values.count else { throw ArgumentError.missingValue(flag) }
        return values[index]
    }
}

private enum ArgumentError: Error, LocalizedError {
    case unknownFlag(String)
    case missingValue(String)
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case let .unknownFlag(flag): "Unknown option: \(flag)"
        case let .missingValue(flag): "Missing value after \(flag)"
        case let .invalidValue(flag): "Invalid value for \(flag)"
        }
    }
}

private func printUsage() {
    print("""
    Usage: pipelineprobe [options]

      --prompt              Ask for Screen Recording permission if needed
      --watch               Continue capturing changed Discord frames
      --interval SECONDS    Capture interval, minimum 0.5 (default: 0.5)
      --iterations N        Stop after N captures
      --fast                Use faster Vision recognition
      --model NAME          Installed Ollama model (default: qwen3:1.7b)
      --timeout SECONDS     Translation timeout (default: 30)
      --min-confidence N    OCR/filter confidence from 0 through 1
      --cache PATH          Explicitly enable a versioned persistent cache
      --show-content        Print source and translation (redacted by default)
      --bundle-id ID        Target app (default: com.hnc.Discord)
      -h, --help            Show this help

    Capture stays in memory. Message content is not logged unless
    --show-content is supplied. Persistent caching is off unless --cache is set.
    """)
}

@main
private struct PipelineProbe {
    @MainActor
    static func main() async {
        do {
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            let arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
            if arguments.prompt { _ = ScreenCapturePermission.requestIfNeeded() }
            try await run(arguments)
        } catch {
            FileHandle.standardError.write(
                Data("pipelineprobe: \(error.localizedDescription)\n".utf8)
            )
            exit(EXIT_FAILURE)
        }
    }

    @MainActor
    private static func run(_ arguments: Arguments) async throws {
        let provider = OllamaTranslationProvider(
            configuration: try OllamaConfiguration(
                model: arguments.model,
                timeout: .seconds(arguments.timeoutSeconds)
            )
        )
        let cache: any TranslationCache
        if let cachePath = arguments.cachePath {
            cache = LayeredTranslationCache(
                persistent: PersistentTranslationCache(
                    fileURL: URL(fileURLWithPath: cachePath).standardizedFileURL
                )
            )
        } else {
            cache = InMemoryTranslationCache()
        }
        let pipeline = LiveTranslationPipeline(
            provider: provider,
            cache: cache,
            filter: EnglishTextFilter(minimumConfidence: arguments.minimumConfidence),
            configuration: LivePipelineConfiguration(
                providerID: "ollama:\(arguments.model)",
                promptVersion: "1",
                maximumConcurrentTranslations: 1
            )
        )

        var changeDetector = FrameChangeDetector()
        var completedIterations = 0
        var latestRun: Task<Void, Never>?
        let clock = ContinuousClock()

        repeat {
            let iterationStart = clock.now
            let capture = try await DiscordWindowCapturer().capture(
                bundleIdentifier: arguments.bundleIdentifier
            )
            let changed = try changeDetector.hasMeaningfulChange(image: capture.image)
            if changed {
                let recognized = try VisionTextRecognizer().recognize(
                    image: capture.image,
                    windowFrame: capture.frame,
                    options: VisionRecognitionOptions(
                        level: arguments.useFastRecognition ? .fast : .accurate,
                        minimumConfidence: arguments.minimumConfidence,
                        regionOfInterest: DiscordOCRRegion.messageContent
                    )
                )
                let observations = DiscordObservationFilter().filter(
                    recognized,
                    in: capture.frame
                )
                let texts = observations
                    .sorted {
                        if $0.screenRect.minY == $1.screenRect.minY {
                            return $0.screenRect.minX < $1.screenRect.minX
                        }
                        return $0.screenRect.minY < $1.screenRect.minY
                    }
                    .enumerated()
                    .map { DetectedText(observation: $0.element, visibleOrder: $0.offset) }
                let snapshot = TextSnapshot(
                    contextID: "discord-window-\(capture.windowID)",
                    windowID: capture.windowID,
                    texts: texts
                )
                print("capture windowID=\(capture.windowID) changed=true observations=\(texts.count)")
                latestRun = Task {
                    let run = await pipeline.process(snapshot)
                    printRun(run, showContent: arguments.showContent)
                }
            } else {
                print("capture windowID=\(capture.windowID) changed=false ocr=skipped")
            }

            completedIterations += 1
            guard arguments.watch,
                  arguments.iterations.map({ completedIterations < $0 }) ?? true else {
                break
            }
            let elapsed = iterationStart.duration(to: clock.now)
            let interval = Duration.seconds(arguments.intervalSeconds)
            if elapsed < interval { try await Task.sleep(for: interval - elapsed) }
        } while true

        await latestRun?.value
    }

    private static func printRun(_ run: PipelineRun, showContent: Bool) {
        let failures = run.diagnostics.failureCounts
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: ",")
        print(
            "pipeline observed=\(run.diagnostics.observedCount) "
                + "eligible=\(run.diagnostics.eligibleCount) "
                + "duplicates=\(run.diagnostics.duplicateCount) "
                + "cacheHits=\(run.diagnostics.cacheHitCount) "
                + "translated=\(run.diagnostics.translatedCount) "
                + "superseded=\(run.diagnostics.superseded) "
                + "failures=[\(failures)]"
        )
        guard showContent else { return }
        for result in run.results {
            print("source=\(escaped(result.sourceText))")
            print("translation=\(escaped(result.translatedText))")
        }
    }

    private static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
