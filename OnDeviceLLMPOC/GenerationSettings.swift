import Foundation
import FoundationModels

/// User-tunable knobs for how the model generates text. Persisted in
/// `UserDefaults` so your preferences survive app launches, and mapped to a
/// `GenerationOptions` value that the session applies per request.
struct GenerationSettings: Codable, Equatable {
    /// 0 = focused/deterministic, 2 = wild. Always applied.
    var temperature: Double = 0.9

    /// Upper bound on the reply length, in tokens. `0` means "no limit".
    var maxResponseTokens: Double = 512

    /// How the next token is picked from the model's probability distribution.
    enum Sampling: String, Codable, CaseIterable, Identifiable {
        case `default`   // model's own balanced sampling
        case greedy      // always the single most-likely token (repeatable)
        case creative    // sample from the top 40 tokens (more variety)

        var id: String { rawValue }

        var label: String {
            switch self {
            case .default:  return "Balanced"
            case .greedy:   return "Precise"
            case .creative: return "Creative"
            }
        }
    }

    var sampling: Sampling = .default

    /// Translates the UI settings into the framework's `GenerationOptions`.
    var generationOptions: GenerationOptions {
        let mode: GenerationOptions.SamplingMode?
        switch sampling {
        case .default:  mode = nil
        case .greedy:   mode = .greedy
        case .creative: mode = .random(top: 40)
        }
        let maxTokens = maxResponseTokens <= 0 ? nil : Int(maxResponseTokens)
        return GenerationOptions(
            samplingMode: mode,
            temperature: temperature,
            maximumResponseTokens: maxTokens
        )
    }

    // MARK: - Persistence

    private static let defaultsKey = "generationSettings"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    static func load() -> GenerationSettings {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(GenerationSettings.self, from: data)
        else {
            return GenerationSettings()
        }
        return decoded
    }
}
