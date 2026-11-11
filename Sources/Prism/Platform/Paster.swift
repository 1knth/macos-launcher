import AppKit
import Carbon

enum Paster {
    /// Simulates ⌘V into the frontmost app after the launcher hides.
    static func pasteIntoFrontApp() {
        guard Accessibility.trusted else {
            Accessibility.ensureTrusted()
            Toast.show("Copied. Allow Accessibility to paste directly.", symbol: "hand.raised.fill")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let vKey = CGKeyCode(kVK_ANSI_V)
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
