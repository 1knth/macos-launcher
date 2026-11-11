import AppKit

/// Floating HUD toast, ported from Clippy's FeedbackPanel. While the launcher is open,
/// messages go to its footer instead, through `inlinePresenter`.
final class Toast: NSPanel {
    private static var current: Toast?
    private static var timer: Timer?
    /// Shows the message somewhere else instead, returning false to fall back to the HUD.
    static var inlinePresenter: ((_ message: String, _ symbol: String) -> Bool)?

    static func show(_ message: String, symbol: String = "checkmark.circle.fill", tint: NSColor = .systemGreen, swatch: NSColor? = nil, duration: TimeInterval = 2.2) {
        if inlinePresenter?(message, symbol) == true { return }
        dismiss()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let panel = Toast(message: message, symbol: symbol, tint: tint, swatch: swatch, visibleFrame: screen.visibleFrame)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
        current = panel
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in dismiss() }
    }

    static func dismiss() {
        timer?.invalidate()
        guard let panel = current else { return }
        current = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        } completionHandler: { panel.orderOut(nil) }
    }

    private init(message: String, symbol: String, tint: NSColor, swatch: NSColor?, visibleFrame: CGRect) {
        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        let textWidth = ceil((message as NSString).size(withAttributes: [.font: font]).width)
        let height: CGFloat = 48
        let width = min(max(200, textWidth + 24 * 2 + 20 + 11), visibleFrame.width - 32)
        let frame = CGRect(x: round(visibleFrame.midX - width / 2), y: round(visibleFrame.minY + 120), width: width, height: height)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        alphaValue = 0
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let glass = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = height / 2
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        // Layer clipping alone doesn't mask the behind-window material's
        // compositor surface, which can leave a rectangular rim around the HUD.
        glass.maskImage = NSImage(size: frame.size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
            return true
        }

        let label = NSTextField(labelWithString: message)
        label.font = font
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let leading: NSView
        if let swatch {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.backgroundColor = swatch.cgColor
            dot.layer?.cornerRadius = 10
            dot.layer?.borderWidth = 1
            dot.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
            leading = dot
        } else {
            let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = tint
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            leading = icon
        }
        leading.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [leading, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 11
        row.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(row)
        NSLayoutConstraint.activate([
            leading.widthAnchor.constraint(equalToConstant: 20),
            leading.heightAnchor.constraint(equalToConstant: 20),
            row.centerXAnchor.constraint(equalTo: glass.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: glass.centerYAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: glass.leadingAnchor, constant: 24),
            row.trailingAnchor.constraint(lessThanOrEqualTo: glass.trailingAnchor, constant: -24),
        ])
        let container = NSView(frame: glass.frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(glass)
        contentView = container
    }
}
