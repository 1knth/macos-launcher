import AppKit

/// Keyboard routing. Keys are tried in priority order: global launcher keys, the ⌘K panel,
/// the chat composer, list navigation, then the current item's action shortcuts.
/// Anything not consumed falls through to the search field as typing.
extension LauncherState {
    /// Returns true when the key was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        if KeyCombo.cmd(",").matches(event) { SettingsController.shared.show(); return true }
        if showActions { handleActionPanelKey(event); return true }
        if route == .chat, handleChatKey(event) { return true }
        if KeyCombo.cmd("k").matches(event) { openActions(); return true }
        if event.keyCode == KeyCode.escape { escape(); return true }
        if route.hasRows, handleNavigationKey(event) { return true }

        let flags = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
        // ⌫ on an empty field goes back, like Raycast.
        if event.keyCode == KeyCode.delete, flags.isEmpty, query.isEmpty, route != .root, route != .chat { pop(); return true }
        if KeyCombo.cmd("w").matches(event) { services.launcher?.hide(); return true }
        return runActionShortcut(event)
    }

    private func handleActionPanelKey(_ event: NSEvent) {
        let actions = actionItem?.actions ?? []
        let flags = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
        switch event.keyCode {
        case KeyCode.escape: showActions = false
        case KeyCode.upArrow: actionSelection = max(0, actionSelection - 1)
        case KeyCode.downArrow: actionSelection = min(max(actions.count - 1, 0), actionSelection + 1)
        default:
            if KeyCode.isReturn(event.keyCode), flags.isEmpty, actions.indices.contains(actionSelection) {
                perform(actions[actionSelection], on: actionItem)
            } else if KeyCombo.cmd("k").matches(event) {
                showActions = false
            } else if let action = actions.first(where: { $0.shortcut?.matches(event) == true }) {
                perform(action, on: actionItem)
            }
        }
    }

    /// In chat the search field is the composer: Return sends and ⌘V can attach an image.
    private func handleChatKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
        if KeyCode.isReturn(event.keyCode), flags.isEmpty {
            if chat.send(query) { query = "" }
            return true
        }
        if KeyCombo.cmd("v").matches(event), let image = NSImage(pasteboard: .general) { chat.attach(image); return true }
        if KeyCombo.cmd("n").matches(event) { chat.newChat(); query = ""; return true }
        if KeyCombo.cmd("⌫").matches(event) { chat.deleteCurrent(); query = ""; return true }
        if KeyCombo.cmd(".").matches(event) { chat.stop(); return true }
        return false
    }

    private func handleNavigationKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
        switch event.keyCode {
        case KeyCode.upArrow:
            if flags.isEmpty, recallOlderSearch() { return true }
            move(-1)
        case KeyCode.downArrow: move(1)
        case KeyCode.pageUp: move(-8)
        case KeyCode.pageDown: move(8)
        default:
            if KeyCombo.ctrl("p").matches(event) { move(-1) } else if KeyCombo.ctrl("n").matches(event) { move(1) } else { return false }
        }
        return true
    }

    /// Return runs the primary action; any other match runs that action.
    private func runActionShortcut(_ event: NSEvent) -> Bool {
        guard let item = actionItem else { return false }
        let flags = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
        if KeyCode.isReturn(event.keyCode), flags.isEmpty, let primary = item.actions.first {
            perform(primary, on: item)
            return true
        }
        if let action = item.actions.first(where: { $0.shortcut?.matches(event) == true }) {
            perform(action, on: item)
            return true
        }
        return false
    }
}
