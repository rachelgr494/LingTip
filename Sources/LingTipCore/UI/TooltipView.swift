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
