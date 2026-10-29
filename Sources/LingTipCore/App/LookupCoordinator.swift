import AppKit
import Combine

/// Orchestrates one lookup: hotkey → read selection → translate → tooltip.
@MainActor
public final class LookupCoordinator: ObservableObject {
    @Published public private(set) var lastStatus: String = "Ready"

    let settings: AppSettings
    private let tooltip = TooltipController()
    private let cache = TranslationCache(capacity: 200)
    private let translator: Translator
    private var inflight: Task<Void, Never>?
    private var openedSettingsForPermission = false

    /// Selections longer than this are cut before being sent; a tooltip is not a document translator.
    nonisolated static let maxCharacters = 1500

    init(settings: AppSettings = .shared, translator: Translator? = nil) {
        self.settings = settings
        self.translator = translator ?? ClaudeTranslator(settings: settings)
    }

    /// Production wiring: shared settings, Claude backend.
    public convenience init() {
        self.init(settings: .shared, translator: nil)
    }

    public func start() {
        HotkeyManager.shared.install { [weak self] in
            self?.translateSelection()
        }
        Permissions.promptIfNeeded()
    }

    /// Entry point for both the global shortcut and the menu item.
    public func translateSelection() {
        inflight?.cancel()
        inflight = Task { await performLookup() }
    }

    private func performLookup() async {
        let anchor = NSEvent.mouseLocation

        guard Permissions.isTrusted else {
            tooltip.show(
                .error("LingTip needs Accessibility access to read the selected text.",
                       hint: "System Settings → Privacy & Security → Accessibility → enable LingTip. If it is already on, remove it with “−” and add it again."),
                at: anchor
            )
            // Open System Settings once per launch, not on every press.
            if !openedSettingsForPermission {
                openedSettingsForPermission = true
                Permissions.openSystemSettings()
            }
            return
        }

        guard let raw = await SelectionReader.read() else {
            let hint = SelectionReader.isSecureInputActive
                ? "A password field is active; macOS blocks reading from it."
                : "Select a word or phrase, then press the shortcut."
            tooltip.show(.error("No text selected.", hint: hint), at: anchor)
            return
        }

        let text = Self.normalize(raw)
        guard !text.isEmpty else {
            tooltip.show(.error("No text selected."), at: anchor)
            return
        }

        let pair = settings.resolvePair(for: text)
        tooltip.show(.loading(text, pair), at: anchor)

        if let cached = cache[text, pair] {
            tooltip.show(.result(text, cached, pair))
            return
        }

        do {
            let request = TranslationRequest(text: text, source: pair.source, target: pair.target)
            let result = try await translator.translate(request)
            guard !Task.isCancelled else { return }
            cache[text, pair] = result
            lastStatus = "Translated “\(text.prefix(30))”"
            tooltip.show(.result(text, result, pair))
        } catch is CancellationError {
            // A newer lookup superseded this one.
        } catch {
            guard !Task.isCancelled else { return }
            lastStatus = "Error: \(error.localizedDescription)"
            tooltip.show(.error(error.localizedDescription, hint: (error as? TranslationError)?.recoverySuggestion))
        }
    }

    /// Trim, collapse runs of whitespace, and cap the length.
    nonisolated static func normalize(_ raw: String) -> String {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count > maxCharacters {
            return String(collapsed.prefix(maxCharacters)) + "…"
        }
        return collapsed
    }
}
