import CoreGraphics
import Foundation

/// A modifier combination plus mouse button that starts a window drag, like ⌃⌘ + drag.
struct DragBinding: Codable, Hashable {
    enum Button: String, Codable { case left, right }

    /// `CGEventFlags` raw value, limited to ⌃ ⌥ ⇧ ⌘.
    let modifiers: UInt64
    let button: Button

    init(_ flags: CGEventFlags, _ button: Button) {
        modifiers = flags.intersection(DragBinding.relevantFlags).rawValue
        self.button = button
    }

    static let relevantFlags: CGEventFlags = [.maskControl, .maskCommand, .maskAlternate, .maskShift]

    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }

    var display: String {
        var keys = ""
        if flags.contains(.maskControl) { keys += "⌃" }
        if flags.contains(.maskAlternate) { keys += "⌥" }
        if flags.contains(.maskShift) { keys += "⇧" }
        if flags.contains(.maskCommand) { keys += "⌘" }
        return keys + (button == .left ? " Drag" : " Right-Drag")
    }

    /// Every combination offered in Settings. Two or more modifiers, so ordinary clicks never match.
    static let choices: [DragBinding] = {
        let combos: [CGEventFlags] = [
            [.maskControl, .maskCommand], [.maskControl, .maskAlternate], [.maskAlternate, .maskCommand],
            [.maskControl, .maskShift], [.maskAlternate, .maskShift], [.maskShift, .maskCommand],
            [.maskControl, .maskAlternate, .maskCommand],
        ]
        return [Button.left, .right].flatMap { button in combos.map { DragBinding($0, button) } }
    }()
}

/// What a window drag does.
enum DragAction: String, CaseIterable, Codable, Identifiable {
    case move, resize
    var id: Self { self }
    var title: String { self == .move ? "Move Window" : "Resize Window" }
}

/// A primary binding and an optional secondary one.
struct DragSlots: Codable, Equatable {
    var primary: DragBinding?
    var secondary: DragBinding?
    var all: [DragBinding] { [primary, secondary].compactMap { $0 } }
}

/// The drag gestures in use, saved when changed in Settings.
enum DragBindings {
    /// Resize is the only gesture with a secondary binding by default: ⌃⌥ + drag, for trackpads without right click.
    static let defaults: [DragAction: DragSlots] = [
        .move: DragSlots(primary: DragBinding([.maskControl, .maskCommand], .left)),
        .resize: DragSlots(primary: DragBinding([.maskControl, .maskCommand], .right),
                           secondary: DragBinding([.maskControl, .maskAlternate], .left)),
    ]

    static func load() -> [DragAction: DragSlots] {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.dragBindings),
              let saved = try? JSONDecoder().decode([String: DragSlots].self, from: data) else { return defaults }
        var result = defaults
        for action in DragAction.allCases { if let slots = saved[action.rawValue] { result[action] = slots } }
        return result
    }

    static func save(_ bindings: [DragAction: DragSlots]) {
        let encoded = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encoded) { UserDefaults.standard.set(data, forKey: DefaultsKey.dragBindings) }
    }
}
