import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    titleHeader
                    SearchBar()
                    if !vm.continueWatching.isEmpty {
                        section(title: "Продолжить просмотр") {
                            ContinueWatchingRow(progressItems: vm.continueWatching)
                        }
                    }
                    section(title: "Популярное аниме") {
                        contentRow(items: vm.popularAnime)
                    }
                    section(title: "Фильмы") {
                        contentRow(items: vm.popularMovies)
                    }
                    section(title: "Сериалы") {
                        contentRow(items: vm.popularSeries)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(theme.palette.background.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationDestination(for: ContentItem.self) { item in
                DetailView(item: item)
            }
            .navigationDestination(for: WatchProgress.self) { progress in
                if let item = vm.itemFor(progress: progress) {
                    DetailView(item: item, autoplayEpisodeNumber: progress.episodeNumber)
                }
            }
        }
        .task(id: "home-once") { await vm.loadAllIfNeeded() }
        .refreshable { await vm.forceReload() }
        .sheet(item: $randomTarget) { item in
            NavigationStack {
                DetailView(item: item)
            }
        }
    }

    @State private var randomTarget: ContentItem?

    private var titleHeader: some View {
        HStack(spacing: 10) {
            Text("Привет 👋")
                .font(AppFont.largeTitle())
                .foregroundStyle(theme.palette.primaryText)
            Spacer()
            Button {
                randomTarget = vm.randomPick()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .heavy))
                    .padding(10)
                    .background(theme.palette.surface)
                    .foregroundStyle(theme.palette.primaryText)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Случайный выбор")
        }
        .padding(.top, 40)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppFont.title2())
                .foregroundStyle(theme.palette.primaryText)
            content()
        }
    }

    private func contentRow(items: [ContentItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if items.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        PosterCardSkeleton()
                    }
                } else {
                    ForEach(items) { item in
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

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var popularAnime: [ContentItem] = []
    @Published var popularMovies: [ContentItem] = []
    @Published var popularSeries: [ContentItem] = []
    @Published var continueWatching: [WatchProgress] = []
    @Published var itemsByID: [String: ContentItem] = [:]

    private var didLoadOnce = false
    private var inFlight: Bool = false

    func loadAllIfNeeded() async {
        if didLoadOnce { return }
        await forceReload()
    }

    func forceReload() async {
        if inFlight { return }
        inFlight = true
        defer { inFlight = false }
        // Run all three feed loads in parallel — speeds up first paint and
        // avoids cancellations cascading from a long serial chain.
        async let anime: Void = loadKind(.anime, into: \.popularAnime)
        async let movies: Void = loadKind(.movie, into: \.popularMovies)
        async let series: Void = loadKind(.series, into: \.popularSeries)
        _ = await (anime, movies, series)
        continueWatching = Array(ProgressService.shared.lastWatched.prefix(10))
        didLoadOnce = true
    }

    private func loadKind(_ kind: ContentKind, into keypath: ReferenceWritableKeyPath<HomeViewModel, [ContentItem]>) async {
        let items = await ContentSourceRegistry.shared.aggregate({ source in
            try await source.popular(kind: kind, limit: 20)
        }, for: kind)
        if !items.isEmpty || self[keyPath: keypath].isEmpty {
            self[keyPath: keypath] = items
            for it in items { itemsByID[it.id] = it }
            ProfileLookup.shared.register(items)
        }
    }

    func itemFor(progress: WatchProgress) -> ContentItem? {
        itemsByID[progress.itemID]
    }

    func randomPick() -> ContentItem? {
        let pool = popularAnime + popularMovies + popularSeries
        return pool.randomElement()
    }
}
