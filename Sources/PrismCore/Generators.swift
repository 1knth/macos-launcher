import Foundation

/// Random values and canned text offered as commands.
public enum Generators {
    public static func password(length: Int = 20) -> String {
        let alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789-_!@#$%")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    public static let lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur."

    /// "roll", "roll d20", "roll 3d6".
    public static func dice(_ query: String) -> (count: Int, sides: Int)? {
        let lowered = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard lowered.hasPrefix("roll") || lowered.hasPrefix("dice") else { return nil }
        let rest = lowered.dropFirst(4).trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return (1, 6) }
        let parts = rest.split(separator: "d", omittingEmptySubsequences: false)
        guard parts.count == 2, let sides = Int(parts[1]), (2...1000).contains(sides) else { return nil }
        let count = parts[0].isEmpty ? 1 : Int(parts[0]) ?? 0
        guard (1...50).contains(count) else { return nil }
        return (count, sides)
    }
}
