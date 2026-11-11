import Foundation

struct EmojiEntry {
    let character: String
    let name: String
}

/// Emoji built from Unicode scalar properties, so no data file is needed.
enum EmojiCatalog {
    static let all: [EmojiEntry] = {
        // Smileys first, then the rest of the emoji blocks.
        let blocks: [ClosedRange<UInt32>] = [
            0x1F600...0x1F64F, 0x1F900...0x1F9FF, 0x1F300...0x1F5FF, 0x1F680...0x1F6FF,
            0x1FA70...0x1FAFF, 0x1F7E0...0x1F7EB, 0x2600...0x27BF, 0x2B00...0x2BFF,
        ]
        var seen = Set<String>()
        var result: [EmojiEntry] = []
        for range in blocks {
            for value in range {
                guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation,
                      !(0x1F3FB...0x1F3FF).contains(value), let name = scalar.properties.name else { continue }
                let character = String(scalar)
                guard seen.insert(character).inserted else { continue }
                result.append(EmojiEntry(character: character, name: name.lowercased().capitalized))
            }
        }
        // Text-default symbols people still expect, shown with the emoji variation selector.
        for value: UInt32 in [0x2764, 0x2600, 0x2601, 0x2744, 0x260E, 0x2702, 0x2708, 0x270C, 0x270F, 0x2714, 0x2716, 0x2728, 0x2B50, 0x203C, 0x2049] {
            guard let scalar = Unicode.Scalar(value), let name = scalar.properties.name else { continue }
            let character = String(scalar) + "\u{FE0F}"
            guard seen.insert(String(scalar)).inserted, seen.insert(character).inserted else { continue }
            result.append(EmojiEntry(character: character, name: name.lowercased().capitalized))
        }
        return result
    }()

    /// Extra search words for the most common emoji.
    static let keywords: [String: [String]] = [
        "😂": ["lol", "laugh", "haha"], "❤️": ["love", "heart"], "👍": ["yes", "ok", "approve", "+1"],
        "🎉": ["party", "celebrate", "tada"], "🔥": ["fire", "lit", "hot"], "🙏": ["please", "thanks", "pray"],
        "😭": ["cry", "sad"], "🤔": ["think", "hmm"], "👀": ["eyes", "look"], "✅": ["done", "check"],
        "🚀": ["launch", "ship", "rocket"], "💀": ["dead", "skull"], "😅": ["sweat", "oops"], "🥲": ["smile tear"],
        "🫠": ["melt"], "💯": ["hundred", "perfect"], "🙃": ["upside"], "😎": ["cool", "sunglasses"],
    ]
}
