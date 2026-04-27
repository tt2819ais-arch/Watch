import Foundation

enum VideoQuality: String, Codable, CaseIterable, Identifiable, Comparable {
    case sd = "480p"
    case hd = "720p"
    case fhd = "1080p"
    case uhd = "2160p"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var orderValue: Int {
        switch self {
        case .sd: return 480
        case .hd: return 720
        case .fhd: return 1080
        case .uhd: return 2160
        }
    }

    static func < (lhs: VideoQuality, rhs: VideoQuality) -> Bool {
        lhs.orderValue < rhs.orderValue
    }
}
