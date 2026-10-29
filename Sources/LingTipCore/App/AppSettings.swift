import Foundation
import Combine

/// User preferences, persisted in UserDefaults. Default pair is English → Hebrew.
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings(defaults: .standard)

    enum Keys {
        static let source = "sourceLanguage"
        static let target = "targetLanguage"
        static let autoHide = "tooltipAutoHideSeconds"
        static let model = "claudeModel"
        static let tooltipWidth = "tooltipWidth"
        static let tooltipHeight = "tooltipMaxHeight"
    }

    static let defaultTooltipWidth: Double = 360
    static let defaultTooltipHeight: Double = 480
    static let tooltipWidthRange: ClosedRange<Double> = 240...900
    static let tooltipHeightRange: ClosedRange<Double> = 120...1200

    static let autoSource = "auto"
    static let defaultModel = "claude-opus-5-5"

    private let defaults: UserDefaults

    /// BCP-47 code, or `AppSettings.autoSource` to detect.
    @Published public var sourceCode: String { didSet { defaults.set(sourceCode, forKey: Keys.source) } }
    @Published public var targetCode: String { didSet { defaults.set(targetCode, forKey: Keys.target) } }
    @Published var autoHideSeconds: Double { didSet { defaults.set(autoHideSeconds, forKey: Keys.autoHide) } }
    @Published var modelID: String { didSet { defaults.set(modelID, forKey: Keys.model) } }
    /// Tooltip card size, set by dragging its corner. Height is a cap: shorter results stay compact.
    @Published var tooltipWidth: Double { didSet { defaults.set(tooltipWidth, forKey: Keys.tooltipWidth) } }
    @Published var tooltipMaxHeight: Double { didSet { defaults.set(tooltipMaxHeight, forKey: Keys.tooltipHeight) } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        sourceCode = defaults.string(forKey: Keys.source) ?? Self.autoSource
        targetCode = defaults.string(forKey: Keys.target) ?? "he"
        autoHideSeconds = defaults.object(forKey: Keys.autoHide) as? Double ?? 10
        modelID = defaults.string(forKey: Keys.model) ?? Self.defaultModel
        tooltipWidth = defaults.object(forKey: Keys.tooltipWidth) as? Double ?? Self.defaultTooltipWidth
        tooltipMaxHeight = defaults.object(forKey: Keys.tooltipHeight) as? Double ?? Self.defaultTooltipHeight
    }

    var tooltipSizeIsDefault: Bool {
        tooltipWidth == Self.defaultTooltipWidth && tooltipMaxHeight == Self.defaultTooltipHeight
    }

    func resetTooltipSize() {
        tooltipWidth = Self.defaultTooltipWidth
        tooltipMaxHeight = Self.defaultTooltipHeight
    }

    public var sourceIsAuto: Bool { sourceCode == Self.autoSource }

    /// Decide the pair for one lookup. If the selected text is already in the
    /// target language, translate back the other way (he → en for the default pair).
    func resolvePair(for text: String) -> LanguagePair {
        let detected = LanguageDetector.detect(text)
        let explicitSource: String? = sourceIsAuto ? nil : sourceCode

        if let detected, Language.sameLanguage(detected, targetCode) {
            let reverseTarget = explicitSource ?? "en"
            if !Language.sameLanguage(reverseTarget, detected) {
                return LanguagePair(source: detected, target: reverseTarget)
            }
        }
        return LanguagePair(source: explicitSource, target: targetCode)
    }
}

struct LanguagePair: Hashable {
    /// nil means "auto-detect".
    let source: String?
    let target: String

    var sourceLabel: String { source.map(Language.name) ?? "Auto" }
    var targetLabel: String { Language.name(for: target) }
    var targetIsRTL: Bool { Language.isRTL(target) }
}
