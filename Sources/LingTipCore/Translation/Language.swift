import Foundation
import NaturalLanguage

public enum Language {
    /// Languages offered in the pickers. Any BCP-47 code works with the Claude backend;
    /// this is just a curated list for the UI.
    static let codes: [String] = [
        "en", "he", "ar", "fr", "de", "es", "it", "pt", "ru", "uk", "pl", "nl",
        "tr", "fa", "hi", "ja", "ko", "zh", "yi", "el", "sv", "da", "nb", "fi",
        "cs", "hu", "ro", "th", "vi", "id",
    ]

    static let rtlCodes: Set<String> = ["he", "ar", "fa", "ur", "yi", "iw"]

    static func isRTL(_ code: String) -> Bool {
        rtlCodes.contains(base(code))
    }

    public static func name(for code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }

    /// "he-IL" and "he" are the same language; "iw" is the legacy code for Hebrew.
    static func sameLanguage(_ a: String, _ b: String) -> Bool {
        canonical(a) == canonical(b)
    }

    private static func base(_ code: String) -> String {
        code.split(separator: "-").first.map(String.init)?.lowercased() ?? code.lowercased()
    }

    private static func canonical(_ code: String) -> String {
        let b = base(code)
        return b == "iw" ? "he" : b
    }
}

enum LanguageDetector {
    /// Returns a BCP-47 base code when reasonably confident, else nil.
    /// Script checks come first because NLLanguageRecognizer is unreliable on single words.
    static func detect(_ text: String) -> String? {
        if let byScript = detectByScript(text) { return byScript }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= 0.6 else { return nil }
        return language.rawValue
    }

    private static func detectByScript(_ text: String) -> String? {
        var hebrew = 0, arabic = 0, letters = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            switch scalar.value {
            case 0x0590...0x05FF, 0xFB1D...0xFB4F: hebrew += 1
            case 0x0600...0x06FF, 0x0750...0x077F, 0xFB50...0xFDFF, 0xFE70...0xFEFF: arabic += 1
            default: break
            }
        }
        guard letters > 0 else { return nil }
        if hebrew * 2 > letters { return "he" }
        if arabic * 2 > letters { return "ar" }
        return nil
    }
}
