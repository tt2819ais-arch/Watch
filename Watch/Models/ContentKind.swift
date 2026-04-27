import Foundation

enum ContentKind: String, Codable, CaseIterable, Identifiable {
    case anime
    case movie
    case series

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anime: return "Аниме"
        case .movie: return "Фильмы"
        case .series: return "Сериалы"
        }
    }
}
