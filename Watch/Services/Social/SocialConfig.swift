import Foundation

enum SocialConfig {
    /// Base URL of the Watch backend (FastAPI on Fly.io).
    /// Override with the `WATCH_BACKEND_URL` Info.plist key when needed.
    static let backendURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "WatchBackendURL") as? String,
           let url = URL(string: raw), !raw.isEmpty {
            return url
        }
        return URL(string: "https://watch-backend-cwwkqdui.fly.dev")!
    }()

    /// Custom URL scheme for sharing user profile links: `watch://u/<nickname>`.
    static let urlScheme = "watch"
    static let userPathPrefix = "u"

    /// Build a `watch://u/<nickname>` URL safely. Nicknames are normally
    /// `[a-zA-Z0-9_]` per sign-up validation, but the backend may evolve
    /// to allow Unicode display names — percent-encode and fall back to
    /// a generic profile URL so a malformed nickname can never crash the
    /// share sheet via a force-unwrap.
    static func profileShareURL(forNickname nickname: String) -> URL {
        let escaped = nickname.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        if !escaped.isEmpty, let url = URL(string: "\(urlScheme)://\(userPathPrefix)/\(escaped)") {
            return url
        }
        return URL(string: "\(urlScheme)://\(userPathPrefix)/")
            ?? URL(string: "https://watch.app")!
    }
}
