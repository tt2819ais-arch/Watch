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
        // PoiskKino is a metadata-only source — most popular Western films
        // it returns have no matching Kodik stream, which manifests as
        // "Нет источников" the moment the user opens a card. We therefore
        // only contribute to the catalog grid when a real text query is
        // being typed; idle browsing falls back to Kodik (which is the
        // actual stream source and therefore guarantees playability).
        return []
    }

    func popular(kind: ContentKind, limit: Int) async throws -> [ContentItem] {
        // Same rationale as `search` — see comment there. The Home screen's
        // "Popular" rail used to surface high-vote Western titles that have
        // no Kodik mirror, so the user got cards that say "Нет источников"
        // the moment they're tapped. Defer entirely to Kodik for popular
        // movies/series so the rail only contains items we can actually
        // play.
        _ = kind; _ = limit
        return []
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
        return arr.map { Genre(id: $0.name, name: $0.name) }
    }

    // MARK: - Internal

    /// Resolve a YouTube trailer URL for a kinopoisk item by id.
    /// Returns nil when the source doesn't have a trailer or the API
    /// call failed — callers must treat this as best-effort.
    func trailerURL(forKinopoiskID kpID: String) async -> URL? {
        guard !AppSecrets.poiskkinoToken.isEmpty,
              let kpInt = Int(kpID) else { return nil }
        let url = host
            .appendingPathComponent(movieAPI)
            .appendingPathComponent("movie")
            .appendingPathComponent(String(kpInt))
        do {
            let dto: PoiskKinoMovieFull = try await HTTPClient.shared.get(
                url, as: PoiskKinoMovieFull.self, headers: authHeaders())
            let trailers = dto.videos?.trailers ?? []
            // Prefer YouTube; fall back to anything with a usable URL
            let pick = trailers.first(where: { ($0.site ?? "").lowercased() == "youtube" })
                ?? trailers.first(where: { $0.url != nil })
            guard let raw = pick?.url, let u = URL(string: raw) else { return nil }
            return u
        } catch {
            return nil
        }
    }

    /// Search for the kinopoisk_id of a non-PoiskKino item by title + year.
    /// Used by the trailer pipeline so Kodik-sourced items can also surface
    /// a trailer embed without piggy-backing on a kinopoisk_id we already
    /// know.
    func resolveKinopoiskID(title: String, year: Int?) async -> String? {
        guard !AppSecrets.poiskkinoToken.isEmpty else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var c = URLComponents(url: host.appendingPathComponent("\(movieAPI)/movie/search"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "query", value: trimmed)
        ]
        guard let u = c.url else { return nil }
        do {
            let env: PoiskKinoEnvelope = try await HTTPClient.shared.get(u, as: PoiskKinoEnvelope.self, headers: authHeaders())
            // If we know the year, prefer matches within ±1; otherwise the
            // first hit is our best guess (PoiskKino sorts by relevance).
            let docs = env.docs
            let best: PoiskKinoDoc? = {
                if let y = year {
                    return docs.first(where: { abs(($0.year ?? 0) - y) <= 1 }) ?? docs.first
                }
                return docs.first
            }()
            return best.map { String($0.id) }
        } catch {
            return nil
        }
    }

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

private struct PoiskKinoMovieFull: Decodable {
    let id: Int
    let videos: PoiskKinoVideos?
}

private struct PoiskKinoVideos: Decodable {
    let trailers: [PoiskKinoTrailer]?
}

private struct PoiskKinoTrailer: Decodable {
    let url: String?
    let name: String?
    let site: String?
    let type: String?
}

private struct PoiskKinoFieldValue: Decodable {
    let name: String
    let slug: String?
}
