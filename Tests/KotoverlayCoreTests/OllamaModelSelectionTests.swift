import Testing
@testable import KotoverlayCore

@Suite("Ollama model selection")
struct OllamaModelSelectionTests {
    @Test("Normalizes and deduplicates installed model names")
    func installedNames() {
        let models = [
            OllamaModel(name: "qwen3:1.7b", model: "qwen3:1.7b"),
            OllamaModel(name: "qwen3:4b", model: "qwen3:4b"),
            OllamaModel(name: "qwen3:1.7b", model: "duplicate"),
            OllamaModel(name: "  ", model: "empty")
        ]

        #expect(OllamaModelSelection.installedNames(from: models) == [
            "qwen3:1.7b", "qwen3:4b"
        ])
    }

    @Test("Keeps an installed stored choice")
    func storedChoice() {
        #expect(OllamaModelSelection.initialModel(
            storedModel: "qwen3:1.7b",
            installedModels: ["qwen3:1.7b", "qwen3:4b"]
        ) == "qwen3:1.7b")
    }

    @Test("Prefers the validated model on first launch")
    func recommendedChoice() {
        #expect(OllamaModelSelection.initialModel(
            storedModel: nil,
            installedModels: ["qwen3:1.7b", "qwen3:4b"]
        ) == "qwen3:1.7b")
    }

    @Test("Falls back to the lightweight model")
    func lightweightFallback() {
        #expect(OllamaModelSelection.initialModel(
            storedModel: "missing:model",
            installedModels: ["qwen3:1.7b"]
        ) == "qwen3:1.7b")
    }
}
