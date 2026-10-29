import Foundation

/// Translates via the Claude Messages API over raw HTTPS (there is no official Swift SDK).
/// Uses structured output so the tooltip gets reliable JSON fields.
struct ClaudeTranslator: Translator {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"
    /// Server-side refusal fallback: if a safety classifier declines, the API re-runs on a
    /// fallback model inside the same call. Remove both lines to opt out.
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    static let fallbacks = "default"

    let settings: AppSettings
    var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard let apiKey = APIKeyStore.anthropicKey, !apiKey.isEmpty else {
            throw TranslationError.missingAPIKey
        }

        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: Self.body(for: request, model: settings.modelID))

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TranslationError.network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw TranslationError.badStatus(status, Self.errorMessage(in: data))
        }
        return try Self.parse(data)
    }

    // MARK: Request

    static func body(for request: TranslationRequest, model: String) -> [String: Any] {
        let userPrompt = """
        Source language: \(request.source ?? "auto")
        Target language: \(request.target)
        Text:
        <<<
        \(request.text)
        >>>
        """
        return [
            "model": model,
            "max_tokens": 2048,
            "system": [["type": "text", "text": systemPrompt]],
            "messages": [["role": "user", "content": userPrompt]],
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": schema],
            ],
            "fallbacks": fallbacks,
        ]
    }

    static let systemPrompt = """
    You power a dictionary tooltip on macOS. The user selects text in any app and presses a shortcut; \
    you translate the selection into the target language (BCP-47 codes are given; "auto" means detect the source).

    Rules:
    - Single word or short phrase (up to ~3 words): put the most likely translation in `translation`, \
    set `part_of_speech`, and give up to 3 `alternatives`, each a distinct meaning or register with a brief sense gloss \
    written in the source language. Do not repeat `translation` among the alternatives.
    - Longer text: translate naturally and faithfully in `translation`; leave `alternatives` empty and `part_of_speech` empty.
    - Hebrew output: include niqqud (vowel points) for single words and short phrases; omit niqqud for longer text.
    - `transliteration`: Latin-script transliteration of `translation` when the target language uses a non-Latin script; otherwise empty.
    - `detected_source_language`: the BCP-47 code of the source text's language.
    - `note`: at most one short sentence of useful context (idiom, false friend, formality, gender), written in the source language; otherwise empty.
    - Use empty strings, not null, for fields that do not apply.
    """

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "translation": ["type": "string"],
            "transliteration": ["type": "string"],
            "part_of_speech": ["type": "string"],
            "alternatives": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string"],
                        "sense": ["type": "string"],
                    ],
                    "required": ["text", "sense"],
                    "additionalProperties": false,
                ],
            ],
            "detected_source_language": ["type": "string"],
            "note": ["type": "string"],
        ],
        "required": ["translation", "transliteration", "part_of_speech", "alternatives", "detected_source_language", "note"],
        "additionalProperties": false,
    ]

    // MARK: Response

    private struct Wire: Decodable {
        var translation: String
        var transliteration: String
        var partOfSpeech: String
        var alternatives: [TranslationResult.Alternative]
        var detectedSourceLanguage: String
        var note: String
    }

    static func parse(_ data: Data) throws -> TranslationResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.malformed("response was not a JSON object")
        }
        if object["type"] as? String == "error" {
            throw TranslationError.badStatus(0, errorMessage(in: data))
        }

        switch object["stop_reason"] as? String {
        case "refusal":
            let details = object["stop_details"] as? [String: Any]
            throw TranslationError.refused(details?["explanation"] as? String)
        case "max_tokens":
            throw TranslationError.truncated
        default:
            break
        }

        let blocks = object["content"] as? [[String: Any]] ?? []
        let text = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else { throw TranslationError.malformed("no text block in response") }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let wire: Wire
        do {
            wire = try decoder.decode(Wire.self, from: Data(text.utf8))
        } catch {
            throw TranslationError.malformed("model output did not match schema")
        }

        func nonEmpty(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return TranslationResult(
            translation: wire.translation.trimmingCharacters(in: .whitespacesAndNewlines),
            transliteration: nonEmpty(wire.transliteration),
            partOfSpeech: nonEmpty(wire.partOfSpeech),
            alternatives: wire.alternatives.filter { !$0.text.isEmpty },
            detectedSource: nonEmpty(wire.detectedSourceLanguage),
            note: nonEmpty(wire.note)
        )
    }

    static func errorMessage(in data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(data: data.prefix(200), encoding: .utf8) ?? "unknown error"
    }
}
