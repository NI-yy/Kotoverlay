import Darwin
import Foundation
import KotoverlayCore

private struct Arguments {
    var model = "qwen3:1.7b"
    var timeoutSeconds = 30.0
    var listModels = false
    var health = false
    var textParts: [String] = []

    static func parse(_ values: [String]) throws -> Arguments {
        var result = Arguments()
        var index = 0
        while index < values.count {
            switch values[index] {
            case "--model":
                result.model = try nextValue(values, index: &index, flag: "--model")
            case "--timeout":
                let raw = try nextValue(values, index: &index, flag: "--timeout")
                guard let seconds = Double(raw), seconds >= 0.1 else {
                    throw ArgumentError.invalidValue("--timeout")
                }
                result.timeoutSeconds = seconds
            case "--list-models": result.listModels = true
            case "--health": result.health = true
            case "--help", "-h":
                printUsage()
                exit(EXIT_SUCCESS)
            default:
                if values[index].hasPrefix("-") {
                    throw ArgumentError.unknownFlag(values[index])
                }
                result.textParts.append(values[index])
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
    Usage: kotoverlay-cli [options] "English text"
           printf 'English text' | kotoverlay-cli [options]

      --model NAME          Ollama model (default: qwen3:1.7b)
      --timeout SECONDS     Overall translation timeout (default: 30)
      --list-models         List locally installed Ollama models
      --health              Check that Ollama is reachable
      -h, --help            Show this help

    The endpoint is fixed to http://127.0.0.1:11434. Ollama's response stream is
    parsed incrementally; the restored final translation is written to stdout.
    Timing and errors go to stderr.
    """)
}

private func inputText(arguments: Arguments) throws -> String {
    if !arguments.textParts.isEmpty {
        return arguments.textParts.joined(separator: " ")
    }
    guard isatty(STDIN_FILENO) == 0 else {
        throw CLIError.missingText
    }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8),
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw CLIError.missingText
    }
    return text
}

private enum CLIError: Error, LocalizedError {
    case missingText

    var errorDescription: String? {
        "Provide English text as an argument or through standard input."
    }
}

private func writeStandardError(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
}

@main
private struct KotoverlayCLI {
    static func main() async {
        do {
            let arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
            let configuration = try OllamaConfiguration(
                model: arguments.model,
                timeout: .seconds(arguments.timeoutSeconds)
            )
            let provider = OllamaTranslationProvider(configuration: configuration)

            if arguments.listModels {
                for model in try await provider.availableModels() {
                    print(model.name)
                }
                return
            }
            if arguments.health {
                try await provider.healthCheck()
                print("Ollama is reachable.")
                return
            }

            let source = try inputText(arguments: arguments)
            let clock = ContinuousClock()
            let started = clock.now
            for try await chunk in provider.translationStream(
                for: TranslationRequest(sourceText: source)
            ) {
                FileHandle.standardOutput.write(Data(chunk.utf8))
            }
            FileHandle.standardOutput.write(Data("\n".utf8))
            let elapsed = started.duration(to: clock.now)
            writeStandardError("Translated locally in \(format(elapsed)).\n")
        } catch {
            writeStandardError("kotoverlay-cli: \(error.localizedDescription)\n")
            exit(EXIT_FAILURE)
        }
    }

    private static func format(_ duration: Duration) -> String {
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.1f ms", milliseconds)
    }
}
