@preconcurrency import AppKit
import CoreGraphics
import Foundation
import KotoverlayCore

private struct Arguments {
    var prompt = false
    var showText = false
    var useFastRecognition = false
    var watch = false
    var intervalSeconds = 0.5
    var iterations: Int?
    var wholeWindow = false
    var bundleIdentifier = "com.hnc.Discord"
    var minimumConfidence: Float = 0.35

    static func parse(_ values: [String]) throws -> Arguments {
        var result = Arguments()
        var index = 0
        while index < values.count {
            switch values[index] {
            case "--prompt": result.prompt = true
            case "--show-text": result.showText = true
            case "--fast": result.useFastRecognition = true
            case "--watch": result.watch = true
            case "--whole-window": result.wholeWindow = true
            case "--help", "-h":
                printUsage()
                exit(EXIT_SUCCESS)
            case "--bundle-id":
                result.bundleIdentifier = try nextValue(values, index: &index, flag: "--bundle-id")
            case "--min-confidence":
                let raw = try nextValue(values, index: &index, flag: "--min-confidence")
                guard let value = Float(raw), (0...1).contains(value) else {
                    throw ArgumentError.invalidValue("--min-confidence")
                }
                result.minimumConfidence = value
            case "--interval":
                let raw = try nextValue(values, index: &index, flag: "--interval")
                guard let value = Double(raw), value >= 0.5 else {
                    throw ArgumentError.invalidValue("--interval")
                }
                result.intervalSeconds = value
            case "--iterations":
                let raw = try nextValue(values, index: &index, flag: "--iterations")
                guard let value = Int(raw), value > 0 else {
                    throw ArgumentError.invalidValue("--iterations")
                }
                result.iterations = value
            default:
                throw ArgumentError.unknownFlag(values[index])
            }
            index += 1
        }
        return result
    }

    private static func nextValue(_ values: [String], index: inout Int, flag: String) throws -> String {
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
    Usage: ocrprobe [options]

      --prompt              Ask macOS for Screen Recording permission if needed
      --show-text           Print recognized text (redacted by default)
      --fast                Use faster, less accurate Vision recognition
      --watch               Repeat with frame-change detection
      --interval SECONDS    Watch interval, minimum 0.5 (default: 0.5)
      --iterations N        Stop watch mode after N captures (diagnostics/tests)
      --whole-window        OCR Discord chrome and sidebars too
      --min-confidence N    Keep confidence from 0 through 1 (default: 0.35)
      --bundle-id ID        Target bundle identifier (default: com.hnc.Discord)
      -h, --help            Show this help

    Only the selected application window is captured. The image stays in memory
    and is never written to disk by this command.
    """)
}

private func format(_ duration: Duration) -> String {
    let components = duration.components
    let milliseconds = Double(components.seconds) * 1_000
        + Double(components.attoseconds) / 1_000_000_000_000_000
    return String(format: "%.1f ms", milliseconds)
}

private func format(_ frame: CGRect) -> String {
    String(
        format: "x=%.0f y=%.0f w=%.0f h=%.0f",
        frame.origin.x,
        frame.origin.y,
        frame.width,
        frame.height
    )
}

private func escaped(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
}

@main
private struct OCRProbe {
    @MainActor
    static func main() async {
        do {
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            let arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
            if arguments.prompt {
                _ = ScreenCapturePermission.requestIfNeeded()
            }
            try await scan(arguments: arguments)
        } catch {
            FileHandle.standardError.write(Data("ocrprobe: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    @MainActor
    private static func scan(arguments: Arguments) async throws {
        let clock = ContinuousClock()
        var changeDetector = FrameChangeDetector()
        var completedIterations = 0

        repeat {
            let iterationStart = clock.now
            let captureStart = clock.now
            let capture = try await DiscordWindowCapturer().capture(
                bundleIdentifier: arguments.bundleIdentifier
            )
            let captureElapsed = captureStart.duration(to: clock.now)
            let changed = try changeDetector.hasMeaningfulChange(image: capture.image)

            if changed {
                let recognitionStart = clock.now
                let observations = try VisionTextRecognizer().recognize(
                    image: capture.image,
                    windowFrame: capture.frame,
                    options: VisionRecognitionOptions(
                        level: arguments.useFastRecognition ? .fast : .accurate,
                        minimumConfidence: arguments.minimumConfidence,
                        regionOfInterest: arguments.wholeWindow
                            ? CGRect(x: 0, y: 0, width: 1, height: 1)
                            : DiscordOCRRegion.messageContent
                    )
                )
                let recognitionElapsed = recognitionStart.duration(to: clock.now)
                print("windowID=\(capture.windowID) changed=true frame=[\(format(capture.frame))] pixels=\(capture.image.width)x\(capture.image.height) scale=\(String(format: "%.1f", capture.scaleFactor)) capture=\(format(captureElapsed)) ocr=\(format(recognitionElapsed)) observations=\(observations.count)")
                printObservations(observations, showText: arguments.showText)
            } else {
                print("windowID=\(capture.windowID) changed=false capture=\(format(captureElapsed)) ocr=skipped observations=0")
            }

            completedIterations += 1
            guard arguments.watch,
                  arguments.iterations.map({ completedIterations < $0 }) ?? true else {
                break
            }

            let elapsed = iterationStart.duration(to: clock.now)
            let interval = Duration.seconds(arguments.intervalSeconds)
            if elapsed < interval {
                try await Task.sleep(for: interval - elapsed)
            }
        } while true
    }

    private static func printObservations(_ observations: [OCRObservation], showText: Bool) {
        for observation in observations {
            let text = showText
                ? escaped(observation.text)
                : "<redacted length=\(observation.text.count)>"
            print("id=\(observation.identifier) confidence=\(String(format: "%.2f", observation.confidence)) frame=[\(format(observation.screenRect))] text=\(text)")
        }
    }
}
