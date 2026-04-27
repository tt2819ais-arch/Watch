import Foundation

/// Protocol every content provider (Anilibria / Kodik / etc.) implements.
/// All methods are async and may throw.
protocol ContentSource: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// Whether this source can serve the given content kind.
    func supports(_ kind: ContentKind) -> Bool

    /// Type-ahead search hints (lightweight, no full episode list).
    func suggest(query: String, kind: ContentKind) async throws -> [ContentItem]

    /// Full search with filters & sorting.
    func search(filter: CatalogFilter, kind: ContentKind, page: Int) async throws -> [ContentItem]

    /// Curated/popular feed for the home page.
    func popular(kind: ContentKind, limit: Int) async throws -> [ContentItem]

    /// Loads episodes + sources for a given item.
    func episodes(for item: ContentItem) async throws -> [Episode]

    /// All known genres (kind-specific).
    func genres(kind: ContentKind) async throws -> [Genre]
}

@MainActor
final class ContentSourceRegistry: ObservableObject {
    static let shared = ContentSourceRegistry()

    @Published private(set) var sources: [ContentSource] = []

    private init() {
        // Default registrations:
        //   - AniLibria: free anime metadata + HLS streams.
        //   - PoiskKino: rich movie/series metadata (Kinopoisk + TMDb + IMDb).
        //   - Kodik:     stream provider for everything; metadata fallback.
        sources = [
            AnilibriaSource(),
            PoiskKinoSource(),
            KodikSource()
        ]
        Logger.shared.info("Registered \(sources.count) content sources", category: .source)
    }

    func sources(for kind: ContentKind) -> [ContentSource] {
        sources.filter { $0.supports(kind) }
    }

    /// Aggregates results across all sources that support the given kind.
    func aggregate(_ work: @escaping @Sendable (ContentSource) async throws -> [ContentItem], for kind: ContentKind) async -> [ContentItem] {
        let active = sources(for: kind)
        return await withTaskGroup(of: [ContentItem].self) { group in
            for src in active {
                group.addTask {
                    do { return try await work(src) }
                    catch {
                        await MainActor.run {
                            Logger.shared.warn("Source \(src.id) failed: \(error)", category: .source)
                        }
                        return []
                    }
                }
            }
            var all: [ContentItem] = []
            for await items in group { all.append(contentsOf: items) }
            return Self.dedup(all)
        }
    }

    static func dedup(_ items: [ContentItem]) -> [ContentItem] {
        var seen = Set<String>()
        var out: [ContentItem] = []
        for it in items {
            // Dedup primarily by lowercased title + year so that the same
            // anime from two sources doesn't appear twice.
            let key = "\(it.kind.rawValue)|\(it.title.lowercased())|\(it.year ?? 0)"
            if !seen.contains(key) {
                seen.insert(key)
                out.append(it)
            }
        }
        return out
    }
}
