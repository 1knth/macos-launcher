import ApplicationServices

enum Accessibility {
    static var trusted: Bool { AXIsProcessTrusted() }

    /// Prompts for Accessibility access (needed for auto-paste and window management).
    @discardableResult
    static func ensureTrusted() -> Bool {
        if AXIsProcessTrusted() { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
