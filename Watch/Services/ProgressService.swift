import Foundation
import Combine

@MainActor
final class ProgressService: ObservableObject {
    static let shared = ProgressService()

    @Published private(set) var byItemEpisode: [String: WatchProgress] = [:]
    @Published private(set) var lastWatched: [WatchProgress] = []

    private let key = "watch_progress"

    private init() {
        let loaded = PersistenceService.shared.load([WatchProgress].self, key: key) ?? []
        for p in loaded { byItemEpisode[p.id] = p }
        rebuildLastWatched()
        Logger.shared.info("Loaded \(loaded.count) progress entries", category: .persistence)
    }

    func progress(for itemID: String, episodeID: String) -> WatchProgress? {
        byItemEpisode["\(itemID)::\(episodeID)"]
    }

    /// Latest progress for an item across all its episodes (for the Continue Watching card).
    func latestProgress(for itemID: String) -> WatchProgress? {
        byItemEpisode.values
            .filter { $0.itemID == itemID }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    func update(itemID: String, episodeID: String, episodeNumber: Int, position: Double, duration: Double) {
        let key = "\(itemID)::\(episodeID)"
        var p = byItemEpisode[key] ?? WatchProgress(
            itemID: itemID,
            episodeID: episodeID,
            episodeNumber: episodeNumber,
            position: 0,
            duration: 0,
            updatedAt: Date()
        )
        p.position = position
        if duration > 0 { p.duration = duration }
        p.updatedAt = Date()
        byItemEpisode[key] = p
        persist()
        rebuildLastWatched()
    }

    func clearAll() {
        byItemEpisode.removeAll()
        persist()
        rebuildLastWatched()
    }

    private func rebuildLastWatched() {
        lastWatched = byItemEpisode.values
            .filter { !$0.isFinished }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        let arr = Array(byItemEpisode.values)
        PersistenceService.shared.save(arr, key: key)
    }
}
