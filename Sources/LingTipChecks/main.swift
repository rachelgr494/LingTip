// Unit checks for LingTipCore. Run with `swift run LingTipChecks` (debug build, so
// @testable import works). Exits non-zero on any failure.
import AppKit
import Foundation
import SwiftUI
@testable import LingTipCore

// MARK: - Tiny harness

var failures = 0
var passes = 0

func check(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) {
    if condition {
        passes += 1
    } else {
        failures += 1
        print("  ✘ \(message)  (\(file):\(line))")
    }
}

func check<T: Equatable>(_ actual: T, equals expected: T, _ message: String, file: String = #fileID, line: Int = #line) {
    check(actual == expected, "\(message): expected \(expected), got \(actual)", file: file, line: line)
}

func checkThrows<E: Error>(_ type: E.Type, _ message: String, file: String = #fileID, line: Int = #line,
                           _ body: () throws -> Void) -> E? {
    do {
        try body()
        failures += 1
        print("  ✘ \(message): no error thrown  (\(file):\(line))")
        return nil
    } catch let error as E {
        passes += 1
        return error
    } catch {
        failures += 1
        print("  ✘ \(message): wrong error type \(error)  (\(file):\(line))")
        return nil
    }
}

func suite(_ name: String, _ body: () throws -> Void) {
    print("▸ \(name)")
    do { try body() } catch { failures += 1; print("  ✘ threw \(error)") }
}

func freshSettings() -> AppSettings {
    let suite = "LingTipChecks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return AppSettings(defaults: defaults)
}

// MARK: - Settings & language

suite("Settings defaults and pair resolution") {
    let settings = freshSettings()
    check(settings.sourceCode, equals: AppSettings.autoSource, "default source is auto")
    check(settings.targetCode, equals: "he", "default target is Hebrew")
    check(settings.modelID, equals: "claude-opus-5-5", "default model")
    check(settings.tooltipWidth, equals: 360, "default tooltip width")
    check(settings.tooltipSizeIsDefault, "tooltip size starts at default")
    settings.tooltipWidth = 500
    check(!settings.tooltipSizeIsDefault, "custom tooltip size detected")
    settings.resetTooltipSize()
    check(settings.tooltipSizeIsDefault, "reset restores default size")

    let en = settings.resolvePair(for: "feasible")
    check(en.source == nil, "English word: source auto")
    check(en.target, equals: "he", "English word: target he")
    check(en.targetIsRTL, "Hebrew target is RTL")

    let he = settings.resolvePair(for: "שלום עולם")
    check(he.source, equals: "he", "Hebrew selection: detected source")
    check(he.target, equals: "en", "Hebrew selection reverses to English")
    check(!he.targetIsRTL, "English target is LTR")

    settings.sourceCode = "fr"
    let fr = settings.resolvePair(for: "בוקר טוב")
    check(fr.target, equals: "fr", "reverse uses explicit source")

    let suiteName = "LingTipChecks.persist.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    AppSettings(defaults: defaults).targetCode = "ar"
    check(AppSettings(defaults: defaults).targetCode, equals: "ar", "settings persist")
}

suite("Language helpers") {
    check(Language.isRTL("he"), "he is RTL")
    check(Language.isRTL("he-IL"), "he-IL is RTL")
    check(Language.isRTL("ar"), "ar is RTL")
    check(!Language.isRTL("en"), "en is LTR")
    check(Language.sameLanguage("iw", "he"), "legacy iw == he")
    check(LanguageDetector.detect("שלום"), equals: "he", "Hebrew script detection")
    check(LanguageDetector.detect("مرحبا"), equals: "ar", "Arabic script detection")
    check(LanguageDetector.detect("The quick brown fox jumps over the lazy dog") != "he", "English is not Hebrew")
}

suite("Normalize") {
    check(LookupCoordinator.normalize("  hello\n\n  world\t!"), equals: "hello world !", "collapses whitespace")
    let long = String(repeating: "a", count: LookupCoordinator.maxCharacters + 50)
    let normalized = LookupCoordinator.normalize(long)
    check(normalized.count, equals: LookupCoordinator.maxCharacters + 1, "caps length")
    check(normalized.hasSuffix("…"), "adds ellipsis when capped")
}

suite("KeyCombo") {
    check(KeyCombo.default.displayString, equals: "⌥⌘T", "default shortcut renders")
    let combo = KeyCombo(keyCode: 49, modifiers: KeyCombo.carbonModifiers(from: [.control, .shift]))
    check(combo.displayString, equals: "⌃⇧Space", "modifier order and special key name")
    let data = try JSONEncoder().encode(combo)
    check(try JSONDecoder().decode(KeyCombo.self, from: data), equals: combo, "round-trips through JSON")
}

// MARK: - Claude response parsing

func apiResponse(stopReason: String, text: String, extra: String = "") -> Data {
    let escaped = text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return Data("""
    {"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5",
     "content":[{"type":"text","text":"\(escaped)"}],
     "stop_reason":"\(stopReason)"\(extra),"usage":{"input_tokens":10,"output_tokens":20}}
    """.utf8)
}

suite("ClaudeTranslator parsing") {
    let payload = """
    {"translation":"שָׁלוֹם","transliteration":"shalom","part_of_speech":"noun",
     "alternatives":[{"text":"הֵי","sense":"informal greeting"}],
     "detected_source_language":"en","note":""}
    """
    let result = try ClaudeTranslator.parse(apiResponse(stopReason: "end_turn", text: payload))
    check(result.translation, equals: "שָׁלוֹם", "translation")
    check(result.transliteration, equals: "shalom", "transliteration")
    check(result.partOfSpeech, equals: "noun", "part of speech")
    check(result.alternatives.count, equals: 1, "alternatives")
    check(result.detectedSource, equals: "en", "detected source")
    check(result.note == nil, "empty note becomes nil")

    let refusalExtra = #","stop_details":{"type":"refusal","category":"general_harms","explanation":"nope"}"#
    let refusal = checkThrows(TranslationError.self, "refusal throws") {
        _ = try ClaudeTranslator.parse(apiResponse(stopReason: "refusal", text: "", extra: refusalExtra))
    }
    if case .refused(let why)? = refusal { check(why, equals: "nope", "refusal explanation") } else { check(false, "refusal case") }

    let truncated = checkThrows(TranslationError.self, "max_tokens throws") {
        _ = try ClaudeTranslator.parse(apiResponse(stopReason: "max_tokens", text: "{"))
    }
    if case .truncated? = truncated {} else { check(false, "truncated case") }

    let errorData = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
    _ = checkThrows(TranslationError.self, "error object throws") { _ = try ClaudeTranslator.parse(errorData) }
    check(ClaudeTranslator.errorMessage(in: errorData), equals: "invalid x-api-key", "error message extraction")
}

suite("ClaudeTranslator request body") {
    let request = TranslationRequest(text: "feasible", source: nil, target: "he")
    let body = ClaudeTranslator.body(for: request, model: "claude-opus-5-5")
    check(body["model"] as? String, equals: "claude-opus-5-5", "model")
    check(body["fallbacks"] as? String, equals: "default", "fallbacks")
    let output = body["output_config"] as? [String: Any]
    check(output?["effort"] as? String, equals: "low", "effort")
    check((output?["format"] as? [String: Any])?["type"] as? String, equals: "json_schema", "structured output")
    check(JSONSerialization.isValidJSONObject(body), "body serializes")
    let content = (body["messages"] as? [[String: Any]])?.first?["content"] as? String
    check(content?.contains("Source language: auto") == true, "auto source in prompt")
}

// MARK: - Cache

suite("TranslationCache") {
    let pair = LanguagePair(source: nil, target: "he")
    let cache = TranslationCache(capacity: 2)
    cache["a", pair] = TranslationResult(translation: "1")
    check(cache["a", pair]?.translation, equals: "1", "store and fetch")
    check(cache["a", LanguagePair(source: nil, target: "fr")] == nil, "keyed by pair")
    cache["b", pair] = TranslationResult(translation: "2")
    _ = cache["a", pair]                                 // a is now most recent
    cache["c", pair] = TranslationResult(translation: "3") // evicts b
    check(cache["a", pair] != nil, "recently used survives")
    check(cache["b", pair] == nil, "least recently used evicted")
    check(cache.count, equals: 2, "capacity respected")
}

// MARK: - Pasteboard snapshot

suite("PasteboardSnapshot") {
    let customType = NSPasteboard.PasteboardType("com.lingtip.test")
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("LingTipChecks.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }

    pasteboard.clearContents()
    let item = NSPasteboardItem()
    item.setString("original text", forType: .string)
    item.setData(Data([1, 2, 3]), forType: customType)
    pasteboard.writeObjects([item])

    let snapshot = PasteboardSnapshot(pasteboard)
    check(!snapshot.isEmpty, "snapshot captured items")

    pasteboard.clearContents()
    pasteboard.setString("copied selection", forType: .string)
    check(pasteboard.string(forType: .string), equals: "copied selection", "simulated ⌘C replaced contents")

    snapshot.restore(to: pasteboard)
    check(pasteboard.string(forType: .string), equals: "original text", "string restored")
    check(pasteboard.data(forType: customType), equals: Data([1, 2, 3]), "custom type restored")

    pasteboard.clearContents()
    let empty = PasteboardSnapshot(pasteboard)
    check(empty.isEmpty, "empty snapshot")
    pasteboard.setString("junk", forType: .string)
    empty.restore(to: pasteboard)
    check(pasteboard.string(forType: .string) == nil, "empty snapshot restores to empty")
}

suite("Tooltip panel fits its content") {
    MainActor.assumeIsolated {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let defaults = UserDefaults(suiteName: "lingtip.checks.tooltip")!
        defaults.removePersistentDomain(forName: "lingtip.checks.tooltip")
        let controller = TooltipController(settings: AppSettings(defaults: defaults))
        let pair = LanguagePair(source: nil, target: "he")
        let paragraph = String(repeating: "A rather long sentence that keeps going and going. ", count: 30)
        controller.show(.result(paragraph, TranslationResult(translation: paragraph), pair), at: NSPoint(x: 300, y: 700))
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(controller.panelSize.width, equals: 360, "panel adopts the default card width")
        check(controller.panelSize.height > 200, "panel grows to show the translation: \(controller.panelSize.height)")
        check(controller.panelSize.height <= 480.5, "panel stays within the default height cap: \(controller.panelSize.height)")
        controller.hide()
    }
}

// MARK: - Tooltip sizing

suite("Tooltip sizing") {
    MainActor.assumeIsolated {
        // SwiftUI hosting only lays out with a live NSApplication. The controller's
        // preferredContentSize is the ideal size the panel adopts (sizingOptions = .preferredContentSize).
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = TooltipModel()
        let controller = NSHostingController(rootView: TooltipView(model: model))
        controller.sizingOptions = [.preferredContentSize]
        let pair = LanguagePair(source: nil, target: "he")
        @MainActor func measure(_ state: TooltipState) -> NSSize {
            model.state = state
            RunLoop.main.run(until: Date().addingTimeInterval(0.05)) // let the @Published change propagate
            return controller.preferredContentSize
        }

        model.maxHeight = 400
        model.width = 300
        let short = measure(.result("hello", TranslationResult(translation: "שלום"), pair))
        check(short.width, equals: 300, "card takes the model width")
        check(short.height > 60 && short.height < 200, "single word card is compact: \(short.height)")

        let paragraph = String(repeating: "A rather long sentence that keeps going and going. ", count: 30)
        model.width = 440
        let long = measure(.result(paragraph, TranslationResult(translation: paragraph), pair))
        check(long.width, equals: 440, "resized width is honored")
        check(long.height <= 400.5, "long result is capped at maxHeight: \(long.height)")
        check(long.height > 300, "long result grows to the cap (scrolls) rather than staying one line: \(long.height)")

        let few = String(repeating: "word ", count: 12)
        let medium = measure(.result(few, TranslationResult(translation: few), pair))
        check(medium.height > short.height && medium.height < 400, "medium text sizes to content: \(medium.height)")

        model.width = 900
        let wide = measure(.result(few, TranslationResult(translation: few), pair))
        check(wide.height < medium.height, "wider card wraps less, so it is shorter: \(wide.height) vs \(medium.height)")
    }
}

// MARK: - Result

print("\n\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)

