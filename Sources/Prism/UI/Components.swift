import AppKit
import SwiftUI

/// AppKit text field so the field editor behaves exactly like a native search box.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusToken: Int

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 18, weight: .regular)
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.systemFont(ofSize: 18, weight: .regular),
        ])
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        var focusToken = -1
        init(_ parent: SearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

struct IconView: View {
    let icon: ItemIcon
    var size: CGFloat = 20

    var body: some View {
        switch icon {
        case .image(let image):
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        case .file(let path):
            Image(nsImage: IconCache.icon(path)).resizable().interpolation(.high).frame(width: size + 2, height: size + 2)
        case .symbol(let name, let color):
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.95), color], startPoint: .top, endPoint: .bottom))
                .overlay(
                    Image(systemName: name)
                        .font(.system(size: size * 0.55, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .frame(width: size, height: size)
        case .emoji(let character):
            Text(character).font(.system(size: size * 0.92)).frame(width: size, height: size)
        case .color(let color):
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Color(nsColor: color))
                .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                .frame(width: size, height: size)
        }
    }
}

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(minWidth: 17, minHeight: 17)
            .padding(.horizontal, text.count > 1 ? 4 : 0)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}

struct ShortcutCaps: View {
    let combo: KeyCombo
    var body: some View {
        HStack(spacing: 3) { ForEach(Array(combo.caps.enumerated()), id: \.offset) { KeyCap(text: $0.element) } }
    }
}

struct ResultRow: View {
    let item: ResultItem
    let selected: Bool

    var body: some View {
        Group {
            switch item.style {
            case .normal: normal
            case let .calculator(expression, result, detail): calculator(expression, result, detail)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.085) : .clear)
        )
        .contentShape(Rectangle())
    }

    private var normal: some View {
        HStack(spacing: 10) {
            IconView(icon: item.icon)
            Text(item.title).font(.system(size: 13)).foregroundStyle(.primary).lineLimit(1)
            if let subtitle = item.subtitle {
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let end = item.countdown {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.remaining(end, now: context.date)).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(.orange)
                }
            }
            if let accessory = item.accessory {
                Text(accessory).font(.system(size: 12)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
    }

    private func calculator(_ expression: String, _ result: String, _ detail: String) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(expression).font(.system(size: 20, weight: .regular)).lineLimit(1).minimumScaleFactor(0.5)
                Text("Question").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .frame(maxWidth: .infinity)
            Image(systemName: "arrow.right").font(.system(size: 18, weight: .medium)).foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text(result).font(.system(size: 24, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.4).textSelection(.enabled)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .frame(height: 100)
    }

    static func remaining(_ end: Date, now: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(now).rounded()))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 10)
            .padding(.top, 9)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Native vibrancy behind SwiftUI content.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}
