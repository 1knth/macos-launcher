import Foundation

/// Every UserDefaults key Prism stores, in one place so names can't drift or collide.
/// Values are persisted on users' Macs, so never rename one without migrating it.
enum DefaultsKey {
    // App
    static let launchedBefore = "launchedBefore"
    static let launcherCenter = "launcherCenter"
    static let customShortcuts = "customShortcuts"
    // Extensions
    static let windowShortcuts = "windowShortcuts"
    static let windowDragging = "windowDragging"
    static let clipboardPaused = "clipboardPaused"
    // Ranking
    static let frecency = "frecency"
    static let searchHistory = "searchHistory"
    static let learnedQueries = "learnedQueries"
    // Features
    static let savedColors = "savedColors"
    static let ocrLiteralMode = "literalMode"
    static let ocrRecognitionLanguages = "recognitionLanguages"
}
