import Foundation

/// Ranks things the user opens often and recently higher.
final class Frecency {
    private let key = DefaultsKey.frecency
    private var table: [String: [Double]]

    init() {
        table = UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]] ?? [:]
    }

    func record(_ id: String) {
        let entry = table[id] ?? [0, 0]
        table[id] = [entry[0] + 1, Date().timeIntervalSince1970]
        UserDefaults.standard.set(table, forKey: key)
    }

    /// 0 for never used, up to about 0.3 for a daily habit.
    func boost(_ id: String) -> Double {
        guard let entry = table[id] else { return 0 }
        let days = (Date().timeIntervalSince1970 - entry[1]) / 86400
        let recency = days < 1 ? 1 : days < 7 ? 0.7 : days < 30 ? 0.4 : 0.2
        return min(0.3, log(1 + entry[0]) * 0.08) * recency
    }

    func top(_ limit: Int, among ids: Set<String>) -> [String] {
        table.filter { ids.contains($0.key) }
            .sorted { boost($0.key) > boost($1.key) }
            .prefix(limit).map(\.key)
    }

    /// The most recently opened of `ids`.
    func last(among ids: Set<String>) -> String? {
        table.filter { ids.contains($0.key) }.max { $0.value[1] < $1.value[1] }?.key
    }

    /// The most often opened of `ids`, ties going to the more recent.
    func mostUsed(_ limit: Int, among ids: Set<String>) -> [String] {
        table.filter { ids.contains($0.key) }
            .sorted { ($0.value[0], $0.value[1]) > ($1.value[0], $1.value[1]) }
            .prefix(limit).map(\.key)
    }
}
