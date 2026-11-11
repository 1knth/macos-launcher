import Foundation

/// Root searches, newest first, recalled with ↑ from an empty search field.
final class SearchHistory {
    private let key = DefaultsKey.searchHistory
    private(set) var entries: [String]

    init() {
        entries = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func record(_ query: String) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        entries.removeAll { $0 == text }
        entries.insert(text, at: 0)
        entries = Array(entries.prefix(30))
        UserDefaults.standard.set(entries, forKey: key)
    }
}
