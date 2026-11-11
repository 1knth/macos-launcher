import AppKit

/// The composition root: one instance of every long-lived service, created at launch.
/// Services don't know about the launcher; anything that spans both is wired here.
final class AppServices {
    static let shared = AppServices()

    // Data
    let apps = AppIndex()
    let clipboard = ClipboardStore()
    let colors = ColorStore()
    // Ranking
    let frecency = Frecency()
    let learned = LearnedStore()
    let searchHistory = SearchHistory()
    // System
    let timers = TimerManager()
    let caffeine = Caffeine()
    let ocr = OCRController()
    let windowDragger = WindowDragger()

    /// Set once at launch; nil in snapshot renders.
    var launcher: LauncherController?

    private init() {
        ocr.willCapture = { [weak self] in self?.launcher?.hide() }
    }

    func start() {
        apps.start()
        clipboard.start()
        windowDragger.start()
    }

    func captureText() { ocr.beginCapture() }

    /// Hides the launcher so it doesn't cover the screen, then opens the system loupe.
    func pickColor(completion: ((NSColor) -> Void)? = nil) {
        launcher?.hide()
        colors.pickFromScreen(completion: completion)
    }
}
