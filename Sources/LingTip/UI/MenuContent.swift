import SwiftUI
import LingTipCore

struct MenuContent: View {
    @ObservedObject var coordinator: LookupCoordinator
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button("Translate Selection") {
            coordinator.translateSelection()
        }

        Divider()

        Text("\(settings.sourceIsAuto ? "Auto" : Language.name(for: settings.sourceCode)) → \(Language.name(for: settings.targetCode))")
        Text(coordinator.lastStatus)

        if !Permissions.isTrusted {
            Button("Grant Accessibility Access…") {
                Permissions.promptIfNeeded()
                Permissions.openSystemSettings()
            }
        }
        if APIKeyStore.anthropicKey == nil {
            Button("Add Claude API Key…") {
                SettingsWindowController.shared.show()
            }
        }

        Divider()

        Button("Settings…") {
            SettingsWindowController.shared.show()
        }
        .keyboardShortcut(",")

        Button("Quit LingTip") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
