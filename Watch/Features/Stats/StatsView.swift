import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @StateObject private var stats = StatsService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Статистика")
                        .font(AppFont.largeTitle())
                        .foregroundStyle(theme.palette.primaryText)
                        .padding(.top, 40)

                    grid

                    Text("Последние просмотры")
                        .font(AppFont.title3())
                        .foregroundStyle(theme.palette.primaryText)

                    VStack(spacing: 6) {
                        ForEach(stats.events.suffix(20).reversed()) { e in
                            row(for: e)
                        }
                        if stats.events.isEmpty {
                            Text("Пока нет данных. Включи серию — статистика появится здесь.")
                                .font(AppFont.subheadline())
                                .foregroundStyle(theme.palette.secondaryText)
                                .padding(.vertical, 16)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(theme.palette.background.ignoresSafeArea())
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            ForEach(StatsService.Period.allCases) { p in
                let s = stats.summary(for: p)
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.displayName)
                        .font(AppFont.subheadline())
                        .foregroundStyle(theme.palette.secondaryText)
                    Text(s.prettyDuration)
                        .font(AppFont.title2())
                        .foregroundStyle(theme.palette.primaryText)
                    Text("\(s.episodeCount) серий")
                        .font(AppFont.footnote())
                        .foregroundStyle(theme.palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(theme.palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func row(for e: WatchEvent) -> some View {
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
}
