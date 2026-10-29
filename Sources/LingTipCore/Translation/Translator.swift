import Foundation

struct TranslationRequest: Hashable {
    let text: String
    /// BCP-47 code, or nil to auto-detect.
    let source: String?
    let target: String
}

struct TranslationResult: Equatable, Codable {
    struct Alternative: Equatable, Codable {
        var text: String
        var sense: String
    }

    var translation: String
    var transliteration: String?
    var partOfSpeech: String?
    var alternatives: [Alternative] = []
    var detectedSource: String?
    var note: String?
}

protocol Translator {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

enum TranslationError: LocalizedError {
    case missingAPIKey
    case badStatus(Int, String)
    case refused(String?)
    case truncated
    case malformed(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No Claude API key configured."
        case .badStatus(401, _): return "The Claude API rejected the API key."
        case .badStatus(429, _): return "Rate limited by the Claude API."
        case .badStatus(let code, let message): return "Claude API error \(code): \(message)"
        case .refused(let why): return why.map { "Translation declined: \($0)" } ?? "Translation declined by the model."
        case .truncated: return "The translation was cut off."
        case .malformed(let detail): return "Unexpected response: \(detail)"
        case .network(let detail): return "Network error: \(detail)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missingAPIKey, .badStatus(401, _): return "Add your key in LingTip → Settings."
        case .badStatus(429, _): return "Wait a moment and try again."
        case .network: return "Check your internet connection."
        default: return nil
        }
    }
}
