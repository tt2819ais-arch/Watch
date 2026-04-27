import Foundation

/// PoiskKino (api.poiskkino.dev) — Kinopoisk / TMDb / IMDb metadata aggregator
/// for movies and series. Auth via `X-API-KEY` header (token comes from
/// `AppSecrets.poiskkinoToken`, baked at build time from the GH secret).
///
/// PoiskKino provides metadata only — no playable streams. For actual playback
/// we hand off to KodikSource by `kinopoisk_id` once the user opens a detail
/// view.
final class PoiskKinoSource: ContentSource, @unchecked Sendable {
    let id: String = "poiskkino"
    let displayName: String = "ПоискКино"

    private let host = URL(string: "https://api.poiskkino.dev")!
    private let movieAPI = "/v1.4"
    private let metaAPI  = "/v1"

    func supports(_ kind: ContentKind) -> Bool {
        kind == .movie || kind == .series
    }

    // MARK: - ContentSource

    func suggest(query: String, kind: ContentKind) async throws -> [ContentItem] {
        guard supports(kind), AppSecrets.poiskkinoToken.isEmpty == false else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        var c = URLComponents(url: host.appendingPathComponent("\(movieAPI)/movie/search"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "query", value: trimmed)
        ]
        let env: PoiskKinoEnvelope = try await HTTPClient.shared.get(c.url!, as: PoiskKinoEnvelope.self, headers: authHeaders())
        return env.docs.compactMap { mapDoc($0) }.filter { $0.kind == kind }
    }

    func search(filter: CatalogFilter, kind: ContentKind, page: Int) async throws -> [ContentItem] {
        guard supports(kind), AppSecrets.poiskkinoToken.isEmpty == false else { return [] }
        if !filter.query.trimmingCharacters(in: .whitespaces).isEmpty {
            return try await suggest(query: filter.query, kind: kind)
        }
        var c = URLComponents(url: host.appendingPathComponent("\(movieAPI)/movie"),
                              resolvingAgainstBaseURL: false)!
        var qi: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "isSeries", value: kind == .series ? "true" : "false")
        ]
        if let from = filter.yearFrom, let to = filter.yearTo {
            qi.append(URLQueryItem(name: "year", value: "\(from)-\(to)"))
        } else if let y = filter.yearFrom ?? filter.yearTo {
            qi.append(URLQueryItem(name: "year", value: String(y)))
        }
        for g in filter.genres {
            qi.append(URLQueryItem(name: "genres.name", value: g))
        }
        switch filter.sort {
        case .rating:
            qi.append(URLQueryItem(name: "sortField", value: "rating.kp"))
            qi.append(URLQueryItem(name: "sortType", value: "-1"))
        case .year:
            qi.append(URLQueryItem(name: "sortField", value: "year"))
            qi.append(URLQueryItem(name: "sortType", value: "-1"))
        case .name:
            qi.append(URLQueryItem(name: "sortField", value: "name"))
            qi.append(URLQueryItem(name: "sortType", value: "1"))
        case .recent:
            qi.append(URLQueryItem(name: "sortField", value: "createdAt"))
            qi.append(URLQueryItem(name: "sortType", value: "-1"))
        case .popularity:
            qi.append(URLQueryItem(name: "sortField", value: "votes.kp"))
            qi.append(URLQueryItem(name: "sortType", value: "-1"))
        }
        c.queryItems = qi
        let env: PoiskKinoEnvelope = try await HTTPClient.shared.get(c.url!, as: PoiskKinoEnvelope.self, headers: authHeaders())
        return env.docs.compactMap { mapDoc($0) }
    }

    func popular(kind: ContentKind, limit: Int) async throws -> [ContentItem] {
        guard supports(kind), AppSecrets.poiskkinoToken.isEmpty == false else { return [] }
        var c = URLComponents(url: host.appendingPathComponent("\(movieAPI)/movie"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "isSeries", value: kind == .series ? "true" : "false"),
            URLQueryItem(name: "sortField", value: "votes.kp"),
            URLQueryItem(name: "sortType", value: "-1"),
            URLQueryItem(name: "rating.kp", value: "7-10")
        ]
        let env: PoiskKinoEnvelope = try await HTTPClient.shared.get(c.url!, as: PoiskKinoEnvelope.self, headers: authHeaders())
        return env.docs.compactMap { mapDoc($0) }
    }

    func episodes(for item: ContentItem) async throws -> [Episode] {
        // PoiskKino has no streams — defer to Kodik via kinopoisk_id stored as
        // the originalID. The DetailViewModel calls this and KodikSource in
        // sequence; we just return [].
        return []
    }

    func genres(kind: ContentKind) async throws -> [Genre] {
        guard supports(kind), AppSecrets.poiskkinoToken.isEmpty == false else {
            return []
        }
        var c = URLComponents(url: host.appendingPathComponent("\(metaAPI)/movie/possible-values-by-field"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "field", value: "genres.name")]
        let arr: [PoiskKinoFieldValue] = try await HTTPClient.shared.get(c.url!, as: [PoiskKinoFieldValue].self, headers: authHeaders())
        return arr.map { Genre(id: $0.name, name: $0.name, kind: kind) }
    }

    // MARK: - Internal

    private func authHeaders() -> [String: String] {
        ["X-API-KEY": AppSecrets.poiskkinoToken]
    }

    private func mapDoc(_ d: PoiskKinoDoc) -> ContentItem? {
        let kind: ContentKind = (d.isSeries ?? false) ? .series : .movie
        let title = d.name ?? d.alternativeName ?? d.enName ?? "—"
        let originalID = String(d.id)
        return ContentItem(
            id: ContentItem.makeID(sourceID: id, kind: kind, originalID: originalID),
            sourceID: id,
            kind: kind,
            title: title,
            originalTitle: d.alternativeName ?? d.enName,
            descriptionText: d.description,
            posterURL: d.poster?.url.flatMap(URL.init(string:)),
            bannerURL: d.backdrop?.url.flatMap(URL.init(string:)),
            year: d.year,
            genres: (d.genres ?? []).compactMap { $0.name },
            rating: d.rating?.kp ?? d.rating?.imdb,
            durationMinutes: d.movieLength ?? d.seriesLength,
            totalEpisodes: d.seasonsInfo?.reduce(0) { $0 + ($1.episodesCount ?? 0) }
        )
    }
}

// MARK: - DTOs

private struct PoiskKinoEnvelope: Decodable {
    let docs: [PoiskKinoDoc]
    let total: Int?
    let limit: Int?
    let page: Int?
    let pages: Int?
}

private struct PoiskKinoDoc: Decodable {
    let id: Int
    let name: String?
    let alternativeName: String?
    let enName: String?
    let description: String?
    let year: Int?
    let isSeries: Bool?
    let movieLength: Int?
    let seriesLength: Int?
    let rating: PoiskKinoRating?
    let poster: PoiskKinoImage?
    let backdrop: PoiskKinoImage?
    let genres: [PoiskKinoNamed]?
    let seasonsInfo: [PoiskKinoSeasonInfo]?
}

private struct PoiskKinoRating: Decodable {
    let kp: Double?
    let imdb: Double?
    let tmdb: Double?
}

private struct PoiskKinoImage: Decodable {
    let url: String?
    let previewUrl: String?
}

private struct PoiskKinoNamed: Decodable {
    let name: String?
}

private struct PoiskKinoSeasonInfo: Decodable {
    let number: Int?
    let episodesCount: Int?
}

private struct PoiskKinoFieldValue: Decodable {
    let name: String
    let slug: String?
}
