import Foundation
import Combine

@MainActor
final class FavoritesService: ObservableObject {
    static let shared = FavoritesService()

    @Published private(set) var items: [ContentItem] = []

    private let key = "favorites"

    private init() {
        items = PersistenceService.shared.load([ContentItem].self, key: key) ?? []
        Logger.shared.info("Loaded \(items.count) favorites", category: .persistence)
    }

    func isFavorite(_ id: String) -> Bool {
        items.contains(where: { $0.id == id })
    }

    func toggle(_ item: ContentItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: idx)
            Logger.shared.info("Removed favorite \(item.title)", category: .persistence)
        } else {
            items.insert(item, at: 0)
            Logger.shared.info("Added favorite \(item.title)", category: .persistence)
        }
        persist()
    }

    func remove(id: String) {
        items.removeAll(where: { $0.id == id })
        persist()
    }

    private func persist() {
        PersistenceService.shared.save(items, key: key)
    }
}
