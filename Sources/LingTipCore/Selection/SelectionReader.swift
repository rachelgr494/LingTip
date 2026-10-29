import AppKit
import ApplicationServices
import Carbon

/// Reads the text currently selected in the frontmost app.
/// Strategy: Accessibility API first (clean, no clipboard), then a synthesized ⌘C
/// with clipboard save/restore for apps that don't expose selection via AX
/// (Chrome, Electron, PDF viewers, terminals).
enum SelectionReader {
    static var isSecureInputActive: Bool { IsSecureEventInputEnabled() }

    static func read() async -> String? {
        if let text = readViaAccessibility(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        // Secure input (password fields) blocks synthesized keystrokes anyway.
        guard !isSecureInputActive else { return nil }
        return await readViaClipboard()
    }

    // MARK: Accessibility

    static func readViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let focused = unsafeBitCast(focusedRef, to: AXUIElement.self)

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &valueRef) == .success,
              let text = valueRef as? String else { return nil }
        return text
    }

    // MARK: Clipboard fallback

    static func readViaClipboard(timeout: TimeInterval = 0.4) async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount

        await KeySynthesizer.waitForModifiersReleased()
        KeySynthesizer.postCommandC()

        let deadline = Date().addingTimeInterval(timeout)
        while pasteboard.changeCount == before, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(15))
        }

        defer { snapshot.restore(to: pasteboard) }
        guard pasteboard.changeCount != before else { return nil }
        return pasteboard.string(forType: .string)
    }
}

/// A copy of every item/type on a pasteboard, so we can put it back after a synthetic ⌘C.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var byType: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { byType[type] = data }
            }
            return byType
        }
    }

    var isEmpty: Bool { items.allSatisfy(\.isEmpty) }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !isEmpty else { return }
        let restored = items.map { byType -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in byType { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}

enum KeySynthesizer {
    /// If the user is still holding ⌥⌘ from the hotkey, the target app may see ⌥⌘C
    /// instead of ⌘C. Wait briefly for the physical modifiers to be released.
    static func waitForModifiersReleased(timeout: TimeInterval = 0.5) async {
        let deadline = Date().addingTimeInterval(timeout)
        let watched: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        while !NSEvent.modifierFlags.intersection(watched).isEmpty, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    static func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_C)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
