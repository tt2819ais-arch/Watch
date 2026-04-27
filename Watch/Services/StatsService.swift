import Foundation
import Combine

@MainActor
final class StatsService: ObservableObject {
    static let shared = StatsService()

    @Published private(set) var events: [WatchEvent] = []

    private let key = "watch_events"

    private init() {
        events = PersistenceService.shared.load([WatchEvent].self, key: key) ?? []
        Logger.shared.info("Loaded \(events.count) watch events", category: .stats)
    }

    /// Records an incremental viewing chunk. We rate-limit calls to once per ~30s
    /// from the player so the events list stays small.
    func record(itemID: String, itemTitle: String, kind: ContentKind, episodeNumber: Int, watchedSeconds: Double) {
        guard watchedSeconds > 0 else { return }
        let event = WatchEvent(
            itemID: itemID,
            itemTitle: itemTitle,
            kind: kind,
            episodeNumber: episodeNumber,
            watchedSeconds: watchedSeconds
        )
        events.append(event)
        persist()
    }

    func clearAll() {
        events.removeAll()
        persist()
    }

    // MARK: - Aggregations

    enum Period: String, CaseIterable, Identifiable {
        case today, yesterday, week, month, all
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .today: return "Сегодня"
            case .yesterday: return "Вчера"
            case .week: return "Неделя"
            case .month: return "Месяц"
            case .all: return "Всё время"
            }
        }
    }

    struct Summary {
        let totalSeconds: Double
        let episodeCount: Int

        var totalMinutes: Int { Int(totalSeconds / 60) }
        var totalHours: Double { totalSeconds / 3600 }
        var prettyDuration: String {
            let h = Int(totalSeconds) / 3600
            let m = (Int(totalSeconds) % 3600) / 60
            if h > 0 {
                return "\(h) ч \(m) мин"
            }
            return "\(m) мин"
        }
    }

    func summary(for period: Period, calendar: Calendar = .current, now: Date = Date()) -> Summary {
        let range = dateRange(for: period, calendar: calendar, now: now)
        let filtered = events.filter { range.contains($0.timestamp) }
        let totalSeconds = filtered.reduce(0.0) { $0 + $1.watchedSeconds }
        // Distinct episodes within this period.
        let episodeCount = Set(filtered.map { "\($0.itemID)::\($0.episodeNumber)" }).count
        return Summary(totalSeconds: totalSeconds, episodeCount: episodeCount)
    }

    private func dateRange(for period: Period, calendar: Calendar, now: Date) -> Range<Date> {
        let startOfToday = calendar.startOfDay(for: now)
        switch period {
        case .today:
            let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
            return startOfToday..<end
        case .yesterday:
            let start = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            return start..<startOfToday
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
            let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
            return start..<end
        case .month:
            let start = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
            let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
            return start..<end
        case .all:
            return Date.distantPast..<Date.distantFuture
        }
    }

    private func persist() {
        PersistenceService.shared.save(events, key: key)
    }
}
