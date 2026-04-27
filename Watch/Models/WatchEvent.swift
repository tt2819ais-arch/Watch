import Foundation

/// One viewing event recorded for statistics.
struct WatchEvent: Codable, Hashable, Identifiable {
    let id: UUID
    let itemID: String
    let itemTitle: String
    let kind: ContentKind
    let episodeNumber: Int
    /// Watched seconds during this session (incremental, not cumulative position).
    let watchedSeconds: Double
    let timestamp: Date

    init(
        id: UUID = UUID(),
        itemID: String,
        itemTitle: String,
        kind: ContentKind,
        episodeNumber: Int,
        watchedSeconds: Double,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.itemID = itemID
        self.itemTitle = itemTitle
        self.kind = kind
        self.episodeNumber = episodeNumber
        self.watchedSeconds = watchedSeconds
        self.timestamp = timestamp
    }
}
