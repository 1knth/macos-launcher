import AppKit
import SwiftUI

/// Owns the launcher window: showing, hiding, where it appears, and dragging it with snap guides.
final class LauncherController: NSObject, NSWindowDelegate {
    let state = LauncherState()
    private let panel = LauncherPanel()
    private let guides = SnapGuides()
    private let positionKey = DefaultsKey.launcherCenter
    private let snapDistance: CGFloat = 10

    var isVisible: Bool { panel.isVisible }

    override init() {
        super.init()
        let container = NSView(frame: CGRect(origin: .zero, size: panel.frame.size))
        container.autoresizingMask = [.width, .height]
        let shadow = ShadowView(frame: container.bounds)
        shadow.autoresizingMask = [.width, .height]
        let background = LauncherBackground(frame: container.bounds.insetBy(dx: LauncherPanel.margin, dy: LauncherPanel.margin))
        background.autoresizingMask = [.width, .height]
        let hosting = NSHostingView(rootView: LauncherView(state: state))
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        container.addSubview(shadow)
        container.addSubview(background)
        panel.contentView = container
        panel.delegate = self
        panel.keyHandler = { [weak self] event in self?.state.handleKey(event) ?? false }
        panel.onClickOutside = { [weak self] in self?.hide() }
        panel.onDragMove = { [weak self] origin in self?.snap(origin) ?? origin }
        panel.onDragEnd = { [weak self] in self?.dragEnded() }
        Toast.inlinePresenter = { [weak self] message, symbol in
            guard let self, self.isVisible else { return false }
            self.state.flash(message, symbol: symbol)
            return true
        }
        state.refresh()
        // Draw the panel once, invisibly, so the first real open doesn't pay for SwiftUI's first layout.
        DispatchQueue.main.async { [self] in
            guard !panel.isVisible else { return }
            panel.alphaValue = 0
            position()
            panel.orderFrontRegardless()
            panel.displayIfNeeded()
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    func toggle() {
        if panel.isVisible && panel.isKeyWindow { hide() } else { show() }
    }

    /// Every open starts fresh at the root search; `resume` keeps the current view, for flows
    /// that hide the launcher briefly (like picking a color from the screen).
    func show(_ route: Route? = nil, resume: Bool = false) {
        if !panel.isVisible, !resume { state.reset() }
        if let route, state.route != route {
            state.reset()
            if route != .root { state.push(route) }
        }
        if state.route == .root { state.captureSelection() }
        LoginItem.reload()
        position()
        panel.orderFrontRegardless()
        panel.makeKey()
        state.didShow()
    }

    func hide() {
        guard panel.isVisible else { return }
        state.showActions = false
        state.clearHover()
        state.recordSearch()
        guides.hide()
        panel.orderOut(nil)
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: positionKey)
        if panel.isVisible { position() }
    }

    private var currentScreen: NSScreen {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Default spot: horizontally centered, a little above the middle (Raycast/Spotlight).
    private func defaultCenter(in area: CGRect) -> CGPoint {
        CGPoint(x: area.midX, y: area.minY + area.height * 0.62)
    }

    private func position() {
        let area = currentScreen.visibleFrame
        var center = defaultCenter(in: area)
        if let saved = UserDefaults.standard.array(forKey: positionKey) as? [Double], saved.count == 2 {
            center = CGPoint(x: area.minX + area.width * saved[0], y: area.minY + area.height * saved[1])
        }
        let size = LauncherView.size
        var rect = CGRect(x: round(center.x - size.width / 2), y: round(center.y - size.height / 2), width: size.width, height: size.height)
        rect.origin.x = min(max(rect.minX, area.minX + 8), area.maxX - size.width - 8)
        rect.origin.y = min(max(rect.minY, area.minY + 8), area.maxY - size.height - 8)
        panel.setFrame(rect.insetBy(dx: -LauncherPanel.margin, dy: -LauncherPanel.margin), display: false)
    }

    /// Snaps the launcher's center to the screen's center lines and its default height.
    private func snap(_ origin: CGPoint) -> CGPoint {
        let size = LauncherView.size
        var center = CGPoint(x: origin.x + LauncherPanel.margin + size.width / 2, y: origin.y + LauncherPanel.margin + size.height / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? currentScreen
        let area = screen.visibleFrame
        let home = defaultCenter(in: area)
        let all: [SnapGuides.Guide] = [
            .init(axis: .vertical, position: area.midX),
            .init(axis: .horizontal, position: area.midY),
            .init(axis: .horizontal, position: home.y),
        ]
        var snapped: [SnapGuides.Guide] = []
        if let vertical = all.first(where: { $0.axis == .vertical && abs($0.position - center.x) < snapDistance }) {
            center.x = vertical.position
            snapped.append(vertical)
        }
        if let horizontal = all.filter({ $0.axis == .horizontal }).min(by: { abs($0.position - center.y) < abs($1.position - center.y) }),
           abs(horizontal.position - center.y) < snapDistance {
            center.y = horizontal.position
            snapped.append(horizontal)
        }
        guides.show(on: screen, guides: all, snapped: snapped, below: panel)
        return CGPoint(x: round(center.x - size.width / 2 - LauncherPanel.margin), y: round(center.y - size.height / 2 - LauncherPanel.margin))
    }

    private func dragEnded() {
        guides.hide()
        let rect = panel.frame.insetBy(dx: LauncherPanel.margin, dy: LauncherPanel.margin)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) } ?? currentScreen
        let area = screen.visibleFrame
        UserDefaults.standard.set([Double((rect.midX - area.minX) / area.width), Double((rect.midY - area.minY) / area.height)], forKey: positionKey)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Alerts we present (e.g. delete-all confirmation) temporarily take key; don't hide for those.
        DispatchQueue.main.async { [weak self] in
            guard let self, NSApp.modalWindow == nil, !self.panel.isKeyWindow else { return }
            self.hide()
        }
    }
}
