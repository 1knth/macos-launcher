import AppKit
import PrismCore
import ScreenCaptureKit
import Vision

// Screen-region text capture, ported from Clippy (~/Coding/scanner): select a region,
// capture it with ScreenCaptureKit, recognize text locally with Vision, copy it.

private func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
}

/// Full-screen selection overlay: crosshair guides before dragging, then a clear cutout
/// with corner handles and a live size readout, plus a HUD hint pill.
final class SelectionView: NSView {
    var start: CGPoint?
    var end: CGPoint?
    var mouse: CGPoint?
    var finish: ((CGRect) -> Void)?
    var cancel: (() -> Void)?
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    private var selection: CGRect? {
        guard let start, let end else { return nil }
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    override func mouseMoved(with event: NSEvent) {
        mouse = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        mouse = nil
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        start = convert(event.locationInWindow, from: nil)
        end = start
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        end = CGPoint(x: max(0, min(bounds.width, point.x)), y: max(0, min(bounds.height, point.y)))
        mouse = end
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard let rect = selection else { return }
        if rect.width < 4 || rect.height < 4 {
            start = nil
            end = nil
            needsDisplay = true
        } else {
            finish?(rect)
        }
    }
    override func rightMouseDown(with event: NSEvent) { cancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()

        if let rect = selection {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            NSGraphicsContext.restoreGraphicsState()

            let border = NSBezierPath(roundedRect: rect.insetBy(dx: -0.5, dy: -0.5), xRadius: 3.5, yRadius: 3.5)
            border.lineWidth = 1
            NSColor.white.withAlphaComponent(0.9).setStroke()
            border.stroke()
            drawCorners(rect)
            drawSizeLabel(rect)
        } else if let mouse {
            drawCrosshair(at: mouse)
        }
        drawHint()
    }

    private func drawCrosshair(at point: CGPoint) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: 0, y: point.y))
        path.line(to: CGPoint(x: bounds.width, y: point.y))
        path.move(to: CGPoint(x: point.x, y: 0))
        path.line(to: CGPoint(x: point.x, y: bounds.height))
        path.lineWidth = 1
        path.setLineDash([4, 4], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.45).setStroke()
        path.stroke()
    }

    /// L-shaped corner brackets, like the system screenshot tool.
    private func drawCorners(_ rect: CGRect) {
        let length = min(14, rect.width / 3, rect.height / 3)
        let path = NSBezierPath()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1), (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1), (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x + dx * length, y: corner.y))
            path.line(to: corner)
            path.line(to: CGPoint(x: corner.x, y: corner.y + dy * length))
        }
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.white.setStroke()
        path.stroke()
    }

    private func drawSizeLabel(_ rect: CGRect) {
        let scale = window?.backingScaleFactor ?? 2
        let text = "\(Int(rect.width * scale)) × \(Int(rect.height * scale))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium), .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var pill = CGRect(x: rect.midX - size.width / 2 - 8, y: rect.minY - size.height - 14, width: size.width + 16, height: size.height + 6)
        if pill.minY < 8 { pill.origin.y = rect.minY + 8 }
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 3), withAttributes: attributes)
    }

    private func drawHint() {
        let message = "Drag over text to copy it  ·  Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white,
        ]
        let measured = (message as NSString).size(withAttributes: attributes)
        let iconSize: CGFloat = 15
        let width = measured.width + iconSize + 8 + 32
        let height: CGFloat = 34
        let pill = CGRect(x: bounds.midX - width / 2, y: bounds.maxY - height - 64, width: width, height: height)
        // Stay out of the way when the selection reaches the hint.
        if let rect = selection, rect.intersects(pill.insetBy(dx: -10, dy: -10)) { return }
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: pill, xRadius: height / 2, yRadius: height / 2).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let outline = NSBezierPath(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), xRadius: height / 2, yRadius: height / 2)
        outline.lineWidth = 1
        outline.stroke()
        if let icon = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium).applying(.init(paletteColors: [.white]))) {
            icon.draw(in: CGRect(x: pill.minX + 16, y: pill.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height))
        }
        (message as NSString).draw(at: CGPoint(x: pill.minX + 16 + iconSize + 8, y: pill.midY - measured.height / 2), withAttributes: attributes)
    }
}

final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum OCRError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

final class OCRController {
    private var windows: [NSWindow] = []
    private var job: UUID?
    private var workerActive = false
    private var previousApp: NSRunningApplication?
    private var screenObserver: NSObjectProtocol?
    private let ocrQueue = DispatchQueue(label: "app.prism.ocr", qos: .userInitiated)
    /// Runs as a capture starts, so Prism's own windows get out of the way.
    var willCapture: (() -> Void)?

    static var literalMode: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.ocrLiteralMode) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.ocrLiteralMode) }
    }
    static var recognitionLanguages: [String] { UserDefaults.standard.stringArray(forKey: DefaultsKey.ocrRecognitionLanguages) ?? [] }

    init() {
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.windows.isEmpty else { return }
            self.cancelCapture()
            Toast.show("Displays changed. Try again.", symbol: "info.circle.fill", tint: .secondaryLabelColor)
        }
    }

    /// Shared Vision recognizer, also used for images in file search and clipboard history.
    static func recognize(_ image: CGImage, correction: Bool = !literalMode, languages: [String] = recognitionLanguages) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = correction
        request.automaticallyDetectsLanguage = languages.isEmpty
        if !languages.isEmpty { request.recognitionLanguages = languages }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> OCRLine? in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            return OCRLine(text, observation.boundingBox)
        }
        return TextAssembler.assemble(lines)
    }

    /// OCRs an image (file or clipboard) and copies the text.
    static func copyText(from image: NSImage?) {
        guard let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Toast.show("Couldn’t read that image", symbol: "exclamationmark.triangle.fill", tint: .systemOrange)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let text = (try? recognize(cgImage)) ?? ""
            DispatchQueue.main.async {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Toast.show("No text found", symbol: "text.viewfinder", tint: .secondaryLabelColor)
                } else {
                    Paster.copy(text)
                    Toast.show(summary(text), symbol: "text.viewfinder")
                }
            }
        }
    }

    /// "Copied “Hello world…” · 3 lines"
    static func summary(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let first = lines.first.map { String($0.prefix(36)) } ?? ""
        let ellipsis = (lines.first?.count ?? 0) > 36 || lines.count > 1 ? "…" : ""
        return "Copied “\(first)\(ellipsis)”" + (lines.count > 1 ? " · \(lines.count) lines" : "")
    }

    func beginCapture() {
        guard job == nil, !workerActive else { Toast.show("Capture already in progress.", symbol: "info.circle.fill", tint: .secondaryLabelColor); return }
        willCapture?()
        previousApp = NSWorkspace.shared.frontmostApplication
        // Preflight is advisory: let ScreenCaptureKit report whether this process can capture.
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        let id = UUID()
        job = id
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard self.job == id else { return }
                let screens = NSScreen.screens.filter { screen in content.displays.contains { $0.displayID == displayID(screen) } }
                guard !screens.isEmpty else { throw OCRError.message("No available display.") }
                self.presentSelection(screens: screens, id: id)
            } catch { self.fail(error, id: id, stage: "Preparing screen capture") }
        }
    }

    private func presentSelection(screens: [NSScreen], id: UUID) {
        for screen in screens {
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.cancel = { [weak self] in self?.cancelCapture() }
            view.finish = { [weak self] rect in
                let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                self?.capture(rect: global, screen: screen, id: id)
            }
            window.acceptsMouseMovedEvents = true
            window.contentView = view
            let mouse = NSEvent.mouseLocation
            if screen.frame.contains(mouse) { view.mouse = CGPoint(x: mouse.x - screen.frame.minX, y: mouse.y - screen.frame.minY) }
            windows.append(window)
            window.orderFrontRegardless()
            window.makeFirstResponder(view)
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        (windows.first { $0.frame.contains(mouse) } ?? windows.first)?.makeKey()
    }

    private func capture(rect: CGRect, screen: NSScreen, id: UUID) {
        guard job == id, !workerActive else { return }
        workerActive = true
        let overlayIDs = Set(windows.map { CGWindowID($0.windowNumber) })
        closeSelection()
        let correction = !Self.literalMode
        let languages = Self.recognitionLanguages
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard self.job == id else { self.workerActive = false; return }
                guard let display = content.displays.first(where: { $0.displayID == displayID(screen) }) else { throw OCRError.message("Display changed. Try again.") }
                let excluded = content.windows.filter { overlayIDs.contains($0.windowID) }
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = ownApps.isEmpty
                    ? SCContentFilter(display: display, excludingWindows: excluded)
                    : SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                guard let plan = CaptureGeometry.plan(selection: rect, screen: screen.frame, scale: CGFloat(filter.pointPixelScale)) else { throw OCRError.message("Select a larger region.") }
                guard plan.width <= 12000, plan.height <= 12000, plan.width * plan.height <= 32_000_000 else { throw OCRError.message("Select a smaller region (maximum 32 megapixels).") }
                let configuration = SCStreamConfiguration()
                configuration.sourceRect = plan.rect
                configuration.width = plan.width
                configuration.height = plan.height
                configuration.showsCursor = false
                configuration.capturesAudio = false
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                guard self.job == id else { self.workerActive = false; return }
                self.recognize(image, correction: correction, languages: languages, id: id)
            } catch {
                self.workerActive = false
                self.fail(error, id: id, stage: "Capturing selected region")
            }
        }
    }

    private func recognize(_ image: CGImage, correction: Bool, languages: [String], id: UUID) {
        ocrQueue.async {
            let result = Result { try Self.recognize(image, correction: correction, languages: languages) }
            DispatchQueue.main.async {
                self.workerActive = false
                guard self.job == id else { return }
                self.job = nil
                switch result {
                case .success(let text):
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        Toast.show("No text found.", symbol: "text.viewfinder", tint: .secondaryLabelColor)
                        return
                    }
                    Paster.copy(text)
                    Toast.show(Self.summary(text), symbol: "text.viewfinder")
                case .failure(let error): self.fail(error, id: id, stage: "Recognizing text")
                }
            }
        }
    }

    func cancelCapture() {
        job = nil
        closeSelection()
    }

    private func fail(_ error: Error, id: UUID, stage: String) {
        guard job == id else { return }
        let nsError = error as NSError
        fputs("Prism: \(stage) failed [\(nsError.domain):\(nsError.code)]\n", stderr)
        job = nil
        closeSelection()
        let alert = NSAlert()
        alert.messageText = "\(stage) failed"
        alert.informativeText = "\(error.localizedDescription)\n\nIf Screen Recording access is already enabled, quit Prism, remove its entry from Screen & System Audio Recording, add \(Bundle.main.bundlePath) again, and reopen it. Rebuilding an ad-hoc signed app can invalidate its saved permission."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Permission Settings")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func closeSelection() {
        let hadSelection = !windows.isEmpty
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
        if hadSelection, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApp?.activate(options: [])
        }
        previousApp = nil
    }
}
