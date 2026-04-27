import Foundation

/// Kodik (kodik-api.com) — anime / movies / series streams via embedded
/// iframe. Token can be the public fallback baked into BakedSecrets, or a
/// user-provided override via Settings.
final class KodikSource: ContentSource, @unchecked Sendable {
    let id: String = "kodik"
    let displayName: String = "Kodik"

    private let api = URL(string: "https://kodik-api.com")!

    func supports(_ kind: ContentKind) -> Bool { true }

    // MARK: - Search / suggestions

    func suggest(query: String, kind: ContentKind) async throws -> [ContentItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let raw = try await search(parameters: ["title": trimmed, "limit": "20"])
        return raw.compactMap { mapToItem($0, kind: kind) }
    }

    func search(filter: CatalogFilter, kind: ContentKind, page: Int) async throws -> [ContentItem] {
        var params: [String: String] = ["limit": "30"]
        let trimmed = filter.query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { params["title"] = trimmed }
        if let from = filter.yearFrom, let to = filter.yearTo {
            params["year"] = "\(from)-\(to)"
        } else if let y = filter.yearFrom ?? filter.yearTo {
            params["year"] = String(y)
        }
        if !filter.genres.isEmpty {
            params[kind == .anime ? "anime_genres" : "genres"] = filter.genres.joined(separator: ",")
        }
        params["types"] = typesParam(for: kind)
        let raw = try await search(parameters: params)
        return raw.compactMap { mapToItem($0, kind: kind) }
    }

    func popular(kind: ContentKind, limit: Int) async throws -> [ContentItem] {
        let raw = try await list(parameters: [
            "types": typesParam(for: kind),
            "limit": String(limit),
            "sort": "year"
        ])
        return raw.compactMap { mapToItem($0, kind: kind) }
    }

    // MARK: - Detail / episodes

    func episodes(for item: ContentItem) async throws -> [Episode] {
        // Direct lookup by Kodik internal id.
        if let originalID = parseOriginalID(item.id) {
            let raw = try await search(parameters: [
                "id": originalID,
                "with_seasons": "true",
                "with_episodes": "true"
            ])
            return buildEpisodes(from: raw)
        }
        // Cross-source lookup: PoiskKino → Kodik via kinopoisk_id.
        if item.sourceID == "poiskkino", let kpID = poiskkinoOriginalID(from: item.id) {
            return try await episodesByKinopoiskID(kpID)
        }
        // Last-resort: search by title.
        return try await episodesByTitle(item.title, year: item.year)
    }

    /// Look up Kodik streams for a Kinopoisk id.
    func episodesByKinopoiskID(_ kpID: String) async throws -> [Episode] {
        let raw = try await search(parameters: [
            "kinopoisk_id": kpID,
            "with_seasons": "true",
            "with_episodes": "true"
        ])
        return buildEpisodes(from: raw)
    }

    /// Fuzzy fallback: search by title.
    func episodesByTitle(_ title: String, year: Int?) async throws -> [Episode] {
        var params: [String: String] = [
            "title": title,
            "with_seasons": "true",
            "with_episodes": "true",
            "limit": "10"
        ]
        if let year { params["year"] = String(year) }
        let raw = try await search(parameters: params)
        return buildEpisodes(from: raw)
    }

    private func poiskkinoOriginalID(from compositeID: String) -> String? {
        let parts = compositeID.split(separator: "|")
        guard parts.count == 3, parts[0] == "poiskkino" else { return nil }
        return String(parts[2])
    }

    func genres(kind: ContentKind) async throws -> [Genre] {
        // Kodik does not expose a /genres endpoint; we return a curated list.
        switch kind {
        case .anime:
            return defaultAnimeGenres
        case .movie, .series:
            return defaultMovieGenres
        }
    }

    // MARK: - HTTP

    private func search(parameters: [String: String]) async throws -> [KodikResult] {
        try await postCollection(path: "/search", parameters: parameters)
    }

    private func list(parameters: [String: String]) async throws -> [KodikResult] {
        try await postCollection(path: "/list", parameters: parameters)
    }

    private func postCollection(path: String, parameters: [String: String]) async throws -> [KodikResult] {
        var p = parameters
        p["token"] = await KodikTokenResolver.shared.currentToken()
        guard !p["token"]!.isEmpty else { return [] }

        var c = URLComponents(url: api.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        c.queryItems = p.map { URLQueryItem(name: $0.key, value: $0.value) }

        do {
            let envelope: KodikEnvelope = try await HTTPClient.shared.post(c.url!, body: nil, as: KodikEnvelope.self)
            if let err = envelope.error, err.contains("токен") {
                // Token went stale mid-session — drop the cache, refresh, retry once.
                Logger.shared.info("Kodik token rejected, refreshing…", category: .source)
                await KodikTokenResolver.shared.markInvalid()
                if let fresh = await KodikTokenResolver.shared.refresh(), !fresh.isEmpty {
                    p["token"] = fresh
                    c.queryItems = p.map { URLQueryItem(name: $0.key, value: $0.value) }
                    let retry: KodikEnvelope = try await HTTPClient.shared.post(c.url!, body: nil, as: KodikEnvelope.self)
                    return retry.results ?? []
                }
                return []
            }
            return envelope.results ?? []
        } catch {
            throw error
        }
    }

    // MARK: - Mapping

    private func typesParam(for kind: ContentKind) -> String {
        switch kind {
        case .anime: return "anime,anime-serial"
        case .movie: return "film,foreign-movie,soviet-cartoon,foreign-cartoon,russian-cartoon"
        case .series: return "foreign-serial,russian-serial,cartoon-serial"
        }
    }

    private func mapToItem(_ r: KodikResult, kind: ContentKind) -> ContentItem? {
        let resolvedKind = inferKind(from: r.type) ?? kind
        guard supports(resolvedKind) else { return nil }
        let title = r.title ?? r.titleOrig ?? r.otherTitle ?? "—"
        return ContentItem(
            id: ContentItem.makeID(sourceID: id, kind: resolvedKind, originalID: r.id ?? title),
            sourceID: id,
            kind: resolvedKind,
            title: title,
            originalTitle: r.titleOrig,
            descriptionText: nil,
            posterURL: r.materialData?.posterUrl.flatMap(URL.init(string:))
                ?? r.screenshots?.first.flatMap(URL.init(string:)),
            bannerURL: r.materialData?.posterUrl.flatMap(URL.init(string:)),
            year: r.year,
            genres: r.materialData?.animeGenres ?? r.materialData?.genres ?? [],
            rating: r.materialData?.kinopoiskRating ?? r.materialData?.imdbRating,
            durationMinutes: nil,
            totalEpisodes: r.episodesCount
        )
    }

    private func inferKind(from rawType: String?) -> ContentKind? {
        guard let raw = rawType else { return nil }
        if raw.contains("anime") { return .anime }
        if raw.contains("serial") { return .series }
        if raw.contains("film") || raw.contains("movie") || raw.contains("cartoon") {
            return raw.contains("serial") ? .series : .movie
        }
        return nil
    }

    private func parseOriginalID(_ compositeID: String) -> String? {
        let parts = compositeID.split(separator: "|")
        guard parts.count == 3, parts[0] == id else { return nil }
        return String(parts[2])
    }

    private func buildEpisodes(from results: [KodikResult]) -> [Episode] {
        var byNumber: [Int: [VideoSource]] = [:]
        for r in results {
            guard let link = r.absoluteLink else { continue }
            let voice = VoiceTrack(
                id: "kodik_\(r.translation?.id ?? 0)",
                studio: r.translation?.title ?? "Kodik",
                language: (r.translation?.type ?? "") == "subtitles" ? "субтитры" : "RU"
            )
            // Each translation may have multiple episodes; if none, treat as single-file (movie).
            if let seasons = r.seasons, !seasons.isEmpty {
                for season in seasons.values {
                    for (numStr, episodeURL) in (season.episodes ?? [:]) {
                        let n = Int(numStr) ?? 0
                        let url = absoluteIframeURL(from: episodeURL) ?? link
                        var arr = byNumber[n, default: []]
                        arr.append(VideoSource(
                            id: "\(r.id ?? "")_\(n)_\(voice.id)",
                            url: url,
                            quality: parseQuality(r.quality),
                            voiceTrack: voice,
                            headers: [:]
                        ))
                        byNumber[n] = arr
                    }
                }
            } else {
                let n = r.lastEpisode ?? 1
                var arr = byNumber[n, default: []]
                arr.append(VideoSource(
                    id: "\(r.id ?? "")_\(n)_\(voice.id)",
                    url: link,
                    quality: parseQuality(r.quality),
                    voiceTrack: voice,
                    headers: [:]
                ))
                byNumber[n] = arr
            }
        }
        return byNumber
            .sorted { $0.key < $1.key }
            .map { (num, sources) in
                Episode(
                    id: "kodik_ep_\(num)",
                    number: num,
                    title: nil,
                    durationSeconds: nil,
                    thumbnailURL: nil,
                    sources: sources
                )
            }
    }

    private func parseQuality(_ q: String?) -> VideoQuality {
        guard let q else { return .hd }
        let s = q.lowercased()
        if s.contains("2160") || s.contains("4k") { return .uhd }
        if s.contains("1080") { return .fhd }
        if s.contains("720")  { return .hd }
        return .sd
    }

    private func absoluteIframeURL(from raw: String) -> URL? {
        if raw.hasPrefix("//") { return URL(string: "https:" + raw) }
        return URL(string: raw)
    }

    // Curated genre list (Kodik has no genres endpoint).
    private let defaultAnimeGenres: [Genre] = [
        "Сёнен", "Сёдзе", "Романтика", "Комедия", "Драма", "Боевик", "Приключения",
        "Фэнтези", "Меха", "Спорт", "Школа", "Сверхъестественное", "Хоррор", "Спокон",
        "Этти", "Гарем", "Сейнен", "Йонкома"
    ].map { Genre(id: $0, name: $0) }

    private let defaultMovieGenres: [Genre] = [
        "Боевик", "Драма", "Комедия", "Криминал", "Детектив", "Триллер", "Ужасы",
        "Фантастика", "Фэнтези", "Мелодрама", "Военный", "Биография", "История",
        "Приключения", "Семейный", "Спорт", "Документальный", "Мультфильм", "Аниме"
    ].map { Genre(id: $0, name: $0) }
}

// MARK: - DTOs

private struct KodikEnvelope: Decodable {
    let total: Int?
    let results: [KodikResult]?
    let nextPage: String?
    let prevPage: String?
    let error: String?
}

private struct KodikResult: Decodable {
    let id: String?
    let type: String?
    let link: String?
    let title: String?
    let titleOrig: String?
    let otherTitle: String?
    let translation: KodikTranslation?
    let year: Int?
    let lastSeason: Int?
    let lastEpisode: Int?
    let episodesCount: Int?
    let kinopoiskId: String?
    let imdbId: String?
    let shikimoriId: String?
    let quality: String?
    let screenshots: [String]?
    let materialData: KodikMaterial?
    let seasons: [String: KodikSeason]?

    var absoluteLink: URL? {
        guard let l = link else { return nil }
        return l.hasPrefix("//") ? URL(string: "https:" + l) : URL(string: l)
    }
}

private struct KodikTranslation: Decodable {
    let id: Int?
    let title: String?
    let type: String?
}

private struct KodikSeason: Decodable {
    let link: String?
    let episodes: [String: String]?
}

private struct KodikMaterial: Decodable {
    let title: String?
    let animeTitle: String?
    let titleEn: String?
    let otherTitles: [String]?
    let posterUrl: String?
    let animePosterUrl: String?
    let description: String?
    let animeDescription: String?
    let kinopoiskRating: Double?
    let imdbRating: Double?
    let shikimoriRating: Double?
    let year: Int?
    let countries: [String]?
    let genres: [String]?
    let animeGenres: [String]?
    let duration: Int?
}
