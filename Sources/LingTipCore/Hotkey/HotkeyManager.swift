import AppKit
import Carbon
import Combine

/// A key + Carbon modifier mask, persisted as JSON. Default: ⌥⌘T.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = KeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | optionKey))

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + KeyCombo.keyName(for: keyCode)
    }

    private static let specialNames: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Human-readable key, using the current ASCII-capable layout so a Hebrew layout still shows "T".
    static func keyName(for keyCode: UInt32) -> String {
        if let special = specialNames[Int(keyCode)] { return special }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { buffer -> String in
            guard let base = buffer.baseAddress else { return "Key \(keyCode)" }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                        UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysMask),
                                        &deadKeyState, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return "Key \(keyCode)" }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }
}

/// Registers the global shortcut with Carbon (no Accessibility needed for this part)
/// and fires on key release.
@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()
    private static let defaultsKey = "hotkeyCombo"
    private static let signature: OSType = 0x4C54_4950 // "LTIP"

    @Published private(set) var combo: KeyCombo
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?
    private var suspended = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            combo = saved
        } else {
            combo = .default
        }
    }

    func install(_ action: @escaping () -> Void) {
        self.action = action
        installHandler()
        register()
    }

    func update(_ newCombo: KeyCombo) {
        combo = newCombo
        if let data = try? JSONEncoder().encode(newCombo) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        unregister()
        if !suspended { register() }
    }

    /// While the recorder is capturing keys, the registered hotkey must not swallow them.
    func setSuspended(_ on: Bool) {
        suspended = on
        unregister()
        if !on { register() }
    }

    private func fire() {
        action?()
    }

    private func register() {
        guard hotKeyRef == nil else { return }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr { hotKeyRef = ref } else { NSLog("LingTip: RegisterEventHotKey failed (\(status))") }
    }

    private func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        hotKeyRef = nil
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        // C callback: cannot capture context, so it reaches the singleton directly.
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { HotkeyManager.shared.fire() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}

// MARK: - Recorder

/// Click, press a combination (with ⌘, ⌥ or ⌃), done. Esc cancels.
final class RecorderView: NSView {
    var combo: KeyCombo { didSet { refresh() } }
    var onChange: ((KeyCombo) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private(set) var isRecording = false {
        didSet { refresh(); onRecordingChange?(isRecording) }
    }

    init(combo: KeyCombo) {
        self.combo = combo
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 24) }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            window?.makeFirstResponder(self)
            isRecording = true
        }
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        handle(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        handle(event)
        return true
    }

    private func handle(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape { stopRecording(); return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else {
            label.stringValue = "Include ⌘, ⌥ or ⌃"
            return
        }
        let newCombo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: KeyCombo.carbonModifiers(from: flags))
        combo = newCombo
        onChange?(newCombo)
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        label.stringValue = isRecording ? "Type shortcut…  (esc cancels)" : combo.displayString
        label.textColor = isRecording ? .secondaryLabelColor : .labelColor
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }
}

import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var manager: HotkeyManager

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView(combo: manager.combo)
        view.onChange = { manager.update($0) }
        view.onRecordingChange = { manager.setSuspended($0) }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        if !view.isRecording, view.combo != manager.combo { view.combo = manager.combo }
    }
}
