import AppKit
import SwiftUI

/// Dark navy card with the logo's gold→pink gradient as accent. Always dark,
/// independent of the system appearance, so it reads like the logo everywhere.
struct TooltipView: View {
    @ObservedObject var model: TooltipModel

    private let corner: CGFloat = 14

    var body: some View {
        // A fixed width makes SwiftUI measure wrapped text at the real width; without it the
        // hosting view sizes the window for a single line and long results get clipped.
        let width = model.width
        ScrollView(.vertical) {
            content
                .padding(14)
                .frame(width: width, alignment: .leading)
        }
        .scrollIndicators(.visible)
        .frame(width: width)
        .frame(maxHeight: model.maxHeight)   // taller content scrolls instead of being cut off
        .background(
            ZStack {
                VisualEffectBackground()
                Brand.navy.opacity(0.88)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Brand.gradient, lineWidth: 1.5)
        )
        .overlay(alignment: .bottomTrailing) {
            ResizeGrip(model: model).padding(3)
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.state {
            case .input:
                inputForm

            case .loading(let text, let pair):
                header(text, pair)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Brand.orange)
                    Text("Translating…").foregroundStyle(Brand.cream.opacity(0.7))
                }

            case .result(let text, let result, let pair):
                header(text, pair)
                translation(result, pair)
                if !result.alternatives.isEmpty {
                    alternatives(result.alternatives, rtl: pair.targetIsRTL)
                }
                if let note = result.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Brand.cream.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

            case .error(let message, let hint):
                Label {
                    Text(message).foregroundStyle(Brand.cream)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.pink)
                }
                .fixedSize(horizontal: false, vertical: true)
                if let hint {
                    Text(hint).font(.caption).foregroundStyle(Brand.cream.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Pieces

    private var inputForm: some View {
        let isEmpty = model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let submit = { if !isEmpty { model.onSubmit?(model.draft) } }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Type text to translate")
                .font(.callout)
                .foregroundStyle(Brand.cream.opacity(0.7))
            InputField(text: $model.draft, placeholder: "Word or phrase", onSubmit: submit)
                .frame(maxWidth: .infinity)
            HStack {
                Spacer()
                Button(action: submit) {
                    Text("Translate")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Brand.navy)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Brand.gradient))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isEmpty)
                .opacity(isEmpty ? 0.5 : 1)
                .help("Translate (Return)")
            }
        }
    }

    private func header(_ text: String, _ pair: LanguagePair) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.callout)
                .foregroundStyle(Brand.cream.opacity(0.7))
                .lineLimit(4)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text("\(pair.sourceLabel) → \(pair.targetLabel)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Brand.navy)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Brand.gradient))
                .lineLimit(1)
        }
    }

    private func translation(_ result: TranslationResult, _ pair: LanguagePair) -> some View {
        let rtl = pair.targetIsRTL
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: rtl ? .trailing : .leading, spacing: 3) {
                Text(result.translation)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Brand.cream)
                    .multilineTextAlignment(rtl ? .trailing : .leading)
                    .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
                HStack(spacing: 6) {
                    if let transliteration = result.transliteration {
                        Text(transliteration).italic().foregroundStyle(Brand.gold)
                    }
                    if let pos = result.partOfSpeech {
                        Text(pos).foregroundStyle(Brand.cream.opacity(0.5))
                    }
                }
                .font(.footnote)
            }
            CopyButton(text: result.translation)
        }
    }

    private func alternatives(_ items: [TranslationResult.Alternative], rtl: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, alt in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(alt.text)
                        .font(.body)
                        .foregroundStyle(Brand.cream)
                        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("· \(alt.sense)")
                        .font(.footnote)
                        .foregroundStyle(Brand.cream.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// AppKit text field, so it can take focus as soon as the input appears (SwiftUI's
/// @FocusState is a macro; see Package.swift). Return submits.
private struct InputField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusingTextField()
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 15)
        field.bezelStyle = .roundedBezel
        field.alignment = .natural
        field.baseWritingDirection = .natural   // Hebrew input lays out right-to-left
        field.lineBreakMode = .byTruncatingHead
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InputField

        init(_ parent: InputField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}

/// Grabs focus when shown, and handles ⌘X/C/V/A/Z itself: a menu-bar app has no Edit menu
/// to route those key equivalents.
private final class FocusingTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        let action: Selector? = switch key {
        case "x": #selector(NSText.cut(_:))
        case "c": #selector(NSText.copy(_:))
        case "v": #selector(NSText.paste(_:))
        case "a": #selector(NSText.selectAll(_:))
        case "z": Selector(("undo:"))
        default: nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Drag handle in the card's bottom-right corner. Width changes the wrap width; height changes
/// the cap at which content starts scrolling. The size persists via TooltipModel.onResizeEnd.
private struct ResizeGrip: View {
    @ObservedObject var model: TooltipModel

    var body: some View {
        Path { path in
            for offset: CGFloat in [6, 11, 16] {
                path.move(to: CGPoint(x: 20, y: offset))
                path.addLine(to: CGPoint(x: offset, y: 20))
            }
        }
        .stroke(Brand.cream.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .frame(width: 20, height: 20)
        .frame(width: 28, height: 28)   // generous hit area
        .contentShape(Rectangle())
        .help("Drag to resize")
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { _ in
                    // Screen coordinates: the card moves and resizes during the drag, so
                    // view-relative translations would feed back into the gesture and jump.
                    let mouse = NSEvent.mouseLocation
                    if model.dragStart == nil {
                        model.dragStart = CGSize(width: model.width, height: model.maxHeight)
                        model.dragMouse = mouse
                    }
                    guard let start = model.dragStart, let origin = model.dragMouse else { return }
                    let widthRange = AppSettings.tooltipWidthRange
                    let heightRange = AppSettings.tooltipHeightRange
                    let newWidth = start.width + (mouse.x - origin.x)
                    let newHeight = start.height + (origin.y - mouse.y) // screen y grows upward
                    model.width = min(max(newWidth, widthRange.lowerBound), widthRange.upperBound)
                    let cap = min(heightRange.upperBound, model.screenLimit)
                    model.maxHeight = min(max(newHeight, heightRange.lowerBound), cap)
                }
                .onEnded { _ in
                    model.dragStart = nil
                    model.dragMouse = nil
                    model.onResizeEnd?(model.width, model.maxHeight)
                }
        )
    }
}

@MainActor
private final class CopyFeedback: ObservableObject {
    @Published var copied = false

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
    }
}

private struct CopyButton: View {
    let text: String
    @StateObject private var feedback = CopyFeedback()

    var body: some View {
        Button {
            feedback.copy(text)
        } label: {
            Image(systemName: feedback.copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(feedback.copied ? Brand.gold : Brand.orange)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy translation")
    }
}

/// Translucent dark backdrop; the navy tint is layered on top in TooltipView.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
