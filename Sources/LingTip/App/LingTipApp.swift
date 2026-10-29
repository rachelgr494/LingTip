import SwiftUI
import LingTipCore

@main
struct LingTipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // "…Template" suffix makes AppKit tint the silhouette for light/dark menu bars.
        MenuBarExtra("LingTip", image: "MenuBarIconTemplate") {
            MenuContent(coordinator: appDelegate.coordinator)
        }
    }
}
