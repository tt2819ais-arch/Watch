import Foundation

struct VoiceTrack: Codable, Hashable, Identifiable {
    /// Stable id (studio + language).
    let id: String
    /// Studio / dubber name (e.g. "AniLibria", "AniDub", "LostFilm").
    let studio: String
    /// Language tag (e.g. "ru", "en", "jp+sub_ru").
    let language: String

    var displayName: String {
        if studio.isEmpty { return language.uppercased() }
        return "\(studio) — \(language.uppercased())"
    }
}

extension VoiceTrack {
    static let unknown = VoiceTrack(id: "unknown", studio: "", language: "ru")
}
