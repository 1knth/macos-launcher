import AppKit
import PrismCore

/// The Search Google route: one row that opens the typed search.
final class GoogleResults: ResultProvider {
    func items(for query: String) -> [ResultItem] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return [singleActionItem("google.search", "Search Google for “\(text)”", "magnifyingglass", .blue, section: "Google") {
            WebSearch.openGoogle(text)
        }]
    }
}
