import Foundation

/// Thin client for the Watch FastAPI backend. Single point of contact for
/// auth, social profiles, messaging, and sync (stats / favorites).
///
/// Decoder uses `convertFromSnakeCase` + ISO 8601 dates, encoder mirrors that
/// so JSON bodies match the backend's pydantic schemas.
actor WatchAPI {
    static let shared = WatchAPI()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private(set) var token: String?

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { dec in
            let raw = try dec.singleValueContainer().decode(String.self)
            if let d = WatchAPI.iso8601MS.date(from: raw) { return d }
            if let d = WatchAPI.iso8601.date(from: raw) { return d }
            // Backend sometimes returns naive timestamps without a "Z".
            if let d = WatchAPI.iso8601Naive.date(from: raw) { return d }
            throw DecodingError.dataCorruptedError(in: try dec.singleValueContainer(),
                debugDescription: "Cannot parse date: \(raw)")
        }

        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let iso8601MS: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601Naive: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return f
    }()

    // MARK: - Token

    func setToken(_ token: String?) {
        self.token = token
    }

    // MARK: - Auth

    func signup(nickname: String, password: String) async throws -> SocialTokenResponse {
        let body = ["nickname": nickname, "password": password]
        let resp: SocialTokenResponse = try await request("/auth/signup", method: "POST", body: body, requiresAuth: false)
        setToken(resp.accessToken)
        return resp
    }

    func login(nickname: String, password: String) async throws -> SocialTokenResponse {
        let body = ["nickname": nickname, "password": password]
        let resp: SocialTokenResponse = try await request("/auth/login", method: "POST", body: body, requiresAuth: false)
        setToken(resp.accessToken)
        return resp
    }

    func me() async throws -> PublicUser {
        try await request("/auth/me", method: "GET", body: Optional<EmptyBody>.none, requiresAuth: true)
    }

    func updateMe(bio: String? = nil,
                  privacyHideStats: Bool? = nil,
                  privacyHideFavorites: Bool? = nil,
                  privacyHideHistory: Bool? = nil) async throws -> PublicUser {
        let body = UpdateMeRequest(
            bio: bio,
            privacyHideStats: privacyHideStats,
            privacyHideFavorites: privacyHideFavorites,
            privacyHideHistory: privacyHideHistory
        )
        return try await request("/users/me", method: "PATCH", body: body, requiresAuth: true)
    }

    // MARK: - Users

    func publicProfile(nickname: String) async throws -> PublicProfile {
        let path = "/users/\(percentEncode(nickname))"
        return try await request(path, method: "GET", body: Optional<EmptyBody>.none, requiresAuth: true)
    }

    func searchUsers(query: String) async throws -> [PublicUser] {
        var c = URLComponents(url: SocialConfig.backendURL.appendingPathComponent("users"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "query", value: query)]
        return try await request(absolute: c.url!, method: "GET", body: Optional<EmptyBody>.none, requiresAuth: true)
    }

    // MARK: - Messages

    func conversation(with nickname: String) async throws -> [SocialMessage] {
        let path = "/messages/\(percentEncode(nickname))"
        return try await request(path, method: "GET", body: Optional<EmptyBody>.none, requiresAuth: true)
    }

    func inbox() async throws -> [InboxEntry] {
        try await request("/messages/inbox", method: "GET", body: Optional<EmptyBody>.none, requiresAuth: true)
    }

    func sendMessage(to nickname: String,
                     body: String,
                     itemId: String? = nil,
                     itemTitle: String? = nil,
                     itemPosterUrl: String? = nil) async throws -> SocialMessage {
        let payload = MessageInRequest(body: body, itemId: itemId, itemTitle: itemTitle, itemPosterUrl: itemPosterUrl)
        return try await request("/messages/\(percentEncode(nickname))", method: "POST", body: payload, requiresAuth: true)
    }

    func deleteMessage(_ id: Int) async throws {
        try await voidRequest("/messages/\(id)", method: "DELETE", requiresAuth: true)
    }

    func reactToMessage(_ id: Int, emoji: String) async throws -> SocialMessage {
        let payload = ["emoji": emoji]
        return try await request("/messages/\(id)/react", method: "POST", body: payload, requiresAuth: true)
    }

    func block(nickname: String) async throws {
        try await voidRequest("/messages/block/\(percentEncode(nickname))", method: "POST", requiresAuth: true)
    }

    func unblock(nickname: String) async throws {
        try await voidRequest("/messages/block/\(percentEncode(nickname))", method: "DELETE", requiresAuth: true)
    }

    // MARK: - Public stats

    func communityStats() async throws -> CommunityStats {
        async let onlineFetch: OnlineStat = request(
            "/stats/online", method: "GET",
            body: Optional<EmptyBody>.none, requiresAuth: false
        )
        async let countFetch: UsersCountStat = request(
            "/users/count", method: "GET",
            body: Optional<EmptyBody>.none, requiresAuth: false
        )
        let online = try await onlineFetch
        let count = try await countFetch
        return CommunityStats(online: online.online, total: count.total, newLast7d: count.newLast7d)
    }

    func changePassword(current: String, new: String) async throws -> PublicUser {
        let body = ["current_password": current, "new_password": new]
        return try await request("/auth/change_password", method: "POST", body: body, requiresAuth: true)
    }

    // MARK: - Admin

    func adminVerify(nickname: String) async throws -> PublicUser {
        try await request("/admin/verify/\(percentEncode(nickname))", method: "POST", body: Optional<EmptyBody>.none, requiresAuth: true)
    }

    func adminUnverify(nickname: String) async throws -> PublicUser {
        try await request("/admin/verify/\(percentEncode(nickname))", method: "DELETE", body: Optional<EmptyBody>.none, requiresAuth: true)
    }

    func adminPromote(nickname: String) async throws -> PublicUser {
        try await request("/admin/promote/\(percentEncode(nickname))", method: "POST", body: Optional<EmptyBody>.none, requiresAuth: true)
    }

    // MARK: - Sync (favorites / stats)

    func pushStat(itemId: String,
                  title: String,
                  posterUrl: String?,
                  kind: String,
                  episodeNumber: Int?,
                  secondsWatched: Int?) async throws -> SocialStatPoint {
        let body = StatPointInRequest(
            itemId: itemId,
            title: title,
            posterUrl: posterUrl,
            kind: kind,
            episodeNumber: episodeNumber,
            secondsWatched: secondsWatched
        )
        return try await request("/sync/stats", method: "POST", body: body, requiresAuth: true)
    }

    func addFavorite(itemId: String, title: String, posterUrl: String?, kind: String) async throws -> SocialFavorite {
        let body = FavoriteInRequest(itemId: itemId, title: title, posterUrl: posterUrl, kind: kind)
        return try await request("/sync/favorites", method: "POST", body: body, requiresAuth: true)
    }

    func removeFavorite(itemId: String) async throws {
        try await voidRequest("/sync/favorites/\(percentEncode(itemId))", method: "DELETE", requiresAuth: true)
    }

    // MARK: - Plumbing

    private func percentEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }

    private func request<T: Decodable, B: Encodable>(_ path: String, method: String, body: B?, requiresAuth: Bool) async throws -> T {
        guard let url = URL(string: path, relativeTo: SocialConfig.backendURL) else {
            throw WatchAPIError.invalidURL
        }
        return try await request(absolute: url, method: method, body: body, requiresAuth: requiresAuth)
    }

    private func request<T: Decodable, B: Encodable>(absolute url: URL, method: String, body: B?, requiresAuth: Bool) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                req.httpBody = try encoder.encode(body)
            } catch {
                throw WatchAPIError.decoding(error)
            }
        }
        if requiresAuth {
            guard let token else { throw WatchAPIError.unauthorized }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        Logger.shared.debug("WatchAPI \(method) \(url.absoluteString)", category: .network)

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            // SwiftUI cancels in-flight tasks aggressively when a view's
            // .task is re-evaluated (tab switch, sheet dismissal). Those
            // cancellations are not real errors and shouldn't pollute the
            // log; just rethrow so the caller's catch logic decides.
            let nsErr = error as NSError
            if nsErr.code != NSURLErrorCancelled {
                Logger.shared.warn("WatchAPI \(method) \(url.absoluteString) transport: \(error.localizedDescription)", category: .network)
            }
            throw WatchAPIError.transport(error)
        }

        guard let http = resp as? HTTPURLResponse else {
            throw WatchAPIError.transport(URLError(.badServerResponse))
        }

        Logger.shared.debug("WatchAPI \(method) \(url.absoluteString) -> \(http.statusCode)", category: .network)

        if http.statusCode == 401 { throw WatchAPIError.unauthorized }
        if http.statusCode == 403 { throw WatchAPIError.forbidden }

        guard (200...299).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            Logger.shared.warn("WatchAPI \(method) \(url.absoluteString) -> \(http.statusCode) body: \(bodyStr.prefix(300))", category: .network)
            throw WatchAPIError.status(http.statusCode, body: bodyStr)
        }

        // Tolerate empty bodies when caller asked for `EmptyResponse`.
        if T.self == EmptyResponse.self {
            // swiftlint:disable:next force_cast
            return EmptyResponse() as! T
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw WatchAPIError.decoding(error)
        }
    }

    private func voidRequest(_ path: String, method: String, requiresAuth: Bool) async throws {
        let _: EmptyResponse = try await request(path, method: method, body: Optional<EmptyBody>.none, requiresAuth: requiresAuth)
    }
}

// MARK: - Wire bodies

private struct EmptyBody: Encodable {}

struct EmptyResponse: Decodable { init() {} }

private struct UpdateMeRequest: Encodable {
    let bio: String?
    let privacyHideStats: Bool?
    let privacyHideFavorites: Bool?
    let privacyHideHistory: Bool?
}

private struct MessageInRequest: Encodable {
    let body: String
    let itemId: String?
    let itemTitle: String?
    let itemPosterUrl: String?
}

private struct StatPointInRequest: Encodable {
    let itemId: String
    let title: String
    let posterUrl: String?
    let kind: String
    let episodeNumber: Int?
    let secondsWatched: Int?
}

private struct FavoriteInRequest: Encodable {
    let itemId: String
    let title: String
    let posterUrl: String?
    let kind: String
}
