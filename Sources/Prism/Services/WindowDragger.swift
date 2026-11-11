import AppKit
import ApplicationServices
import os

private let log = Logger(subsystem: "app.local.prism", category: "drag")

/// Hold ⌃⌘ and drag anywhere on screen to move the active window; ⌃⌘ right-drag resizes it around its center,
/// moving all four corners at once.
/// An active session event tap swallows the modified clicks so the app underneath never sees them. Taps run on
/// their own thread and Accessibility calls run on a serial queue, so neither Prism's main thread nor a slow app
/// can stall clicks system-wide. Approach adapted from easy-move-resize (MIT, Daniel Marcotte).
final class WindowDragger {
    static var enabled: Bool { UserDefaults.standard.object(forKey: DefaultsKey.windowDragging) as? Bool ?? true }
    private static let modifiers: CGEventFlags = [.maskControl, .maskCommand]
    private static let relevantFlags: CGEventFlags = [.maskControl, .maskCommand, .maskAlternate, .maskShift]
    private static let minimumSize = CGSize(width: 100, height: 50)

    private enum Kind { case move, resize }
    private struct Session {
        let kind: Kind
        let app: AXUIElement
        let window: AXUIElement
        let start: CGPoint
        let frame: CGRect
        let restoreEnhancedUI: Bool
        /// 1 when the grab started right of (below) the center, so dragging that way grows the window; -1 otherwise.
        let horizontal: CGFloat
        let vertical: CGFloat
    }

    // Owned by the main thread.
    private var eventRunLoop: CFRunLoop?
    private var trustTimer: Timer?
    // Owned by the event thread.
    private var keyTap: CFMachPort?
    private var mouseTap: CFMachPort?
    private var dragging: Kind?
    // Owned by `queue`.
    private let queue = DispatchQueue(label: "app.local.prism.window-drag", qos: .userInteractive)
    private var session: Session?
    // Shared between the event thread and `queue`; drags coalesce to the latest point.
    private let lock = NSLock()
    private var latest: CGPoint?
    private var flushScheduled = false
    // The active app, tracked from workspace notifications; guarded by `lock` (written on main, read on `queue`).
    private var frontPID: pid_t = 0

    func start() {
        // The system-wide AXFocusedApplication query fails intermittently, so track the active app directly.
        frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            lock.lock()
            frontPID = app.processIdentifier
            lock.unlock()
        }
        reload()
        // Starts listening once Accessibility is granted.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.reload() }
        trustTimer?.tolerance = 0.5
        // Any change to the Accessibility list (including Prism's access being revoked) drops every tap at once;
        // the timer brings them back if access remains.
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
            self?.stopEventThread()
        }
    }

    func reload() {
        let wanted = Self.enabled && Accessibility.trusted
        if wanted, eventRunLoop == nil { startEventThread() } else if !wanted, eventRunLoop != nil { stopEventThread() }
    }

    /// A high-priority thread with a listen-only tap for modifier changes. It installs the active mouse tap the
    /// moment ⌃⌘ goes down, without waiting on Prism's main thread, which macOS deprioritizes in the background.
    /// A listen-only tap can't hold up input, so it's safe to keep around.
    private func startEventThread() {
        let ready = DispatchSemaphore(value: 0)
        var runLoop: CFRunLoop?
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            let callback: CGEventTapCallBack = { _, type, event, info in
                Unmanaged<WindowDragger>.fromOpaque(info!).takeUnretainedValue().handleKey(type, event)
                return Unmanaged.passUnretained(event)
            }
            keyTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                       eventsOfInterest: 1 << CGEventType.flagsChanged.rawValue, callback: callback,
                                       userInfo: Unmanaged.passUnretained(self).toOpaque())
            if let keyTap { CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(nil, keyTap, 0), .commonModes) }
            ready.signal()
            guard keyTap != nil else {
                fputs("Prism: window dragging unavailable (modifier tap refused)\n", stderr)
                return
            }
            CFRunLoopRun()
        }
        thread.name = "Prism window drag"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        eventRunLoop = runLoop
    }

    private func stopEventThread() {
        guard let runLoop = eventRunLoop else { return }
        eventRunLoop = nil
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
            removeMouseTap()
            if let keyTap { CFMachPortInvalidate(keyTap) }
            keyTap = nil
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(runLoop)
    }

    // MARK: Event thread

    private static func held(_ flags: CGEventFlags) -> Bool { flags.intersection(relevantFlags) == modifiers }

    private func handleKey(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            log.notice("key tap disabled (\(type.rawValue)); re-enabling")
            if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: true) }
        case .flagsChanged:
            log.notice("flags \(event.flags.rawValue, format: .hex) held=\(Self.held(event.flags)) tap=\(self.mouseTap != nil) dragging=\(self.dragging != nil)")
            if Self.held(event.flags) { installMouseTap() } else if dragging == nil { removeMouseTap() }
        default:
            break
        }
    }

    /// The active tap that swallows ⌃⌘ clicks. It only exists while ⌃⌘ is held or a drag is in progress: an active
    /// tap whose Accessibility access is revoked can freeze all input.
    private func installMouseTap() {
        guard mouseTap == nil else { return }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            Unmanaged<WindowDragger>.fromOpaque(info!).takeUnretainedValue().handleMouse(type, event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            log.error("mouse tap refused")
            return
        }
        log.notice("mouse tap installed")
        mouseTap = tap
        dragging = nil
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    }

    private func removeMouseTap() {
        guard let mouseTap else { return }
        CGEvent.tapEnable(tap: mouseTap, enable: false)
        CFMachPortInvalidate(mouseTap)
        self.mouseTap = nil
        log.notice("mouse tap removed (dragging=\(self.dragging != nil))")
        if dragging != nil {
            dragging = nil
            queue.async { self.end() }
        }
    }

    private func handleMouse(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            log.notice("mouse tap disabled (\(type.rawValue)); re-enabling")
            // The mouse-up may have been missed while disabled; drop the session rather than swallow a later drag.
            if dragging != nil {
                dragging = nil
                queue.async { self.end() }
            }
            if let mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: true) }
            return pass
        case .leftMouseDown, .rightMouseDown:
            // A new press means any previous session lost its mouse-up.
            if dragging != nil {
                dragging = nil
                queue.async { self.end() }
            }
            log.notice("mouse down \(type.rawValue) flags \(event.flags.rawValue, format: .hex) held=\(Self.held(event.flags)) wasDragging=\(self.dragging != nil)")
            guard Self.held(event.flags) else { return pass }
            let kind: Kind = type == .leftMouseDown ? .move : .resize
            let point = event.location
            dragging = kind
            queue.async { self.begin(kind, at: point) }
            return nil
        case .leftMouseDragged, .rightMouseDragged:
            // Keep swallowing even if the modifiers are released mid-drag, so the app never sees half a click.
            guard let kind = dragging, (kind == .move) == (type == .leftMouseDragged) else { return pass }
            schedule(event.location)
            return nil
        case .leftMouseUp, .rightMouseUp:
            guard let kind = dragging, (kind == .move) == (type == .leftMouseUp) else { return pass }
            dragging = nil
            schedule(event.location)
            queue.async { self.end() }
            // If the keys were released mid-drag, drop the tap now that the drag is over (after this callback returns).
            if !Self.held(event.flags) {
                CFRunLoopPerformBlock(CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue) { [self] in
                    if dragging == nil, !Self.held(CGEventSource.flagsState(.combinedSessionState)) { removeMouseTap() }
                }
            }
            return nil
        default:
            return pass
        }
    }

    private func schedule(_ point: CGPoint) {
        lock.lock()
        latest = point
        let needsFlush = !flushScheduled
        flushScheduled = true
        lock.unlock()
        if needsFlush { queue.async { self.flush() } }
    }

    // MARK: Accessibility queue

    private func flush() {
        lock.lock()
        let point = latest
        flushScheduled = false
        lock.unlock()
        if let point { apply(point) }
    }

    /// Drags act on the active window wherever the pointer is.
    private func begin(_ kind: Kind, at point: CGPoint) {
        end()
        lock.lock()
        let pid = frontPID
        lock.unlock()
        guard pid != 0, pid != getpid() else { return log.notice("begin: no active app") }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let window = Self.element(app, kAXFocusedWindowAttribute) ?? Self.element(app, kAXMainWindowAttribute) else {
            return log.notice("begin: no focused window")
        }
        guard !Self.bool(window, "AXFullScreen"), let frame = WindowManager.frame(of: window) else { return log.notice("begin: full screen or no frame") }
        AXUIElementSetMessagingTimeout(window, 0.25)
        // Apps with enhanced UI on (set by assistive tools) animate AX frame changes, which makes drags lag.
        let enhanced = Self.bool(app, "AXEnhancedUserInterface")
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        let horizontal: CGFloat = point.x >= frame.midX ? 1 : -1
        let vertical: CGFloat = point.y >= frame.midY ? 1 : -1
        log.notice("begin \(kind == .move ? "move" : "resize") frame \(frame.debugDescription, privacy: .public)")
        session = Session(kind: kind, app: app, window: window, start: point, frame: frame,
                          restoreEnhancedUI: enhanced, horizontal: horizontal, vertical: vertical)
    }

    private func apply(_ point: CGPoint) {
        guard let session else { return }
        let dx = point.x - session.start.x, dy = point.y - session.start.y
        let frame = session.frame
        switch session.kind {
        case .move:
            Self.setPosition(session.window, CGPoint(x: frame.minX + dx, y: frame.minY + dy))
        case .resize:
            // Every edge moves by the drag distance, so the window grows or shrinks around its center.
            var size = frame.size
            size.width = max(size.width + 2 * session.horizontal * dx, Self.minimumSize.width)
            size.height = max(size.height + 2 * session.vertical * dy, Self.minimumSize.height)
            var value = size
            guard let sizeValue = AXValueCreate(.cgSize, &value) else { return }
            AXUIElementSetAttributeValue(session.window, kAXSizeAttribute as CFString, sizeValue)
            // Center on the size the app actually accepted, so clamped windows don't drift.
            let actual = WindowManager.frame(of: session.window)?.size ?? size
            Self.setPosition(session.window, CGPoint(x: frame.midX - actual.width / 2, y: frame.midY - actual.height / 2))
        }
    }

    private func end() {
        if let session, session.restoreEnhancedUI {
            AXUIElementSetAttributeValue(session.app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        session = nil
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    private static func setPosition(_ window: AXUIElement, _ point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }
}
