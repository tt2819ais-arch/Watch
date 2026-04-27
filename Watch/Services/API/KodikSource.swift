import Foundation

/// Kodik source — anime + movies + series. Requires an API token, which the
/// user provides in Settings. If no token is set, the source acts as a no-op
/// (returns empty results) but does not throw.
///
/// Docs: https://kodikapi.com/
final class KodikSource: ContentSource, @unchecked Sendable {
    let id = "kodik"
    let displayName = "Kodik"

    private let baseURL = URL(string: "https://kodikapi.com")!

    func supports(_ kind: ContentKind) -> Bool { true }

    private var token: String? {
        let raw = UserDefaults.standard.string(forKey: "kodik.token") ?? ""
        return raw.isEmpty ? nil : raw
    }

    // MARK: - Public

    func suggest(query: String, kind: ContentKind) async throws -> [ContentItem] {
        guard token != nil, !query.isEmpty else { return [] }
        return try await searchKodik(query: query, kind: kind, limit: 8)
    }

    func search(filter: CatalogFilter, kind: ContentKind, page: Int) async throws -> [ContentItem] {
        guard token != nil else { return [] }
        if !filter.query.isEmpty {
            return try await searchKodik(query: filter.query, kind: kind, limit: 50)
        }
        return try await listKodik(filter: filter, kind: kind, page: page)
    }

    func popular(kind: ContentKind, limit: Int) async throws -> [ContentItem] {
        guard token != nil else { return [] }
        return try await listKodik(filter: CatalogFilter(), kind: kind, page: 1, limit: limit)
    }

    func episodes(for item: ContentItem) async throws -> [Episode] {
        guard item.sourceID == id, let token else { return [] }
        var comps = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        let parts = item.id.split(separator: "|")
        guard parts.count == 3 else { return [] }
        let originalID = String(parts[2])
        comps.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "id", value: originalID),
            URLQueryItem(name: "with_episodes", value: "true"),
            URLQueryItem(name: "with_seasons", value: "true")
        ]
        guard let url = comps.url else { return [] }
        let resp: KodikSearchResponse = try await HTTPClient.shared.get(url, as: KodikSearchResponse.self)
        guard let first = resp.results.first else { return [] }
        return mapEpisodes(first)
    }

    func genres(kind: ContentKind) async throws -> [Genre] {
        guard let token else { return [] }
        var comps = URLComponents(url: baseURL.appendingPathComponent("genres"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "types", value: kindToTypes(kind))
        ]
        guard let url = comps.url else { return [] }
        let resp: KodikGenresResponse = try await HTTPClient.shared.get(url, as: KodikGenresResponse.self)
        return resp.results.map { Genre(id: $0.title.lowercased(), name: $0.title) }
    }

    // MARK: - Helpers

    private func searchKodik(query: String, kind: ContentKind, limit: Int) async throws -> [ContentItem] {
        guard let token else { return [] }
        var comps = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "title", value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "types", value: kindToTypes(kind)),
            URLQueryItem(name: "with_material_data", value: "true")
        ]
        guard let url = comps.url else { return [] }
        let resp: KodikSearchResponse = try await HTTPClient.shared.get(url, as: KodikSearchResponse.self)
        return resp.results.map(mapItem(_:))
    }

    private func listKodik(filter: CatalogFilter, kind: ContentKind, page: Int, limit: Int = 30) async throws -> [ContentItem] {
        guard let token else { return [] }
        var comps = URLComponents(url: baseURL.appendingPathComponent("list"), resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "types", value: kindToTypes(kind)),
            URLQueryItem(name: "with_material_data", value: "true"),
            URLQueryItem(name: "sort", value: kodikSort(filter.sort))
        ]
        if let from = filter.yearFrom, let to = filter.yearTo {
            query.append(URLQueryItem(name: "year", value: "\(from)-\(to)"))
        } else if let from = filter.yearFrom {
            query.append(URLQueryItem(name: "year", value: "\(from)"))
        }
        if !filter.genres.isEmpty {
            query.append(URLQueryItem(name: "genres", value: filter.genres.joined(separator: ",")))
        }
        comps.queryItems = query
        guard let url = comps.url else { return [] }
        let resp: KodikSearchResponse = try await HTTPClient.shared.get(url, as: KodikSearchResponse.self)
        return resp.results.map(mapItem(_:))
    }

    private func kindToTypes(_ kind: ContentKind) -> String {
        switch kind {
        case .anime:  return "anime,anime-serial"
        case .movie:  return "foreign-movie,russian-movie,soviet-cartoon,foreign-cartoon,russian-cartoon"
        case .series: return "foreign-tv-show,russian-tv-show,soviet-tv-show,documentary-tv-show"
        }
    }

    private func kodikSort(_ s: CatalogFilter.Sort) -> String {
        switch s {
        case .popularity: return "shikimori_rating"
        case .recent:     return "updated_at"
        case .year:       return "year"
        case .rating:     return "kinopoisk_rating"
        case .name:       return "title"
        }
    }

    // MARK: - Mapping

    private func mapItem(_ r: KodikResult) -> ContentItem {
        let kind: ContentKind = {
            if r.type?.contains("anime") == true { return .anime }
            if r.type?.contains("movie") == true { return .movie }
            return .series
        }()
        let poster: URL? = r.materialData?.posterURL.flatMap { URL(string: $0) }
        return ContentItem(
            id: ContentItem.makeID(sourceID: id, kind: kind, originalID: r.id ?? ""),
            sourceID: id,
            kind: kind,
            title: r.title ?? r.titleOrig ?? "—",
            originalTitle: r.titleOrig,
            descriptionText: r.materialData?.description,
            posterURL: poster,
            bannerURL: poster,
            year: r.year,
            genres: r.materialData?.allGenres ?? [],
            rating: r.materialData?.shikimoriRating ?? r.materialData?.kinopoiskRating,
            durationMinutes: r.materialData?.duration,
            totalEpisodes: r.lastEpisode
        )
    }

    /// Kodik returns embed iframe URLs, not direct video files. Real apps wrap
    /// Kodik via WebView. For the stubbed implementation we expose the iframe
    /// URL as a single source of unknown quality. Player will fall back to
    /// a built-in WebView player when scheme is `https` but file is HTML.
    private func mapEpisodes(_ r: KodikResult) -> [Episode] {
        var episodes: [Episode] = []
        guard let link = r.link, let baseURL = URL(string: link.hasPrefix("http") ? link : "https:\(link)") else {
            return []
        }
        let voice = VoiceTrack(
            id: "kodik-\(r.translation?.id ?? 0)",
            studio: r.translation?.title ?? "Kodik",
            language: "ru"
        )
        if let s = r.seasons {
            for (_, season) in s.sorted(by: { ($0.key) < ($1.key) }) {
                guard let eps = season.episodes else { continue }
                for (epKey, _) in eps.sorted(by: { ($0.key) < ($1.key) }) {
                    let n = Int(epKey) ?? episodes.count + 1
                    episodes.append(Episode(
                        id: "s\(season.title ?? "1")e\(n)",
                        number: n,
                        title: nil,
                        durationSeconds: nil,
                        thumbnailURL: nil,
                        sources: [VideoSource(id: "kodik", url: baseURL, quality: .hd, voiceTrack: voice, headers: [:])]
                    ))
                }
            }
        } else {
            // Single movie / single video.
            episodes.append(Episode(
                id: "1",
                number: 1,
                title: nil,
                durationSeconds: r.materialData?.duration.map { $0 * 60 },
                thumbnailURL: nil,
                sources: [VideoSource(id: "kodik", url: baseURL, quality: .hd, voiceTrack: voice, headers: [:])]
            ))
        }
        return episodes
    }
}

// MARK: - DTOs

private struct KodikSearchResponse: Decodable {
    let results: [KodikResult]
}

private struct KodikResult: Decodable {
    let id: String?
    let title: String?
    let titleOrig: String?
    let type: String?
    let year: Int?
    let link: String?
    let lastEpisode: Int?
    let translation: KodikTranslation?
    let materialData: KodikMaterialData?
    let seasons: [String: KodikSeason]?
}

private struct KodikTranslation: Decodable {
    let id: Int?
    let title: String?
}

private struct KodikSeason: Decodable {
    let title: String?
    let episodes: [String: String]?
}

private struct KodikMaterialData: Decodable {
    let posterURL: String?
    let description: String?
    let shikimoriRating: Double?
    let kinopoiskRating: Double?
    let duration: Int?
    let allGenres: [String]?
}

private struct KodikGenresResponse: Decodable {
    let results: [KodikGenre]
}

private struct KodikGenre: Decodable {
    let title: String
}
