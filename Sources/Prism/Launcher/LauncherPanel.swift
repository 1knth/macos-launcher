import AppKit
import SwiftUI

/// A borderless, non-activating panel: it takes keyboard focus while the app you were using
/// stays frontmost, so paste and window commands land in the right place (like Spotlight).
/// The window is larger than the visible launcher by `margin` so a soft shadow fits around it.
final class LauncherPanel: NSPanel {
    static let margin: CGFloat = 28
    static let cornerRadius: CGFloat = 14
    static let dragRegionHeight: CGFloat = 56
    static let footerHeight: CGFloat = 40

    var keyHandler: ((NSEvent) -> Bool)?
    var onClickOutside: (() -> Void)?
    var onDragMove: ((CGPoint) -> CGPoint)?
    var onDragEnd: (() -> Void)?

    init() {
        let size = CGSize(width: LauncherView.size.width + Self.margin * 2, height: LauncherView.size.height + Self.margin * 2)
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // Appear and disappear instantly, no fade.
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The visible launcher inside the shadow margin, in window coordinates.
    var launcherRect: CGRect { CGRect(origin: .zero, size: frame.size).insetBy(dx: Self.margin, dy: Self.margin) }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            if keyHandler?(event) == true { return }
        case .leftMouseDown, .rightMouseDown:
            let point = event.locationInWindow
            if !launcherRect.contains(point) {
                onClickOutside?()
                return
            }
            if event.type == .leftMouseDown, isDragRegion(point) {
                trackPotentialDrag(event)
                return
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    private func isDragRegion(_ point: CGPoint) -> Bool {
        let rect = launcherRect
        return point.y >= rect.maxY - Self.dragRegionHeight || point.y <= rect.minY + Self.footerHeight
    }

    /// A press in the search bar or footer is a click unless the mouse moves a few points,
    /// in which case the launcher follows the mouse. Clicks are replayed so the field
    /// still focuses, places the caret and handles double-clicks.
    private func trackPotentialDrag(_ down: NSEvent) {
        let startMouse = NSEvent.mouseLocation
        let startOrigin = frame.origin
        var dragging = false
        while let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp {
                if dragging {
                    onDragEnd?()
                } else {
                    NSApp.postEvent(next, atStart: true)
                    super.sendEvent(down)
                }
                return
            }
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - startMouse.x, dy = mouse.y - startMouse.y
            if !dragging, hypot(dx, dy) < 4 { continue }
            dragging = true
            let proposed = CGPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)
            setFrameOrigin(onDragMove?(proposed) ?? proposed)
        }
    }
}

/// Soft shadow drawn only outside the launcher's rounded rect, so the translucent
/// background isn't darkened from underneath.
final class ShadowView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 13
        layer?.shadowOffset = CGSize(width: 0, height: -5)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let inner = bounds.insetBy(dx: LauncherPanel.margin, dy: LauncherPanel.margin)
        let shape = CGPath(roundedRect: inner, cornerWidth: LauncherPanel.cornerRadius, cornerHeight: LauncherPanel.cornerRadius, transform: nil)
        layer?.shadowPath = shape
        let mask = CAShapeLayer()
        let cutout = CGMutablePath()
        cutout.addRect(bounds)
        cutout.addPath(shape)
        mask.path = cutout
        mask.fillRule = .evenOdd
        layer?.mask = mask
    }
}

/// The launcher's translucent background with a hairline edge that adapts to light and dark.
final class LauncherBackground: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .sidebar
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = LauncherPanel.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        updateBorder()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    private func updateBorder() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.borderColor = (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.12)).cgColor
    }
}

/// Dotted guides shown while dragging the launcher; the snapped guide is drawn brighter.
final class SnapGuides {
    struct Guide: Equatable {
        enum Axis { case vertical, horizontal }
        let axis: Axis
        let position: CGFloat
    }

    private var window: NSWindow?
    private let view = GuideView()

    func show(on screen: NSScreen, guides: [Guide], snapped: [Guide], below panel: NSWindow) {
        if window == nil || window?.frame != screen.frame {
            let guideWindow = window ?? NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            guideWindow.setFrame(screen.frame, display: false)
            guideWindow.isOpaque = false
            guideWindow.backgroundColor = .clear
            guideWindow.ignoresMouseEvents = true
            guideWindow.hasShadow = false
            guideWindow.isReleasedWhenClosed = false
            guideWindow.level = panel.level
            guideWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            guideWindow.animationBehavior = .none
            guideWindow.contentView = view
            window = guideWindow
        }
        view.origin = screen.frame.origin
        view.guides = guides
        view.snapped = snapped
        view.needsDisplay = true
        window?.order(.below, relativeTo: panel.windowNumber)
    }

    func hide() { window?.orderOut(nil) }

    private final class GuideView: NSView {
        var origin: CGPoint = .zero
        var guides: [Guide] = []
        var snapped: [Guide] = []

        override func draw(_ dirtyRect: NSRect) {
            for guide in guides {
                let active = snapped.contains(guide)
                let path = NSBezierPath()
                if guide.axis == .vertical {
                    path.move(to: CGPoint(x: guide.position - origin.x, y: 0))
                    path.line(to: CGPoint(x: guide.position - origin.x, y: bounds.height))
                } else {
                    path.move(to: CGPoint(x: 0, y: guide.position - origin.y))
                    path.line(to: CGPoint(x: bounds.width, y: guide.position - origin.y))
                }
                path.lineWidth = 1
                path.setLineDash([3, 5], count: 2, phase: 0)
                NSColor.white.withAlphaComponent(active ? 0.55 : 0.16).setStroke()
                path.stroke()
                // A dark companion line keeps guides visible over light wallpapers.
                path.setLineDash([3, 5], count: 2, phase: 3)
                NSColor.black.withAlphaComponent(active ? 0.3 : 0.08).setStroke()
                path.stroke()
            }
        }
    }
}
