import Foundation

/// Text transforms applied to the clipboard's text.
public enum TextTransform: CaseIterable {
    case upper, lower, title, sentence, camel, snake, kebab, trim, sortLines, uniqueLines, reverseLines, base64Encode, base64Decode, urlEncode, urlDecode, jsonPretty, count

    public var title: String {
        switch self {
        case .upper: return "UPPERCASE"
        case .lower: return "lowercase"
        case .title: return "Title Case"
        case .sentence: return "Sentence case"
        case .camel: return "camelCase"
        case .snake: return "snake_case"
        case .kebab: return "kebab-case"
        case .trim: return "Trim Whitespace"
        case .sortLines: return "Sort Lines"
        case .uniqueLines: return "Remove Duplicate Lines"
        case .reverseLines: return "Reverse Lines"
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .urlEncode: return "URL Encode"
        case .urlDecode: return "URL Decode"
        case .jsonPretty: return "Format JSON"
        case .count: return "Count Characters & Words"
        }
    }

    public var symbol: String {
        switch self {
        case .upper, .lower, .title, .sentence: return "textformat"
        case .camel, .snake, .kebab: return "chevron.left.forwardslash.chevron.right"
        case .trim: return "scissors"
        case .sortLines, .uniqueLines, .reverseLines: return "list.bullet"
        case .base64Encode, .base64Decode, .urlEncode, .urlDecode: return "lock.doc"
        case .jsonPretty: return "curlybraces"
        case .count: return "number"
        }
    }

    public func apply(_ text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        switch self {
        case .upper: return text.uppercased()
        case .lower: return text.lowercased()
        case .title: return text.capitalized
        case .sentence: return text.prefix(1).uppercased() + text.dropFirst().lowercased()
        case .camel:
            let words = Self.words(text)
            guard let first = words.first else { return nil }
            return first.lowercased() + words.dropFirst().map(\.capitalized).joined()
        case .snake: return Self.words(text).map { $0.lowercased() }.joined(separator: "_")
        case .kebab: return Self.words(text).map { $0.lowercased() }.joined(separator: "-")
        case .trim: return lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        case .sortLines: return lines.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n")
        case .uniqueLines:
            var seen = Set<String>()
            return lines.filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .reverseLines: return lines.reversed().joined(separator: "\n")
        case .base64Encode: return Data(text.utf8).base64EncodedString()
        case .base64Decode:
            return Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { String(data: $0, encoding: .utf8) }
        case .urlEncode: return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?")))
        case .urlDecode: return text.removingPercentEncoding
        case .jsonPretty:
            guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]),
                  let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return nil }
            return String(data: data, encoding: .utf8)
        case .count:
            let words = text.split { $0.isWhitespace || $0.isNewline }.count
            return "\(text.count) characters · \(words) words · \(lines.count) lines"
        }
    }

    private static func words(_ text: String) -> [String] {
        // Split on separators and on lower→upper boundaries, so "fooBar baz" → foo, Bar, baz.
        var spaced = ""
        var previous: Character?
        for character in text {
            if let previous, previous.isLowercase, character.isUppercase { spaced.append(" ") }
            spaced.append(character)
            previous = character
        }
        return spaced.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
