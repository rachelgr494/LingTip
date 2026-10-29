import SwiftUI
import ServiceManagement

/// Hosts SettingsView in a plain window. A menu-bar-only app has no Dock presence,
/// so we activate explicitly to bring the window forward.
@MainActor
public final class SettingsWindowController {
    public static let shared = SettingsWindowController()
    private var window: NSWindow?

    public func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "LingTip Settings"
            w.styleMask = [.titled, .closable, .resizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// View state lives here rather than in @State (see Package.swift for why).
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var apiKeyDraft = ""
    @Published var keyStatus = ""
    @Published var testStatus = ""
    @Published var testing = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var accessibilityGranted = Permissions.isTrusted

    func saveKey() {
        do {
            try APIKeyStore.save(apiKeyDraft)
            apiKeyDraft = ""
            keyStatus = "Saved."
        } catch {
            keyStatus = "Could not save: \(error.localizedDescription)"
        }
    }

    func removeKey() {
        APIKeyStore.clear()
        keyStatus = "Key removed."
    }

    func testConnection(settings: AppSettings) {
        testing = true
        testStatus = ""
        Task {
            defer { testing = false }
            do {
                let request = TranslationRequest(text: "hello", source: "en", target: settings.targetCode)
                let result = try await ClaudeTranslator(settings: settings).translate(request)
                testStatus = "OK — hello → \(result.translation)"
            } catch {
                testStatus = error.localizedDescription
            }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("LingTip: launch at login change failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func recheckPermissions() {
        accessibilityGranted = Permissions.isTrusted
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var hotkeys = HotkeyManager.shared
    @StateObject private var vm = SettingsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            form
        }
        .frame(width: 500, height: 760)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            vm.recheckPermissions()
        }
    }

    /// Logo banner (Logo.png is copied into Contents/Resources by Scripts/build_app.sh).
    private var header: some View {
        HStack(spacing: 14) {
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("LingTip")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.cream)
                Text("Select text anywhere, press \(hotkeys.combo.displayString), read the translation.")
                    .font(.callout)
                    .foregroundStyle(Brand.cream.opacity(0.65))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Brand.navy)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Brand.gradient).frame(height: 2)
        }
    }

    private var form: some View {
        Form {
            Section("Claude API") {
                if APIKeyStore.usingEnvironment {
                    Label("Using ANTHROPIC_API_KEY from the environment.", systemImage: "checkmark.circle")
                } else {
                    LabeledContent("API key") {
                        SecureField("Paste your key here (sk-ant-…)", text: $vm.apiKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { vm.saveKey() }
                    }
                    Text("Get a key at console.anthropic.com → API Keys. It is stored only in your login Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Save to Keychain") { vm.saveKey() }
                            .disabled(vm.apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        if APIKeyStore.hasKeychainKey {
                            Button("Remove") { vm.removeKey() }
                        }
                        Spacer()
                        Text(vm.keyStatus.isEmpty ? (APIKeyStore.hasKeychainKey ? "A key is saved." : "No key saved.") : vm.keyStatus)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                TextField("Model", text: $settings.modelID)
                Text("Default is claude-opus-5-5. For faster, cheaper lookups try claude-haiku-5-5.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(vm.testing ? "Testing…" : "Test connection") { vm.testConnection(settings: settings) }
                        .disabled(vm.testing)
                    Text(vm.testStatus).font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Languages") {
                Picker("From", selection: $settings.sourceCode) {
                    Text("Auto-detect").tag(AppSettings.autoSource)
                    Divider()
                    ForEach(Language.codes, id: \.self) { Text(Language.name(for: $0)).tag($0) }
                }
                Picker("To", selection: $settings.targetCode) {
                    ForEach(Language.codes, id: \.self) { Text(Language.name(for: $0)).tag($0) }
                }
                Text("If the selected text is already in the “To” language, LingTip translates it back into the “From” language (or English when auto-detecting).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Shortcut") {
                HStack {
                    Text("Translate selection")
                    Spacer()
                    ShortcutRecorder(manager: hotkeys)
                    Button("Reset") { hotkeys.update(.default) }
                        .disabled(hotkeys.combo == .default)
                }
            }

            Section("Behavior") {
                HStack {
                    Slider(value: $settings.autoHideSeconds, in: 3...30, step: 1)
                    Text("\(Int(settings.autoHideSeconds)) s").monospacedDigit().frame(width: 36)
                }
                Text("How long the tooltip stays before fading (it waits while the pointer is over it).")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Tooltip size: \(Int(settings.tooltipWidth)) × \(Int(settings.tooltipMaxHeight)) pt")
                    Spacer()
                    Button("Reset") { settings.resetTooltipSize() }
                        .disabled(settings.tooltipSizeIsDefault)
                }
                Text("Drag the grip in the tooltip's bottom-right corner to change its width and the height at which it starts scrolling.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: Binding(
                    get: { vm.launchAtLogin },
                    set: { vm.setLaunchAtLogin($0) }
                ))
            }

            Section("Permissions") {
                HStack {
                    Label(vm.accessibilityGranted ? "Accessibility: granted" : "Accessibility: not granted",
                          systemImage: vm.accessibilityGranted ? "checkmark.circle" : "xmark.circle")
                    Spacer()
                    if !vm.accessibilityGranted {
                        Button("Open System Settings") { Permissions.openSystemSettings() }
                    }
                    Button("Re-check") { vm.recheckPermissions() }
                }
                Text("Needed to read the selected text and to send ⌘C to apps that don't expose their selection.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .tint(Brand.orange)
    }
}
