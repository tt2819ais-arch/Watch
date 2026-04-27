import SwiftUI

/// Local activity: stats / events / continue-watching / favourites. Used by
/// `SelfProfileView` (signed-in tab content) and standalone for previews.
/// Does NOT host its own `NavigationStack` — the parent provides one and
/// owns the destinations.
struct ProfileBody: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var stats = StatsService.shared
    @ObservedObject private var fav = FavoritesService.shared
    @ObservedObject private var progress = ProgressService.shared

    @State private var period: StatsService.Period = .week

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            statsCard
            periodPicker
            eventsSection
            continueSection
            favoritesSection
        }
    }

    private var statsCard: some View {
        let s = stats.summary(for: period)
        return HStack(spacing: 12) {
            statBlock(title: "Время", value: s.prettyDuration, icon: "clock.fill")
            statBlock(title: "Серий", value: "\(s.episodeCount)", icon: "play.tv.fill")
            statBlock(title: "В избранном", value: "\(fav.items.count)", icon: "heart.fill")
        }
    }

    private func statBlock(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .heavy))
                Spacer()
            }
            Text(value)
                .font(AppFont.title2())
                .foregroundStyle(theme.palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(AppFont.footnote())
                .foregroundStyle(theme.palette.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var periodPicker: some View {
        Picker("", selection: $period) {
            ForEach(StatsService.Period.allCases) { p in
                Text(p.displayName).tag(p)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var eventsSection: some View {
        let recent = stats.events.suffix(20).reversed()
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Последние просмотры")
                    .font(AppFont.title3())
                    .foregroundStyle(theme.palette.primaryText)
                VStack(spacing: 6) {
                    ForEach(Array(recent), id: \.id) { e in
                        eventRow(e)
                    }
                }
            }
        }
    }

    private func eventRow(_ e: WatchEvent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: e.kind == .anime ? "sparkles.tv.fill" : (e.kind == .movie ? "film.fill" : "tv.fill"))
                .frame(width: 22)
                .foregroundStyle(theme.palette.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.itemTitle)
                    .font(AppFont.subheadline())
                    .foregroundStyle(theme.palette.primaryText)
                    .lineLimit(1)
                Text("Серия \(e.episodeNumber) — \(Int(e.watchedSeconds / 60)) мин")
                    .font(AppFont.footnote())
                    .foregroundStyle(theme.palette.secondaryText)
            }
            Spacer()
            Text(e.timestamp, style: .relative)
                .font(AppFont.footnote())
                .foregroundStyle(theme.palette.secondaryText)
        }
        .padding(10)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var continueSection: some View {
        if !progress.lastWatched.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Продолжить просмотр")
                    .font(AppFont.title3())
                    .foregroundStyle(theme.palette.primaryText)
                ContinueWatchingRow(progressItems: Array(progress.lastWatched.prefix(10)))
            }
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        if !fav.items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Избранное")
                    .font(AppFont.title3())
                    .foregroundStyle(theme.palette.primaryText)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 16) {
                    ForEach(fav.items) { item in
                        NavigationLink(value: item) {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Lookup table to resolve a WatchProgress back to its ContentItem when navigating
/// from Profile. We keep a lightweight in-memory cache populated by other views.
@MainActor
final class ProfileLookup {
    static let shared = ProfileLookup()
    private var byID: [String: ContentItem] = [:]

    func register(_ items: [ContentItem]) {
        for it in items { byID[it.id] = it }
    }

    func item(for progress: WatchProgress) -> ContentItem? {
        byID[progress.itemID]
    }
}
