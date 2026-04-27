import Foundation

/// AniLibria v1 (anilibria.top) — free public anime API.
/// Base URL: https://anilibria.top/api/v1
/// Storage host: https://anilibria.top (poster/preview paths are relative).
final class AnilibriaSource: ContentSource, @unchecked Sendable {
    let id: String = "anilibria"
    let displayName: String = "AniLibria"

    private let host = URL(string: "https://anilibria.top")!
    private let api  = URL(string: "https://anilibria.top/api/v1")!

    func supports(_ kind: ContentKind) -> Bool {
        kind == .anime
    }

    // MARK: - Suggestions / search

    func suggest(query: String, kind: ContentKind) async throws -> [ContentItem] {
        guard kind == .anime, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return try await search(query: query)
    }

    func search(filter: CatalogFilter, kind: ContentKind, page: Int) async throws -> [ContentItem] {
        guard kind == .anime else { return [] }
        if !filter.query.trimmingCharacters(in: .whitespaces).isEmpty {
            // Search endpoint doesn't support filters; client-side filter on top of it.
            let raw = try await search(query: filter.query)
            return apply(filter: filter, to: raw)
        }
        return try await catalog(filter: filter, page: page)
    }

    func popular(kind: ContentKind, limit: Int) async throws -> [ContentItem] {
        guard kind == .anime else { return [] }
        var components = URLComponents(url: api.appendingPathComponent("anime/catalog/releases"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        let resp: ReleaseListEnvelope = try await HTTPClient.shared.get(components.url!, as: ReleaseListEnvelope.self)
        return resp.data.map { mapToItem($0) }
    }

    // MARK: - Detail / episodes

    func episodes(for item: ContentItem) async throws -> [Episode] {
        guard let alias = aliasFromItemID(item.id) else { return [] }
        let url = api.appendingPathComponent("anime/releases/\(alias)")
        let detail: ReleaseDetail = try await HTTPClient.shared.get(url, as: ReleaseDetail.self)
        return detail.episodes.map { mapEpisode($0) }
    }

    func genres(kind: ContentKind) async throws -> [Genre] {
        guard kind == .anime else { return [] }
        let url = api.appendingPathComponent("anime/genres")
        let arr: [GenreDTO] = try await HTTPClient.shared.get(url, as: [GenreDTO].self)
        return arr.map { Genre(id: String($0.id), name: $0.name) }
    }

    // MARK: - Internals

    private func search(query: String) async throws -> [ContentItem] {
        var c = URLComponents(url: api.appendingPathComponent("app/search/releases"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "query", value: query)]
        let raw: [ReleaseDTO] = try await HTTPClient.shared.get(c.url!, as: [ReleaseDTO].self)
        return raw.map { mapToItem($0) }
    }

    private func catalog(filter: CatalogFilter, page: Int) async throws -> [ContentItem] {
        var c = URLComponents(url: api.appendingPathComponent("anime/catalog/releases"),
                              resolvingAgainstBaseURL: false)!
        var qi: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "limit", value: "30")
        ]
        if let from = filter.yearFrom { qi.append(URLQueryItem(name: "f[years][from_year]", value: String(from))) }
        if let to = filter.yearTo   { qi.append(URLQueryItem(name: "f[years][to_year]",   value: String(to))) }
        for g in filter.genres {
            qi.append(URLQueryItem(name: "f[genres][]", value: g))
        }
        c.queryItems = qi
        let resp: ReleaseListEnvelope = try await HTTPClient.shared.get(c.url!, as: ReleaseListEnvelope.self)
        return resp.data.map { mapToItem($0) }
    }

    private func apply(filter: CatalogFilter, to items: [ContentItem]) -> [ContentItem] {
        var arr = items
        if let from = filter.yearFrom { arr = arr.filter { ($0.year ?? 0) >= from } }
        if let to = filter.yearTo   { arr = arr.filter { ($0.year ?? 9999) <= to } }
        if !filter.genres.isEmpty {
            arr = arr.filter { item in
                !item.genres.isEmpty && filter.genres.allSatisfy { wanted in item.genres.contains { $0.localizedCaseInsensitiveContains(wanted) } }
            }
        }
        return arr
    }

    private func aliasFromItemID(_ id: String) -> String? {
        // Composite id format: "anilibria|anime|<alias>"
        let parts = id.split(separator: "|")
        guard parts.count == 3, parts[0] == "anilibria" else { return nil }
        return String(parts[2])
    }

    private func mapToItem(_ r: ReleaseDTO) -> ContentItem {
        let absPoster = r.poster?.optimized?.src ?? r.poster?.src
        let posterURL = absPoster.flatMap { absoluteURL($0) }
        return ContentItem(
            id: ContentItem.makeID(sourceID: id, kind: .anime, originalID: r.alias),
            sourceID: id,
            kind: .anime,
            title: r.name?.main ?? r.alias,
            originalTitle: r.name?.english,
            descriptionText: r.description,
            posterURL: posterURL,
            bannerURL: posterURL,
            year: r.year,
            genres: [],   // catalog/list response does not include genres for each item
            rating: nil,
            durationMinutes: nil,
            totalEpisodes: r.episodesTotal
        )
    }

    private func mapEpisode(_ dto: EpisodeDTO) -> Episode {
        let voice = VoiceTrack(id: "anilibria_ru", studio: "AniLibria", language: "RU")
        var sources: [VideoSource] = []
        if let s = dto.hls480, let u = stripAds(s) {
            sources.append(VideoSource(id: "\(dto.id)_sd", url: u, quality: .sd, voiceTrack: voice, headers: [:]))
        }
        if let s = dto.hls720, let u = stripAds(s) {
            sources.append(VideoSource(id: "\(dto.id)_hd", url: u, quality: .hd, voiceTrack: voice, headers: [:]))
        }
        if let s = dto.hls1080, let u = stripAds(s) {
            sources.append(VideoSource(id: "\(dto.id)_fhd", url: u, quality: .fhd, voiceTrack: voice, headers: [:]))
        }
        let thumb = dto.preview?.optimized?.src ?? dto.preview?.src
        return Episode(
            id: dto.id,
            number: dto.ordinal ?? dto.sortOrder ?? 0,
            title: dto.name,
            durationSeconds: dto.duration,
            thumbnailURL: thumb.flatMap { absoluteURL($0) },
            sources: sources,
            openingStart: dto.opening?.start,
            openingStop: dto.opening?.stop,
            endingStart: dto.ending?.start,
            endingStop: dto.ending?.stop
        )
    }

    /// Override `isWithVideoAds=1` -> 0, removing the AniLibria video ad insertion
    /// the user explicitly asked to be cut.
    private func stripAds(_ rawURL: String) -> URL? {
        guard var c = URLComponents(string: rawURL) else { return URL(string: rawURL) }
        c.queryItems = c.queryItems?.map { item in
            if item.name == "isWithVideoAds" || item.name == "isWithVideoAdsAlways" {
                return URLQueryItem(name: item.name, value: "0")
            }
            return item
        }
        return c.url
    }

    private func absoluteURL(_ path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        return URL(string: path, relativeTo: host)?.absoluteURL
    }
}

// MARK: - DTOs

private struct ReleaseListEnvelope: Decodable {
    let data: [ReleaseDTO]
    let meta: MetaDTO?
}

private struct MetaDTO: Decodable {
    let pagination: Pagination?
    struct Pagination: Decodable {
        let total: Int?
        let currentPage: Int?
        let totalPages: Int?
    }
}

private struct ReleaseDTO: Decodable {
    let id: Int
    let alias: String
    let year: Int?
    let name: NameDTO?
    let poster: PosterDTO?
    let description: String?
    let episodesTotal: Int?
    let episodes: [EpisodeDTO]?
}

private struct NameDTO: Decodable {
    let main: String?
    let english: String?
    let alternative: String?
}

private struct PosterDTO: Decodable {
    let src: String?
    let optimized: OptimizedSrc?
}

private struct EpisodeDTO: Decodable {
    let id: String
    let name: String?
    let ordinal: Int?
    let sortOrder: Int?
    let duration: Int?
    let preview: PreviewDTO?
    let hls480: String?
    let hls720: String?
    let hls1080: String?
    let opening: TimeRangeDTO?
    let ending: TimeRangeDTO?
}

private struct TimeRangeDTO: Decodable {
    let start: Double?
    let stop: Double?
}

private struct PreviewDTO: Decodable {
    let src: String?
    let optimized: OptimizedSrc?
}

private struct OptimizedSrc: Decodable {
    let src: String?
}

private struct ReleaseDetail: Decodable {
    let id: Int
    let alias: String
    let episodes: [EpisodeDTO]
}

private struct GenreDTO: Decodable {
    let id: Int
    let name: String
}
