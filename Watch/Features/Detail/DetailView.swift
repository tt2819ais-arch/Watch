import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var theme: ThemeManager
    @StateObject private var vm: DetailViewModel
    @State private var presentedEpisode: Episode?

    init(item: ContentItem, autoplayEpisodeNumber: Int? = nil) {
        _vm = StateObject(wrappedValue: DetailViewModel(item: item, autoplayEpisodeNumber: autoplayEpisodeNumber))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                meta
                if let desc = vm.item.descriptionText, !desc.isEmpty {
                    descriptionBlock(desc)
                }
                episodesBlock
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(theme.palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    vm.toggleFavorite()
                } label: {
                    Image(systemName: vm.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .heavy))
                }
            }
        }
        .task {
            await vm.loadEpisodes()
            if let n = vm.autoplayEpisodeNumber, let ep = vm.episodes.first(where: { $0.number == n }) {
                presentedEpisode = ep
            }
        }
        .fullScreenCover(item: $presentedEpisode) { ep in
            PlayerView(item: vm.item, episodes: vm.episodes, initialEpisode: ep)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: vm.item.bannerURL ?? vm.item.posterURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    theme.palette.surface
                }
            }
            .frame(height: 360)
            .clipped()
            .overlay(LinearGradient(
                colors: [.clear, theme.palette.background],
                startPoint: .top, endPoint: .bottom
            ))
            VStack(alignment: .leading, spacing: 6) {
                Text(vm.item.title)
                    .font(AppFont.largeTitle())
                    .foregroundStyle(theme.palette.primaryText)
                if let orig = vm.item.originalTitle, orig != vm.item.title {
                    Text(orig)
                        .font(AppFont.body())
                        .foregroundStyle(theme.palette.secondaryText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var meta: some View {
        HStack(spacing: 8) {
            if let y = vm.item.year {
                tag("\(String(y))")
            }
            tag(vm.item.kind.title)
            if let total = vm.item.totalEpisodes, vm.item.kind != .movie {
                tag("\(total) серий")
            }
            ForEach(vm.item.genres.prefix(3), id: \.self) { g in
                tag(g)
            }
            Spacer()
        }
    }

    private func tag(_ s: String) -> some View {
        Text(s)
            .font(AppFont.caption())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(theme.palette.surfaceElevated)
            .foregroundStyle(theme.palette.primaryText)
            .clipShape(Capsule())
    }

    private func descriptionBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Описание")
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            Text(text)
                .font(AppFont.body())
                .foregroundStyle(theme.palette.secondaryText)
        }
    }

    private var episodesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(vm.item.kind == .movie ? "Источники" : "Серии")
                    .font(AppFont.title3())
                    .foregroundStyle(theme.palette.primaryText)
                Spacer()
                if vm.loading { ProgressView().tint(theme.palette.accent) }
            }
            if vm.episodes.isEmpty && !vm.loading {
                Text("Нет доступных источников. Попробуйте позже или настройте API ключи в Настройках.")
                    .font(AppFont.subheadline())
                    .foregroundStyle(theme.palette.secondaryText)
                    .padding(.vertical, 8)
            }
            ForEach(vm.episodes) { ep in
                Button {
                    presentedEpisode = ep
                } label: {
                    EpisodeRow(item: vm.item, episode: ep)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct EpisodeRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let item: ContentItem
    let episode: Episode

    var body: some View {
        let progress = ProgressService.shared.progress(for: item.id, episodeID: episode.id)
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.palette.surfaceElevated)
                    .frame(width: 56, height: 56)
                Text("\(episode.number)")
                    .font(AppFont.title2())
                    .foregroundStyle(theme.palette.primaryText)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.kind == .movie ? (episode.title ?? "Фильм") : "Серия \(episode.number)")
                    .font(AppFont.headline())
                    .foregroundStyle(theme.palette.primaryText)
                if let title = episode.title, !title.isEmpty, item.kind != .movie {
                    Text(title)
                        .font(AppFont.subheadline())
                        .foregroundStyle(theme.palette.secondaryText)
                        .lineLimit(1)
                }
                if let p = progress {
                    HStack(spacing: 6) {
                        Image(systemName: p.isFinished ? "checkmark.circle.fill" : "play.circle.fill")
                        Text(p.isFinished ? "Просмотрено" : "Остановился на \(p.positionMinutes) мин")
                    }
                    .font(AppFont.caption())
                    .foregroundStyle(theme.palette.secondaryText)
                }
            }
            Spacer()
            Image(systemName: "play.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(theme.palette.primaryText)
                .padding(10)
                .background(theme.palette.surface)
                .clipShape(Circle())
        }
        .padding(.vertical, 6)
    }
}

@MainActor
final class DetailViewModel: ObservableObject {
    let item: ContentItem
    let autoplayEpisodeNumber: Int?
    @Published var episodes: [Episode] = []
    @Published var loading: Bool = false
    @Published var isFavorite: Bool = false

    init(item: ContentItem, autoplayEpisodeNumber: Int? = nil) {
        self.item = item
        self.autoplayEpisodeNumber = autoplayEpisodeNumber
        self.isFavorite = FavoritesService.shared.isFavorite(item.id)
    }

    func loadEpisodes() async {
        loading = true
        var collected: [Episode] = []

        // Primary source for this item.
        for src in ContentSourceRegistry.shared.sources where src.id == item.sourceID {
            do {
                collected.append(contentsOf: try await src.episodes(for: item))
            } catch {
                Logger.shared.warn("episodes(for:) failed for \(src.id): \(error)", category: .source)
            }
        }

        // For PoiskKino items the metadata source has no streams — fall back
        // to Kodik using kinopoisk_id from the item's composite id.
        if collected.isEmpty, item.sourceID == "poiskkino" {
            if let kodik = ContentSourceRegistry.shared.sources.first(where: { $0.id == "kodik" }) as? KodikSource {
                let kpID = item.id.split(separator: "|").last.map(String.init) ?? ""
                if !kpID.isEmpty {
                    do {
                        collected.append(contentsOf: try await kodik.episodesByKinopoiskID(kpID))
                    } catch {
                        Logger.shared.warn("Kodik fallback by kinopoisk_id failed: \(error)", category: .source)
                    }
                }
                if collected.isEmpty {
                    do {
                        collected.append(contentsOf: try await kodik.episodesByTitle(item.title, year: item.year))
                    } catch {
                        Logger.shared.warn("Kodik fallback by title failed: \(error)", category: .source)
                    }
                }
            }
        }

        episodes = collected.sorted { $0.number < $1.number }
        loading = false
    }

    func toggleFavorite() {
        FavoritesService.shared.toggle(item)
        isFavorite = FavoritesService.shared.isFavorite(item.id)
    }
}
