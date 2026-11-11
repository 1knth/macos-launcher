import Foundation
import PrismCore

/// Persists `LearnedQueries` in UserDefaults.
final class LearnedStore {
    private let key = DefaultsKey.learnedQueries
    private(set) var queries: LearnedQueries

    init() {
        queries = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(LearnedQueries.self, from: $0) } ?? LearnedQueries()
    }

    func record(_ query: String, id: String) {
        queries.record(query, id: id)
        save()
    }

    func forget(_ query: String, id: String) {
        queries.forget(query, id: id)
        save()
    }

    func reset() {
        queries = LearnedQueries()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(queries) { UserDefaults.standard.set(data, forKey: key) }
    }
}
