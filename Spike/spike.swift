import Foundation
import Translation

@main
struct Spike {
    static func main() async {
        let en = Locale.Language(identifier: "en")
        let he = Locale.Language(identifier: "he")
        let avail = LanguageAvailability()
        let supported = await avail.supportedLanguages.map { $0.minimalIdentifier }.sorted()
        print("supported (\(supported.count)):", supported.joined(separator: " "))
        let status = await avail.status(from: en, to: he)
        print("en->he status:", status)
        guard status != .unsupported else { return }
        do {
            let session = TranslationSession(installedSource: en, target: he)
            if status == .supported {
                print("Language pack not installed; calling prepareTranslation()...")
                try await session.prepareTranslation()
            }
            for w in ["hello", "feasible", "The quick brown fox jumps over the lazy dog."] {
                let r = try await session.translate(w)
                print("\(w) -> \(r.targetText)")
            }
        } catch {
            print("error:", error)
        }
    }
}
