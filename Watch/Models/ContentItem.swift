import Foundation

/// Unified content item. Used for anime, movies and series.
struct ContentItem: Identifiable, Codable, Hashable {
    /// Stable composite ID (sourceID + kind + originalID).
    let id: String
    let sourceID: String
    let kind: ContentKind

    let title: String
    let originalTitle: String?
    let descriptionText: String?
    let posterURL: URL?
    let bannerURL: URL?

    let year: Int?
    let genres: [String]
    let rating: Double?
    let durationMinutes: Int?
    let totalEpisodes: Int?

    /// Used for type-ahead search highlighting and ordering.
    var searchTokens: [String] {
        var t: [String] = []
        t.append(title.lowercased())
        if let o = originalTitle?.lowercased() { t.append(o) }
        return t
    }
}

extension ContentItem {
    static func makeID(sourceID: String, kind: ContentKind, originalID: String) -> String {
        "\(sourceID)|\(kind.rawValue)|\(originalID)"
    }
}
