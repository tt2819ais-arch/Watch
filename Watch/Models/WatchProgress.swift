import Foundation

/// Stores last playback position for a specific (item, episode).
struct WatchProgress: Codable, Hashable, Identifiable {
    var id: String { "\(itemID)::\(episodeID)" }
    let itemID: String
    let episodeID: String
    let episodeNumber: Int
    /// Position in seconds.
    var position: Double
    /// Total duration in seconds (0 if unknown).
    var duration: Double
    var updatedAt: Date

    var positionMinutes: Int { Int(position / 60) }
    var durationMinutes: Int { Int(duration / 60) }

    var isFinished: Bool {
        guard duration > 0 else { return false }
        return position / duration >= 0.95
    }

    var fractionComplete: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}
