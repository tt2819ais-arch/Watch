import Foundation

struct Episode: Identifiable, Codable, Hashable {
    let id: String
    let number: Int
    let title: String?
    let durationSeconds: Int?
    let thumbnailURL: URL?

    /// Available qualities and voice tracks. Each Source is a playable URL.
    let sources: [VideoSource]

    /// Optional intro / outro time markers in seconds (relative to start).
    /// Used by the auto-skip and "Skip intro" / "Skip outro" buttons.
    var openingStart: Double? = nil
    var openingStop: Double? = nil
    var endingStart: Double? = nil
    var endingStop: Double? = nil
}

struct VideoSource: Identifiable, Codable, Hashable {
    let id: String
    let url: URL
    let quality: VideoQuality
    let voiceTrack: VoiceTrack
    /// Optional headers required for playback (e.g. Referer for some CDNs).
    let headers: [String: String]
}
