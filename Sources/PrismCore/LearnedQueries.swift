import Foundation

/// Remembers which result was chosen for a typed query, so "sfi" keeps meaning Safari after
/// picking it once. The latest choice for a query wins; older ones keep a small boost.
public struct LearnedQueries: Codable, Equatable {
    struct Choice: Codable, Equatable {
        var count: Int
        var last: TimeInterval
    }

    private var table: [String: [String: Choice]] = [:]

    public init() {}

    public static func normalize(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespaces).lowercased()
    }

    public mutating func record(_ query: String, id: String, at date: Date = Date()) {
        let key = Self.normalize(query)
        guard !key.isEmpty else { return }
        var choices = table[key] ?? [:]
        let previous = choices[id]?.count ?? 0
        choices[id] = Choice(count: previous + 1, last: date.timeIntervalSince1970)
        table[key] = choices
    }

    public mutating func forget(_ query: String, id: String) {
        let key = Self.normalize(query)
        table[key]?[id] = nil
        if table[key]?.isEmpty == true { table[key] = nil }
    }

    /// The result chosen most recently for exactly this query.
    public func preferred(_ query: String) -> String? {
        table[Self.normalize(query)]?.max { $0.value.last < $1.value.last }?.key
    }

    /// Every id learned for this exact query, including ones the fuzzy matcher wouldn't find
    /// (aliases such as "web" for Safari).
    public func ids(for query: String) -> Set<String> {
        Set(table[Self.normalize(query)]?.keys.map { $0 } ?? [])
    }

    /// Score bonus: large for the preferred pick of this exact query, small for other picks of
    /// it, and smaller for picks of a longer query this one is still being typed toward.
    public func boost(_ query: String, id: String) -> Double {
        let key = Self.normalize(query)
        guard !key.isEmpty else { return 0 }
        if let choice = table[key]?[id] {
            return preferred(key) == id ? 2 : 0.2 + min(Double(choice.count), 5) * 0.04
        }
        let typedToward = table.contains { learned, choices in
            learned.count > key.count && learned.hasPrefix(key) && choices[id] != nil
        }
        return typedToward ? 0.15 : 0
    }

    public func isLearned(_ query: String, id: String) -> Bool {
        table[Self.normalize(query)]?[id] != nil
    }
}
