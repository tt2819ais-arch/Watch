import Foundation
import Combine

/// Top level app state. Owns shared services and the currently selected section.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Section: String, CaseIterable, Identifiable, Codable {
        case home, anime, movies, series, favorites, stats, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: return "Главная"
            case .anime: return "Аниме"
            case .movies: return "Фильмы"
            case .series: return "Сериалы"
            case .favorites: return "Избранное"
            case .stats: return "Статистика"
            case .settings: return "Настройки"
            }
        }
        var systemImage: String {
            switch self {
            case .home: return "house.fill"
            case .anime: return "sparkles.tv.fill"
            case .movies: return "film.fill"
            case .series: return "tv.fill"
            case .favorites: return "heart.fill"
            case .stats: return "chart.bar.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    @Published var selectedSection: Section = .home
    @Published var sidebarVisible: Bool = false

    let logger = Logger.shared
    let persistence = PersistenceService.shared
    let progress = ProgressService.shared
    let favorites = FavoritesService.shared
    let stats = StatsService.shared
    let sources = ContentSourceRegistry.shared

    private init() {}
}
