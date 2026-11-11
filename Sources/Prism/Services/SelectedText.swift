import AppKit

/// Reads the frontmost app's selected text through Accessibility. No simulated ⌘C, so opening
/// the launcher stays instant and nothing lands in clipboard history.
enum SelectedText {
    private static var enabledElectron = Set<pid_t>()

    static func capture() -> String {
        guard Accessibility.trusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return "" }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        if let text = read(element), !text.isEmpty { return text }
        // Chromium and Electron apps only build their accessibility tree when asked to.
        guard !enabledElectron.contains(app.processIdentifier) else { return "" }
        enabledElectron.insert(app.processIdentifier)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        return read(element) ?? ""
    }

    private static func read(_ app: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(app, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SelectedText {
    /// Pastes over the still-active selection in the app the launcher was opened from.
    static func replace(with text: String) {
        Paster.copy(text)
        Paster.pasteIntoFrontApp()
    }
}
