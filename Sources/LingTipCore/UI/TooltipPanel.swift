import AppKit
import Combine
import SwiftUI

enum TooltipState {
    /// Nothing was selected: let the user type the text instead.
    case input
    case loading(String, LanguagePair)
    case result(String, TranslationResult, LanguagePair)
    case error(String, hint: String? = nil)
}

@MainActor
final class TooltipModel: ObservableObject {
    @Published var state: TooltipState = .error("")
    /// Card width. Text wraps at this width, so it must be fixed for SwiftUI to measure height correctly.
    @Published var width: CGFloat = 360
    /// Tallest the card may grow before its content scrolls.
    @Published var maxHeight: CGFloat = 480
    /// Text typed in the `.input` state.
    @Published var draft = ""
    /// Called when the user submits the typed text (Return or the Translate button).
    var onSubmit: ((String) -> Void)?
    /// Upper bound for maxHeight while dragging (the anchor screen's usable height).
    var screenLimit: CGFloat = 1200
    /// Size at the start of a corner drag (no @State: see Package.swift).
    var dragStart: CGSize?
    /// Mouse position in screen coordinates at the start of a corner drag.
    var dragMouse: NSPoint?
    /// Called when a corner drag ends, with the final width and height cap.
    var onResizeEnd: ((CGFloat, CGFloat) -> Void)?
}

/// Borderless, non-activating floating panel. Takes keyboard focus only while showing the
/// text input; even then it does not activate LingTip, so the user's app stays frontmost.
final class TooltipPanel: NSPanel {
    var acceptsKeyboard = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
}

/// Shows/positions/dismisses the tooltip.
@MainActor
final class TooltipController {
    private let panel = TooltipPanel()
    private let model = TooltipModel()
    private let hosting: NSHostingController<TooltipView>
    private var anchor = NSPoint.zero
    private var monitors: [Any] = []
    private var hideTask: Task<Void, Never>?
    private var resizeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
        hosting = NSHostingController(rootView: TooltipView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        model.onResizeEnd = { [settings] width, height in
            settings.tooltipWidth = Double(width)
            settings.tooltipMaxHeight = Double(height)
        }
        // A controller (not a bare NSHostingView) lets the window follow the SwiftUI content size.
        panel.contentViewController = hosting
        // Size the window from the content on every model change. Relying on SwiftUI to resize
        // the panel left it at the loading size, which clipped the translation.
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.fitPanelToContent() }
            .store(in: &cancellables)
        // Keep the top-left anchored when the window size changes.
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    /// Show a state. Pass `at:` for a fresh lookup; omit it to update in place.
    func show(_ state: TooltipState, at point: NSPoint? = nil) {
        if let point {
            anchor = point
            let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                model.screenLimit = visible.height - 40
            }
            model.width = CGFloat(settings.tooltipWidth)
            model.maxHeight = min(CGFloat(settings.tooltipMaxHeight), model.screenLimit)
        }
        model.state = state
        if !panel.isVisible { installMonitors() }
        reposition()
        panel.orderFrontRegardless()
        if case .input = state {
            panel.acceptsKeyboard = true
            panel.makeKey()
        }
        scheduleAutoHide(for: state)
    }

    /// Show an empty text field for the user to type into.
    func showInput(at point: NSPoint, onSubmit: @escaping (String) -> Void) {
        model.draft = ""
        model.onSubmit = onSubmit
        show(.input, at: point)
    }

    /// The typed text while the input is on screen; nil otherwise.
    var inputDraft: String? {
        guard panel.isVisible, case .input = model.state else { return nil }
        return model.draft
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        removeMonitors()
        panel.orderOut(nil)
        panel.acceptsKeyboard = false
    }

    /// Current panel size, read by the checks harness.
    var panelSize: NSSize { panel.frame.size }

    private func fitPanelToContent() {
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.preferredContentSize
        guard size.width > 0, size.height > 0, size != panel.frame.size else { return }
        panel.setContentSize(size)
        reposition()
    }

    // MARK: Placement

    private func reposition() {
        let size = panel.frame.size
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        var origin = NSPoint(x: anchor.x + 14, y: anchor.y - 18 - size.height) // below-right of cursor
        if origin.y < visible.minY + 8 { origin.y = anchor.y + 18 }               // flip above if no room
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }

    // MARK: Dismissal

    private func scheduleAutoHide(for state: TooltipState) {
        hideTask?.cancel()
        let seconds: Double
        switch state {
        case .loading, .input: return // keep while working or typing
        case .result: seconds = settings.autoHideSeconds
        case .error: seconds = 5
        }
        hideTask = Task { [weak self] in
            var remaining = seconds
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(min(remaining, 1)))
                guard !Task.isCancelled, let self else { return }
                // Don't vanish while the pointer is over the tooltip (user may be reading/copying).
                if !self.panel.frame.contains(NSEvent.mouseLocation) { remaining -= 1 }
            }
            self?.hide()
        }
    }

    private func installMonitors() {
        removeMonitors()
        let dismissing: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        // Events in *other* apps: any click, scroll, or keystroke dismisses.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: dismissing, handler: { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }) {
            monitors.append(global)
        }
        // Events in our own app (e.g. the Settings window): Esc dismisses; clicks inside the panel do not.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.hide() }; return nil }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}
