import AppKit
import LingTipCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = LookupCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
        // A menu-bar app has no window or Dock icon, so a first launch looks like nothing
        // happened. Open Settings until the app is usable (API key saved, Accessibility granted).
        if APIKeyStore.anthropicKey == nil || !Permissions.isTrusted {
            SettingsWindowController.shared.show()
        }
    }

    /// The user double-clicked the app (Finder, Launchpad, Spotlight) while it was already
    /// running. Without this nothing visible happens.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }
}
