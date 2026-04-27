import Foundation

struct Episode: Identifiable, Codable, Hashable {
    let id: String
    let number: Int
    let title: String?
    let durationSeconds: Int?
    let thumbnailURL: URL?

    /// Available qualities and voice tracks. Each Source is a playable URL.
    let sources: [VideoSource]
}

struct VideoSource: Identifiable, Codable, Hashable {
    let id: String
    let url: URL
    let quality: VideoQuality
    let voiceTrack: VoiceTrack
    /// Optional headers required for playback (e.g. Referer for some CDNs).
    let headers: [String: String]
}
