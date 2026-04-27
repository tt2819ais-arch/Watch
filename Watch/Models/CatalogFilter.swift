import Foundation

struct CatalogFilter: Equatable {
    var query: String = ""
    var genres: Set<String> = []
    var yearFrom: Int? = nil
    var yearTo: Int? = nil
    var sort: Sort = .popularity

    enum Sort: String, CaseIterable, Identifiable {
        case popularity, recent, year, rating, name
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .popularity: return "Популярные"
            case .recent:     return "Недавние"
            case .year:       return "По году"
            case .rating:     return "По рейтингу"
            case .name:       return "По названию"
            }
        }
    }
}
