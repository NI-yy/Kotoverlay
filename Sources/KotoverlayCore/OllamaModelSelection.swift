import Foundation

public enum OllamaModelSelection {
    public static let recommendedModel = "qwen3:1.7b"
    public static let lightweightModel = "qwen3:1.7b"

    public static func installedNames(from models: [OllamaModel]) -> [String] {
        var seen = Set<String>()
        return models.compactMap { model in
            let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
    }

    public static func initialModel(storedModel: String?, installedModels: [String]) -> String {
        if let storedModel,
           !storedModel.isEmpty,
           installedModels.contains(storedModel) {
            return storedModel
        }
        if installedModels.contains(recommendedModel) {
            return recommendedModel
        }
        if installedModels.contains("qwen3:4b") {
            return "qwen3:4b"
        }
        return installedModels.first ?? recommendedModel
    }
}
