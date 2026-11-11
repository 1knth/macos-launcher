import Foundation

/// Ranks how well a typed query matches a candidate title, Raycast-style:
/// exact > prefix > word prefix > initials ("vsc" → Visual Studio Code) > substring > subsequence.
public enum Fuzzy {
    /// Returns a score in 0...1, or nil when the query does not match.
    public static func score(_ query: String, _ candidate: String, keywords: [String] = []) -> Double? {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return 0.5 }
        var best = single(q, candidate)
        let tokens = q.split(separator: " ").map(String.init)
        if tokens.count > 1, best == nil {
            // Every token has to match somewhere; the weakest one sets the score.
            let scores = tokens.map { token in single(token, candidate) }
            if scores.allSatisfy({ $0 != nil }) { best = scores.compactMap { $0 }.min().map { $0 * 0.9 } }
        }
        for keyword in keywords {
            if let s = single(q, keyword).map({ $0 * 0.85 }), s > (best ?? 0) { best = s }
        }
        return best
    }

    static func single(_ q: String, _ candidate: String) -> Double? {
        let c = candidate.lowercased()
        if c == q { return 1 }
        let ratio = Double(q.count) / Double(max(c.count, 1))
        if c.hasPrefix(q) { return 0.9 + 0.09 * ratio }
        let words = Self.words(candidate)
        if words.contains(where: { $0.hasPrefix(q) }) { return 0.78 + 0.1 * ratio }
        let initials = String(words.compactMap(\.first))
        if q.count >= 2, initials.hasPrefix(q) { return 0.74 + 0.1 * Double(q.count) / Double(max(initials.count, 1)) }
        if c.contains(q) { return 0.6 + 0.1 * ratio }
        return subsequence(q, c)
    }

    /// Lowercased words split on separators, camelCase and letter/digit boundaries.
    public static func words(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previous: Character?
        for character in text {
            let separator = character.isWhitespace || "-_./()[]:,".contains(character)
            if separator {
                if !current.isEmpty { result.append(current) }
                current = ""
            } else {
                if let previous, !current.isEmpty,
                   (previous.isLowercase && character.isUppercase) || (previous.isLetter && character.isNumber) {
                    result.append(current)
                    current = ""
                }
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { result.append(current) }
        return result.map { $0.lowercased() }
    }

    static func subsequence(_ q: String, _ c: String) -> Double? {
        guard q.count >= 2 else { return nil }
        let candidate = Array(c)
        var index = 0
        var gaps = 0
        var lastMatch: Int?
        for character in q {
            var found = false
            while index < candidate.count {
                defer { index += 1 }
                if candidate[index] == character {
                    if let lastMatch { gaps += index - lastMatch - 1 }
                    lastMatch = index
                    found = true
                    break
                }
            }
            if !found { return nil }
        }
        let penalty = Double(gaps) / Double(max(candidate.count, 1))
        return max(0.15, 0.45 - penalty * 0.5)
    }
}
