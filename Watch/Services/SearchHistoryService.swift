import Foundation
import Combine

/// Stores the last N user search queries in UserDefaults.
@MainActor
final class SearchHistoryService: ObservableObject {
    static let shared = SearchHistoryService()
    private static let key = "search.history"
    private static let maxItems = 12

    @Published private(set) var queries: [String] = []

    private init() {
        if let raw = UserDefaults.standard.array(forKey: Self.key) as? [String] {
            queries = raw
        }
    }

    func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        var next = queries.filter { $0.lowercased() != trimmed.lowercased() }
        next.insert(trimmed, at: 0)
        if next.count > Self.maxItems { next = Array(next.prefix(Self.maxItems)) }
        queries = next
        persist()
    }

    func remove(_ query: String) {
        queries.removeAll { $0 == query }
        persist()
    }

    func clear() {
        queries = []
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(queries, forKey: Self.key)
    }
}
