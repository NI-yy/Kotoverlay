import Foundation
import KotoverlayCore

private struct Arguments {
    var prompt = false
    var watch = false
    var redactText = false
    var allElements = false
    var intervalSeconds = 1.0
    var bundleIdentifier = "com.hnc.Discord"
    var maximumElements = 2_000
    var maximumDepth = 30
    var timeoutMilliseconds = 250

    static func parse(_ values: [String]) throws -> Arguments {
        var result = Arguments()
        var index = 0
        while index < values.count {
            switch values[index] {
            case "--prompt": result.prompt = true
            case "--watch": result.watch = true
            case "--redact-text": result.redactText = true
            case "--all-elements": result.allElements = true
            case "--help", "-h":
                printUsage()
                exit(EXIT_SUCCESS)
            case "--bundle-id":
                result.bundleIdentifier = try nextValue(values, index: &index, flag: "--bundle-id")
            case "--max-elements":
                result.maximumElements = try positiveInt(nextValue(values, index: &index, flag: "--max-elements"), flag: "--max-elements")
            case "--max-depth":
                result.maximumDepth = try nonnegativeInt(nextValue(values, index: &index, flag: "--max-depth"), flag: "--max-depth")
            case "--timeout-ms":
                result.timeoutMilliseconds = try positiveInt(nextValue(values, index: &index, flag: "--timeout-ms"), flag: "--timeout-ms")
            case "--interval":
                let raw = try nextValue(values, index: &index, flag: "--interval")
                guard let value = Double(raw), value >= 0.1 else { throw ArgumentError.invalidValue("--interval") }
                result.intervalSeconds = value
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

    private static func positiveInt(_ raw: String, flag: String) throws -> Int {
        guard let value = Int(raw), value > 0 else { throw ArgumentError.invalidValue(flag) }
        return value
    }

    private static func nonnegativeInt(_ raw: String, flag: String) throws -> Int {
        guard let value = Int(raw), value >= 0 else { throw ArgumentError.invalidValue(flag) }
        return value
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
    Usage: axprobe [options]

      --prompt              Ask macOS for Accessibility permission if needed
      --watch               Scan repeatedly (also detects permission changes)
      --redact-text         Print text lengths instead of captured content
      --all-elements        Also print elements that have no text
      --interval SECONDS    Watch interval (default: 1.0)
      --bundle-id ID        Target bundle identifier (default: com.hnc.Discord)
      --max-elements N      Traversal element limit (default: 2000)
      --max-depth N         Traversal depth limit (default: 30)
      --timeout-ms N        Whole-scan time limit (default: 250)
      -h, --help            Show this help

    Message text is printed only because running this diagnostic is an explicit action.
    """)
}

private func escaped(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
}

private func format(_ duration: Duration) -> String {
    let components = duration.components
    let milliseconds = Double(components.seconds) * 1_000
        + Double(components.attoseconds) / 1_000_000_000_000_000
    return String(format: "%.1f ms", milliseconds)
}

private func format(_ frame: CGRect?) -> String {
    guard let frame else { return "-" }
    return String(format: "x=%.0f y=%.0f w=%.0f h=%.0f", frame.origin.x, frame.origin.y, frame.width, frame.height)
}

private func runScan(arguments: Arguments) -> Bool {
    let options = AccessibilityScanOptions(
        bundleIdentifier: arguments.bundleIdentifier,
        maximumElements: arguments.maximumElements,
        maximumDepth: arguments.maximumDepth,
        timeout: .milliseconds(arguments.timeoutMilliseconds)
    )

    do {
        let report = try AccessibilityScanner().scan(options: options)
        let manualAX = report.manualAccessibilityResult.map(String.init) ?? "disabled"
        print("application=\(report.applicationName) pid=\(report.processIdentifier) elements=\(report.snapshots.count) elapsed=\(format(report.elapsed)) stop=\(report.stoppedBecause?.rawValue ?? "complete") manualAX=\(manualAX)")
        for snapshot in report.snapshots {
            guard arguments.allElements || snapshot.text != nil else { continue }
            let displayedText: String
            if let text = snapshot.text {
                displayedText = arguments.redactText
                    ? "<redacted length=\(text.count)>"
                    : escaped(text)
            } else {
                displayedText = "-"
            }
            print("id=\(snapshot.identifier) depth=\(snapshot.depth) role=\(snapshot.role) frame=[\(format(snapshot.frame))] text=\(displayedText)")
        }
        return true
    } catch {
        FileHandle.standardError.write(Data("axprobe: \(error.localizedDescription)\n".utf8))
        return false
    }
}

do {
    let arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
    if arguments.prompt {
        _ = AccessibilityPermission.requestIfNeeded()
    }

    if arguments.watch {
        repeat {
            _ = runScan(arguments: arguments)
            Thread.sleep(forTimeInterval: arguments.intervalSeconds)
        } while true
    } else {
        exit(runScan(arguments: arguments) ? EXIT_SUCCESS : EXIT_FAILURE)
    }
} catch {
    FileHandle.standardError.write(Data("axprobe: \(error.localizedDescription)\n".utf8))
    printUsage()
    exit(EXIT_FAILURE)
}
