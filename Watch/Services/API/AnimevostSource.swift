import Foundation

/// Animevost (api.animevost.org) — open Russian-dub anime API. No token,
/// no auth. Endpoints used:
///   GET  /v1/last?page=N&quantity=N        — recent / popular feed
///   POST /v1/search   body: name=<query>   — title search
///   POST /v1/playlist body: id=<release>   — episode list with mp4 URLs
///
/// Provides anime only. Streams are direct .mp4 in `std` (≈480p) and
/// `hd` (720p), so no embed / web-view fallback needed.
final class AnimevostSource: ContentSource, @unchecked Sendable {
    let id: String = "animevost"
    let displayName: String = "Animevost"

    private let api = URL(string: "https://api.animevost.org/v1")!

    func supports(_ kind: ContentKind) -> Bool {
        kind == .anime
    }

    // MARK: - Search / suggestions

    func suggest(query: String, kind: ContentKind) async throws -> [ContentItem] {
        guard kind == .anime else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return try await searchAPI(name: trimmed)
    }

    func search(filter: CatalogFilter, kind: ContentKind, page: Int) async throws -> [ContentItem] {
        guard kind == .anime else { return [] }
        let q = filter.query.trimmingCharacters(in: .whitespaces)
        let raw: [ContentItem]
        if !q.isEmpty {
            raw = try await searchAPI(name: q)
        } else {
            raw = try await fetchLast(page: max(1, page), quantity: 30)
        }
        return apply(filter: filter, to: raw)
    }

    func popular(kind: ContentKind, limit: Int) async throws -> [ContentItem] {
        guard kind == .anime else { return [] }
        return try await fetchLast(page: 1, quantity: limit)
    }

    // MARK: - Detail / episodes

    func episodes(for item: ContentItem) async throws -> [Episode] {
        guard let releaseID = parseReleaseID(item.id) else { return [] }
        let url = api.appendingPathComponent("playlist")
        let body = formBody(["id": releaseID])
        let raw: [PlaylistItem] = try await HTTPClient.shared.post(
            url,
            body: body,
            as: [PlaylistItem].self,
            headers: ["Content-Type": "application/x-www-form-urlencoded"]
        )

        let voice = VoiceTrack(id: "animevost_ru", studio: "Animevost", language: "ru")
        return raw.enumerated().compactMap { (idx, p) -> Episode? in
            let number = parseEpisodeNumber(p.name) ?? (idx + 1)
            var sources: [VideoSource] = []
            if let stdStr = p.std, let stdURL = URL(string: stdStr) {
                sources.append(VideoSource(
                    id: "animevost_\(releaseID)_\(number)_std",
                    url: stdURL,
                    quality: .sd,
                    voiceTrack: voice,
                    headers: [:]
                ))
            }
            if let hdStr = p.hd, let hdURL = URL(string: hdStr) {
                sources.append(VideoSource(
                    id: "animevost_\(releaseID)_\(number)_hd",
                    url: hdURL,
                    quality: .hd,
                    voiceTrack: voice,
                    headers: [:]
                ))
            }
            guard !sources.isEmpty else { return nil }
            let thumb = p.preview.flatMap { URL(string: $0) }
            return Episode(
                id: "animevost_\(releaseID)_\(number)",
                number: number,
                title: p.name,
                durationSeconds: nil,
                thumbnailURL: thumb,
                sources: sources
            )
        }
        .sorted { $0.number < $1.number }
    }

    func genres(kind: ContentKind) async throws -> [Genre] {
        // Animevost does not expose a genres endpoint; offer a curated list
        // matching what we already use for the AniLibria/Kodik anime tabs.
        guard kind == .anime else { return [] }
        return defaultAnimevostGenres
    }

    // MARK: - HTTP

    private func searchAPI(name: String) async throws -> [ContentItem] {
        let url = api.appendingPathComponent("search")
        let body = formBody(["name": name])
        let envelope: ListEnvelope = try await HTTPClient.shared.post(
            url,
            body: body,
            as: ListEnvelope.self,
            headers: ["Content-Type": "application/x-www-form-urlencoded"]
        )
        return envelope.data.map { mapToItem($0) }
    }

    private func fetchLast(page: Int, quantity: Int) async throws -> [ContentItem] {
        var c = URLComponents(url: api.appendingPathComponent("last"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "quantity", value: String(quantity))
        ]
        let envelope: ListEnvelope = try await HTTPClient.shared.get(c.url!, as: ListEnvelope.self)
        return envelope.data.map { mapToItem($0) }
    }

    private func formBody(_ pairs: [String: String]) -> Data {
        let encoded = pairs.map { (k, v) -> String in
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }

    // MARK: - Mapping

    private func mapToItem(_ r: AnimevostRelease) -> ContentItem {
        let cleanedTitle = sanitizeTitle(r.title)
        let (rus, orig) = splitRussianAndOriginal(cleanedTitle)
        let genres = (r.genre ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let yearInt = r.year.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let posterURL = r.urlImagePreview.flatMap { URL(string: $0) }
        return ContentItem(
            id: ContentItem.makeID(sourceID: id, kind: .anime, originalID: String(r.id)),
            sourceID: id,
            kind: .anime,
            title: rus.isEmpty ? cleanedTitle : rus,
            originalTitle: orig.isEmpty ? nil : orig,
            descriptionText: r.description?.replacingOccurrences(of: "<br />", with: "\n"),
            posterURL: posterURL,
            bannerURL: posterURL,
            year: yearInt,
            genres: genres,
            rating: r.rating.flatMap { ratingScore(votes: $0, total: r.votes ?? 0) },
            durationMinutes: nil,
            totalEpisodes: nil
        )
    }

    /// Animevost titles look like `"Игра лжецов / Liar Game [1-4 из 12+]"`.
    /// Drop the trailing bracketed status so cards stay clean.
    private func sanitizeTitle(_ raw: String) -> String {
        var s = raw
        if let r = s.range(of: #"\s*\[[^\]]*\]\s*"#, options: .regularExpression) {
            s.removeSubrange(r)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Split `"Russian / Original"` into `("Russian", "Original")`.
    private func splitRussianAndOriginal(_ title: String) -> (String, String) {
        guard let slash = title.range(of: " / ") else { return (title, "") }
        let rus = String(title[..<slash.lowerBound]).trimmingCharacters(in: .whitespaces)
        let orig = String(title[slash.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (rus, orig)
    }

    private func parseEpisodeNumber(_ name: String) -> Int? {
        // Names look like "1 серия", "12 серия", "ОВА".
        let scanner = Scanner(string: name)
        scanner.charactersToBeSkipped = .whitespaces
        var digits: Int = 0
        if scanner.scanInt(&digits) {
            return digits
        }
        return nil
    }

    private func parseReleaseID(_ compositeID: String) -> String? {
        // Composite id format: "animevost|anime|<id>"
        let parts = compositeID.split(separator: "|")
        guard parts.count == 3, parts[0] == id else { return nil }
        return String(parts[2])
    }

    /// Animevost rating is an absolute "likes" count, not a 0–10 score.
    /// Translate to a normalized 0–10 score so it lines up with the other
    /// sources: rating ÷ max(votes, 1) × 10, clamped.
    private func ratingScore(votes: Int, total: Int) -> Double? {
        guard total > 0 else { return nil }
        let raw = Double(votes) / Double(total) * 10.0
        return max(0, min(10, raw))
    }

    private let defaultAnimevostGenres: [Genre] = [
        "боевик", "драма", "комедия", "меха", "мистика",
        "приключения", "романтика", "сёнэн", "сёдзё", "спорт",
        "сверхъестественное", "повседневность", "психологическое",
        "научная фантастика", "фэнтези", "школа", "ужасы"
    ].map { Genre(id: $0, name: $0.capitalized) }

    private func apply(filter: CatalogFilter, to items: [ContentItem]) -> [ContentItem] {
        var arr = items
        if let from = filter.yearFrom { arr = arr.filter { ($0.year ?? 0) >= from } }
        if let to = filter.yearTo   { arr = arr.filter { ($0.year ?? 9999) <= to } }
        if !filter.genres.isEmpty {
            arr = arr.filter { item in
                !item.genres.isEmpty && filter.genres.allSatisfy { wanted in
                    item.genres.contains { $0.localizedCaseInsensitiveContains(wanted) }
                }
            }
        }
        return arr
    }
}

// MARK: - Wire types

private struct ListEnvelope: Decodable {
    let state: ListState
    let data: [AnimevostRelease]
}

private struct ListState: Decodable {
    let status: String
    let count: Int?
    let page: Int?
}

private struct AnimevostRelease: Decodable {
    let id: Int
    let title: String
    let description: String?
    let genre: String?
    let year: String?
    let urlImagePreview: String?
    let rating: Int?
    let votes: Int?
    let type: String?
}

private struct PlaylistItem: Decodable {
    let name: String
    let std: String?
    let hd: String?
    let preview: String?
}

private extension CharacterSet {
    static var urlFormAllowed: CharacterSet {
        // application/x-www-form-urlencoded — RFC 3986 unreserved + a few extras.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }
}
