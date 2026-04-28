import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var theme: ThemeManager
    @StateObject private var vm: DetailViewModel
    /// Sheet/cover presentation flow:
    ///   nil → idle.
    ///   .preplay(ep) → PrePlayPicker sheet open.
    ///   .player(ep) → fullScreenCover with player.
    /// Using a single state machine avoids racing two unrelated SwiftUI
    /// presentations attached to the same view, which silently swallowed
    /// presentations on iOS 16/17 in earlier builds.
    @State private var stage: PresentationStage?
    @State private var noSourcesAlert: Bool = false

    enum PresentationStage: Identifiable, Hashable {
        case preplay(Episode)
        case player(Episode)
        var id: String {
            switch self {
            case .preplay(let e): return "pre-\(e.id)"
            case .player(let e):  return "play-\(e.id)"
            }
        }
        var episode: Episode {
            switch self {
            case .preplay(let e), .player(let e): return e
            }
        }
        var isPlayer: Bool { if case .player = self { return true }; return false }
    }

    init(item: ContentItem, autoplayEpisodeNumber: Int? = nil) {
        _vm = StateObject(wrappedValue: DetailViewModel(item: item, autoplayEpisodeNumber: autoplayEpisodeNumber))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                watchButton
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
            if let n = vm.autoplayEpisodeNumber,
               let ep = vm.episodes.first(where: { $0.number == n }) {
                openPrePlay(for: ep)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { if case .preplay = stage { return true } else { return false } },
                set: { if !$0, case .preplay = stage { stage = nil } }
            )
        ) {
            if case .preplay(let ep) = stage {
                PrePlayPicker(item: vm.item, episode: ep) { chosen in
                    if let updated = chosen {
                        // Switch to player stage; the cover takes over after
                        // the sheet's dismiss animation finishes.
                        stage = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                            stage = .player(updated)
                        }
                    } else {
                        stage = nil
                    }
                }
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled(false)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { if case .player = stage { return true } else { return false } },
                set: { if !$0, case .player = stage { stage = nil } }
            )
        ) {
            if case .player(let ep) = stage {
                PlayerView(item: vm.item, episodes: vm.episodes, initialEpisode: ep)
            }
        }
    }

    private func openPrePlay(for ep: Episode) {
        // Defensive: only present if the episode actually has streamable
        // sources, so the user never lands on an empty picker.
        guard !ep.sources.isEmpty else {
            Logger.shared.warn("openPrePlay called with empty sources for ep \(ep.number)", category: .player)
            return
        }
        stage = .preplay(ep)
    }

    private var watchButton: some View {
        Button {
            // If episodes resolved with no playable sources at all, surface
            // an alert so the user has actionable feedback instead of a
            // dead button. Otherwise launch the pre-play picker.
            guard !vm.loading else { return }
            guard let ep = bestResumeEpisode(), !ep.sources.isEmpty else {
                noSourcesAlert = true
                return
            }
            openPrePlay(for: ep)
        } label: {
            let active = !vm.episodes.isEmpty
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(active ? theme.palette.background.opacity(0.15) : Color.clear)
                        .frame(width: 32, height: 32)
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .heavy))
                        .offset(x: 1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(watchButtonTitle)
                        .font(AppFont.headline())
                    if active, vm.episodes.count > 1, let ep = bestResumeEpisode() {
                        Text(resumeSubtitle(for: ep))
                            .font(AppFont.caption())
                            .foregroundStyle((active ? theme.palette.background : theme.palette.secondaryText).opacity(0.7))
                    }
                }
                Spacer(minLength: 0)
                if active {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .heavy))
                        .opacity(0.55)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(active ? theme.palette.primaryText : theme.palette.surface)
            )
            .foregroundStyle(active ? theme.palette.background : theme.palette.secondaryText)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.palette.separator.opacity(active ? 0 : 1), lineWidth: 1)
            )
            .shadow(color: active ? theme.palette.primaryText.opacity(0.18) : .clear,
                    radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(vm.loading && vm.episodes.isEmpty)
        .alert("Нет источников", isPresented: $noSourcesAlert) {
            Button("Обновить") { Task { await vm.loadEpisodes() } }
            Button("ОК", role: .cancel) {}
        } message: {
            Text("Ни один источник не вернул поток для этого тайтла. Попробуйте ещё раз или выберите другой.")
        }
    }

    private func resumeSubtitle(for ep: Episode) -> String {
        if let prog = ProgressService.shared.progress(for: vm.item.id, episodeID: ep.id),
           prog.position > 30 && !prog.isFinished {
            let pct = Int((prog.position / max(1, prog.duration)) * 100)
            return "Серия \(ep.number) · \(pct)% просмотрено"
        }
        return "Серия \(ep.number) из \(vm.episodes.count)"
    }

    private var watchButtonTitle: String {
        if vm.loading && vm.episodes.isEmpty { return "Загрузка…" }
        if vm.episodes.isEmpty { return "Нет источников" }
        if let resume = bestResumeEpisode(),
           let prog = ProgressService.shared.progress(for: vm.item.id, episodeID: resume.id),
           prog.position > 30 && !prog.isFinished {
            return "Продолжить"
        }
        return "Смотреть"
    }

    private func bestResumeEpisode() -> Episode? {
        // Most recent unfinished episode by progress; fall back to the first
        // unwatched, then the first overall.
        let progress = ProgressService.shared
        if let resume = vm.episodes.first(where: { ep in
            if let p = progress.progress(for: vm.item.id, episodeID: ep.id) {
                return !p.isFinished && p.position > 30
            }
            return false
        }) {
            return resume
        }
        if let firstUnwatched = vm.episodes.first(where: { ep in
            progress.progress(for: vm.item.id, episodeID: ep.id)?.isFinished != true
        }) {
            return firstUnwatched
        }
        return vm.episodes.first
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
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let orig = vm.item.originalTitle, orig != vm.item.title {
                    Text(orig)
                        .font(AppFont.body())
                        .foregroundStyle(theme.palette.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var meta: some View {
        // Long titles + many genres used to push tags off-screen because
        // they were laid out in a single non-wrapping HStack. Render the
        // chips in a horizontally-scrollable strip so they always stay
        // inside the safe area.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let y = vm.item.year {
                    tag("\(String(y))")
                }
                tag(vm.item.kind.title)
                if let total = vm.item.totalEpisodes, vm.item.kind != .movie {
                    tag("\(total) серий")
                }
                ForEach(vm.item.genres.prefix(6), id: \.self) { g in
                    tag(g)
                }
            }
            .padding(.vertical, 1)
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
                    openPrePlay(for: ep)
                } label: {
                    EpisodeRow(item: vm.item, episode: ep)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    let watched = ProgressService.shared.progress(for: vm.item.id, episodeID: ep.id)?.isFinished == true
                    Button {
                        ProgressService.shared.setWatched(
                            !watched,
                            itemID: vm.item.id,
                            episodeID: ep.id,
                            episodeNumber: ep.number,
                            duration: Double(ep.durationSeconds ?? 0)
                        )
                    } label: {
                        Label(watched ? "Снять отметку" : "Отметить как просмотренную",
                              systemImage: watched ? "circle" : "checkmark.circle.fill")
                    }
                }
            }
        }
    }
}

struct EpisodeRow: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var progressSvc = ProgressService.shared
    let item: ContentItem
    let episode: Episode

    private var progress: WatchProgress? {
        progressSvc.progress(for: item.id, episodeID: episode.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Tappable watched-toggle checkbox in place of the static
            // episode-number tile. Tapping it flips the "watched" flag for
            // this episode without opening the player.
            Button {
                let watched = progress?.isFinished == true
                progressSvc.setWatched(
                    !watched,
                    itemID: item.id,
                    episodeID: episode.id,
                    episodeNumber: episode.number,
                    duration: Double(episode.durationSeconds ?? 0)
                )
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(progress?.isFinished == true ? theme.palette.accent : theme.palette.surfaceElevated)
                        .frame(width: 56, height: 56)
                    if progress?.isFinished == true {
                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(episode.number)")
                            .font(AppFont.title2())
                            .foregroundStyle(theme.palette.primaryText)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(progress?.isFinished == true ? "Снять отметку \(episode.number)" : "Отметить \(episode.number) как просмотренную")

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
                        collected.append(contentsOf: try await kodik.episodesByKinopoiskID(kpID, kind: item.kind))
                    } catch {
                        Logger.shared.warn("Kodik fallback by kinopoisk_id failed: \(error)", category: .source)
                    }
                }
                if collected.isEmpty {
                    do {
                        collected.append(contentsOf: try await kodik.episodesByTitle(item.title, year: item.year, kind: item.kind))
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
