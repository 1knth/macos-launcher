import Carbon
import Foundation

/// Global shortcuts through Carbon, which needs no extra permission (same approach as Clippy).
final class HotKeys {
    struct Binding: Codable {
        let keyCode: UInt32
        let modifiers: UInt32
        let label: String
        var display: String {
            var result = ""
            if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
            return result + label
        }
    }

    static let shared = HotKeys()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    @discardableResult
    func register(_ binding: Binding, _ handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(binding.keyCode, binding.modifiers, EventHotKeyID(signature: 0x50524953, id: id), GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            fputs("Prism: shortcut \(binding.display) unavailable (\(status))\n", stderr)
            return false
        }
        refs[id] = ref
        handlers[id] = handler
        return true
    }

    func unregisterAll() {
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeys.shared.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}
