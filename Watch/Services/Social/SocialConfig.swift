import Foundation

enum SocialConfig {
    /// Base URL of the Watch backend (FastAPI on Fly.io).
    /// Override with the `WATCH_BACKEND_URL` Info.plist key when needed.
    static let backendURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "WatchBackendURL") as? String,
           let url = URL(string: raw), !raw.isEmpty {
            return url
        }
        return URL(string: "https://watch-backend-vvqgiseh.fly.dev")!
    }()

    /// Custom URL scheme for sharing user profile links: `watch://u/<nickname>`.
    static let urlScheme = "watch"
    static let userPathPrefix = "u"
}
