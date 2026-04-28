import Foundation

// MARK: - Public user / profile

/// Mirrors the backend's `PublicUser` schema (see `/openapi.json`).
struct PublicUser: Codable, Hashable, Identifiable {
    let id: Int
    let nickname: String
    let bio: String
    let role: String
    let verified: Bool
    let isOfficial: Bool
    let createdAt: Date
    let privacyHideStats: Bool
    let privacyHideFavorites: Bool
    let privacyHideHistory: Bool
    let shareUrl: String

    var isAdmin: Bool { role.lowercased() == "admin" }

    /// Display nickname with a leading "@" — used in chat, search rows, etc.
    var handle: String { "@\(nickname)" }
}

/// Mirrors the backend's `PublicProfile` schema.
struct PublicProfile: Codable, Hashable {
    let user: PublicUser
    let statsMinutesTotal: Int?
    let statsEpisodesTotal: Int?
    let favorites: [SocialFavorite]?
    let recentHistory: [SocialStatPoint]?
    let isBlockedByViewer: Bool
    let isBlockingViewer: Bool
}

// MARK: - Sync (favorites / stats)

struct SocialFavorite: Codable, Hashable, Identifiable {
    let id: Int
    let itemId: String
    let title: String
    let posterUrl: String?
    let kind: String
    let addedAt: Date
}

struct SocialStatPoint: Codable, Hashable, Identifiable {
    let id: Int
    let itemId: String
    let title: String
    let posterUrl: String?
    let kind: String
    let episodeNumber: Int?
    let secondsWatched: Int?
    let createdAt: Date
}

// MARK: - Messages

struct SocialMessage: Codable, Hashable, Identifiable {
    let id: Int
    let senderNickname: String
    let recipientNickname: String
    let body: String
    let itemId: String?
    let itemTitle: String?
    let itemPosterUrl: String?
    let createdAt: Date
    let readAt: Date?
    let deleted: Bool
    let reactions: [SocialReaction]
}

struct SocialReaction: Codable, Hashable {
    let userNickname: String
    let emoji: String
}

// MARK: - Inbox

/// Mirrors the backend's `InboxEntry` (`GET /messages/inbox`). One per
/// distinct conversation; powers the in-app bell drawer.
struct InboxEntry: Codable, Hashable, Identifiable {
    let otherNickname: String
    let otherIsOfficial: Bool
    let otherVerified: Bool
    let lastMessage: SocialMessage
    let unreadCount: Int

    var id: String { otherNickname.lowercased() }
}

// MARK: - Auth

struct SocialTokenResponse: Codable {
    let accessToken: String
    let tokenType: String?
    let user: PublicUser
}

// MARK: - Public stats

struct UsersCountStat: Codable, Hashable {
    let total: Int
    let newLast7d: Int
}

struct OnlineStat: Codable, Hashable {
    let online: Int
    let windowMinutes: Int
}

struct CommunityStats: Hashable {
    var online: Int
    var total: Int
    var newLast7d: Int
}

// MARK: - Errors

enum WatchAPIError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden
    case status(Int, body: String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Невалидный URL"
        case .unauthorized: return "Неверный никнейм или пароль"
        case .forbidden: return "Недостаточно прав"
        case .status(let c, let b):
            // Surface the human-readable detail FastAPI returns instead of
            // raw JSON so the UI shows e.g. "Никнейм уже занят" rather than
            // {"detail":"…"}.
            let trimmed = b.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = trimmed.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = obj["detail"] as? String, !detail.isEmpty {
                return detail
            }
            if c == 409 { return "Уже существует" }
            if c == 422 { return "Проверь введённые данные" }
            return "Ошибка \(c)"
        case .decoding(let e): return "Ошибка разбора ответа: \(e.localizedDescription)"
        case .transport(let e): return "Сеть: \(e.localizedDescription)"
        }
    }
}
