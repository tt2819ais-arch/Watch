import Foundation
import Combine

/// Top level app state. Owns shared services and the currently selected section.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Section: String, CaseIterable, Identifiable, Codable {
        case home, anime, movies, series, profile, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: return "Главная"
            case .anime: return "Аниме"
            case .movies: return "Фильмы"
            case .series: return "Сериалы"
            case .profile: return "Профиль"
            case .settings: return "Настройки"
            }
        }
        var systemImage: String {
            switch self {
            case .home: return "house.fill"
            case .anime: return "sparkles.tv.fill"
            case .movies: return "film.fill"
            case .series: return "tv.fill"
            case .profile: return "person.crop.circle.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    @Published var selectedSection: Section = .home

    /// Set by `onOpenURL` (deep links like `watch://u/<nickname>`).
    /// `ProfileTabRoot` consumes it on appear and clears it.
    @Published var pendingProfileNickname: String?

    let logger = Logger.shared
    let persistence = PersistenceService.shared
    let progress = ProgressService.shared
    let favorites = FavoritesService.shared
    let stats = StatsService.shared
    let sources = ContentSourceRegistry.shared

    private init() {}

    /// Returns true if the URL was understood and routed; false otherwise.
    @discardableResult
    func handle(url: URL) -> Bool {
        // Accept both `watch://u/<nick>` and `https://watch.../u/<nick>` shapes.
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        var path = comps.path
        if path.hasPrefix("/") { path.removeFirst() }
        let segments = path.split(separator: "/").map(String.init)
        if comps.scheme == SocialConfig.urlScheme,
           let host = comps.host, host == SocialConfig.userPathPrefix,
           let nick = segments.first {
            routeToProfile(nickname: nick)
            return true
        }
        if segments.first == SocialConfig.userPathPrefix, segments.count >= 2 {
            routeToProfile(nickname: segments[1])
            return true
        }
        return false
    }

    private func routeToProfile(nickname: String) {
        selectedSection = .profile
        pendingProfileNickname = nickname
    }
}
