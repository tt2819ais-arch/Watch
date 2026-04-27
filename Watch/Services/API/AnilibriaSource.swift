import Foundation

/// Anilibria source — anime only, free public API.
/// Docs: https://github.com/anilibria/docs/blob/master/api_v3.md
final class AnilibriaSource: ContentSource, @unchecked Sendable {
    let id = "anilibria"
    let displayName = "AniLibria"

    private let baseURL = URL(string: "https://api.anilibria.tv/v3")!
    private let cdnHost = "https://cache.libria.fun"

    func supports(_ kind: ContentKind) -> Bool { kind == .anime }

    // MARK: - Public API

    func suggest(query: String, kind: ContentKind) async throws -> [ContentItem] {
        guard kind == .anime, !query.isEmpty else { return [] }
        return try await search(query: query, limit: 8)
    }

    func search(filter: CatalogFilter, kind: ContentKind, page: Int) async throws -> [ContentItem] {
        guard kind == .anime else { return [] }
        if !filter.query.isEmpty {
            return try await search(query: filter.query, limit: 50)
        }
        // No query → use updates feed with simple client-side filtering.
        let titles = try await titleUpdates(page: page, itemsPerPage: 30)
        return applyFilter(titles, filter: filter)
    }

    func popular(kind: ContentKind, limit: Int) async throws -> [ContentItem] {
        guard kind == .anime else { return [] }
        let titles = try await titleUpdates(page: 1, itemsPerPage: limit)
        return titles
    }

    func episodes(for item: ContentItem) async throws -> [Episode] {
        guard item.sourceID == id else { return [] }
        let parts = item.id.split(separator: "|")
        guard parts.count == 3, let titleID = Int(parts[2]) else { return [] }
        let dto = try await fetchTitle(id: titleID)
        return mapEpisodes(dto)
    }

    func genres(kind: ContentKind) async throws -> [Genre] {
        guard kind == .anime else { return [] }
        var comps = URLComponents(url: baseURL.appendingPathComponent("genres"), resolvingAgainstBaseURL: false)!
        comps.queryItems = []
        guard let url = comps.url else { return [] }
        struct Resp: Decodable {}
        // /v3/genres returns just an array of strings.
        let data: [String] = try await HTTPClient.shared.get(url, as: [String].self)
        return data.map { Genre(id: $0.lowercased(), name: $0) }
    }

    // MARK: - Internals

    private func search(query: String, limit: Int) async throws -> [ContentItem] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("title/search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "filter", value: "id,code,names,description,posters,type,year,genres,season,player,status")
        ]
        guard let url = comps.url else { throw HTTPError.invalidURL }
        let resp: AnilibriaSearchResponse = try await HTTPClient.shared.get(url, as: AnilibriaSearchResponse.self)
        return resp.list.map(mapTitle)
    }

    private func titleUpdates(page: Int, itemsPerPage: Int) async throws -> [ContentItem] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("title/updates"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "limit", value: "\(itemsPerPage)"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "filter", value: "id,code,names,description,posters,type,year,genres,season,player,status")
        ]
        guard let url = comps.url else { throw HTTPError.invalidURL }
        let resp: AnilibriaSearchResponse = try await HTTPClient.shared.get(url, as: AnilibriaSearchResponse.self)
        return resp.list.map(mapTitle)
    }

    private func fetchTitle(id: Int) async throws -> AnilibriaTitle {
        var comps = URLComponents(url: baseURL.appendingPathComponent("title"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "id", value: "\(id)"),
            URLQueryItem(name: "filter", value: "id,code,names,description,posters,type,year,genres,season,player,status")
        ]
        guard let url = comps.url else { throw HTTPError.invalidURL }
        return try await HTTPClient.shared.get(url, as: AnilibriaTitle.self)
    }

    // MARK: - Mapping

    private func mapTitle(_ t: AnilibriaTitle) -> ContentItem {
        let posterPath = t.posters?.medium?.url ?? t.posters?.original?.url ?? t.posters?.small?.url
        let posterURL = posterPath.flatMap { URL(string: cdnHost + $0) }
        let bannerURL = t.posters?.original?.url.flatMap { URL(string: cdnHost + $0) }
        return ContentItem(
            id: ContentItem.makeID(sourceID: id, kind: .anime, originalID: "\(t.id ?? 0)"),
            sourceID: id,
            kind: .anime,
            title: t.names?.ru ?? t.names?.en ?? "—",
            originalTitle: t.names?.en,
            descriptionText: t.description,
            posterURL: posterURL,
            bannerURL: bannerURL,
            year: t.season?.year,
            genres: t.genres ?? [],
            rating: nil,
            durationMinutes: nil,
            totalEpisodes: t.player?.episodes?.last
        )
    }

    private func mapEpisodes(_ t: AnilibriaTitle) -> [Episode] {
        guard let player = t.player, let host = player.host, let list = player.list else { return [] }
        let sortedKeys = list.keys.compactMap { Int($0) }.sorted()
        return sortedKeys.compactMap { numKey -> Episode? in
            guard let ep = list["\(numKey)"] else { return nil }
            return mapEpisode(ep, host: host)
        }
    }

    private func mapEpisode(_ ep: AnilibriaEpisode, host: String) -> Episode? {
        var sources: [VideoSource] = []
        let voice = VoiceTrack(id: "anilibria-ru", studio: "AniLibria", language: "ru")
        let baseHost = host.hasPrefix("http") ? host : "https://\(host)"
        if let hls = ep.hls {
            if let p = hls.fhd, let url = URL(string: baseHost + p) {
                sources.append(VideoSource(id: "fhd", url: url, quality: .fhd, voiceTrack: voice, headers: [:]))
            }
            if let p = hls.hd, let url = URL(string: baseHost + p) {
                sources.append(VideoSource(id: "hd", url: url, quality: .hd, voiceTrack: voice, headers: [:]))
            }
            if let p = hls.sd, let url = URL(string: baseHost + p) {
                sources.append(VideoSource(id: "sd", url: url, quality: .sd, voiceTrack: voice, headers: [:]))
            }
        }
        guard !sources.isEmpty else { return nil }
        let durationSec = ep.duration.map { Int($0) }
        return Episode(
            id: "\(ep.episode ?? 0)",
            number: Int(ep.episode ?? 0),
            title: ep.name,
            durationSeconds: durationSec,
            thumbnailURL: nil,
            sources: sources
        )
    }

    // MARK: - Filtering

    private func applyFilter(_ items: [ContentItem], filter: CatalogFilter) -> [ContentItem] {
        items.filter { item in
            if !filter.query.isEmpty {
                if !item.title.lowercased().contains(filter.query.lowercased()) { return false }
            }
            if let from = filter.yearFrom, let y = item.year, y < from { return false }
            if let to = filter.yearTo, let y = item.year, y > to { return false }
            if !filter.genres.isEmpty {
                let lower = item.genres.map { $0.lowercased() }
                if !filter.genres.contains(where: { lower.contains($0.lowercased()) }) {
                    return false
                }
            }
            return true
        }
    }
}

// MARK: - DTOs

private struct AnilibriaSearchResponse: Decodable {
    let list: [AnilibriaTitle]
}

private struct AnilibriaTitle: Decodable {
    let id: Int?
    let code: String?
    let names: AnilibriaNames?
    let description: String?
    let posters: AnilibriaPosters?
    let year: Int?
    let genres: [String]?
    let season: AnilibriaSeason?
    let player: AnilibriaPlayer?
    let status: AnilibriaStatus?
}

private struct AnilibriaStatus: Decodable {
    let string: String?
}

private struct AnilibriaNames: Decodable {
    let ru: String?
    let en: String?
}

private struct AnilibriaPosters: Decodable {
    let small: AnilibriaPoster?
    let medium: AnilibriaPoster?
    let original: AnilibriaPoster?
}

private struct AnilibriaPoster: Decodable {
    let url: String
}

private struct AnilibriaSeason: Decodable {
    let year: Int?
    let weekDay: Int?
    let string: String?

    enum CodingKeys: String, CodingKey {
        case year
        case weekDay = "week_day"
        case string
    }
}

private struct AnilibriaPlayer: Decodable {
    let host: String?
    let episodes: AnilibriaPlayerEpisodes?
    let list: [String: AnilibriaEpisode]?
}

private struct AnilibriaPlayerEpisodes: Decodable {
    let first: Int?
    let last: Int?
    let string: String?
}

private struct AnilibriaEpisode: Decodable {
    let episode: Double?
    let name: String?
    let uuid: String?
    let createdTimestamp: Int?
    let preview: String?
    let skips: AnilibriaSkips?
    let hls: AnilibriaHLS?
    let duration: Double?
}

private struct AnilibriaSkips: Decodable {}

private struct AnilibriaHLS: Decodable {
    let sd: String?
    let hd: String?
    let fhd: String?
}
