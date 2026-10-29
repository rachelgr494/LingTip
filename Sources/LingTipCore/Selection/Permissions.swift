import AppKit
import ApplicationServices

public enum Permissions {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "LingTip would like to control this computer" prompt once.
    public static func promptIfNeeded() {
        guard !isTrusted else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    public static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
