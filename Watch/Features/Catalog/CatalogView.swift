import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var theme: ThemeManager
    let kind: ContentKind
    @StateObject private var vm: CatalogViewModel

    init(kind: ContentKind) {
        self.kind = kind
        _vm = StateObject(wrappedValue: CatalogViewModel(kind: kind))
    }

    @State private var showFilters: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    SearchBar()
                    activeFiltersBar
                    grid
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
            .sheet(isPresented: $showFilters) {
                FilterSheet(
                    filter: $vm.filter,
                    availableGenres: vm.availableGenres
                )
                .presentationDetents([.medium, .large])
            }
        }
        .task(id: "catalog-\(kind.rawValue)") {
            await vm.loadGenresIfNeeded()
            await vm.loadIfNeeded()
        }
        .refreshable { await vm.forceReload() }
        .onChange(of: vm.filter) { _ in
            Task { await vm.forceReload() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(kind.title)
                .font(AppFont.largeTitle())
                .foregroundStyle(theme.palette.primaryText)
            Spacer()
            sortMenu
            Button {
                showFilters = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .heavy))
                    .padding(10)
                    .background(theme.palette.surface)
                    .foregroundStyle(theme.palette.primaryText)
                    .clipShape(Circle())
            }
        }
        .padding(.top, 40)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(CatalogFilter.Sort.allCases) { s in
                Button {
                    vm.filter.sort = s
                } label: {
                    HStack {
                        Text(s.displayName)
                        if vm.filter.sort == s { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 16, weight: .heavy))
                .padding(10)
                .background(theme.palette.surface)
                .foregroundStyle(theme.palette.primaryText)
                .clipShape(Circle())
        }
    }

    private var activeFiltersBar: some View {
        let chips = vm.activeFilterChips
        return Group {
            if chips.isEmpty {
                EmptyView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(AppFont.caption())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(theme.palette.surfaceElevated)
                                .foregroundStyle(theme.palette.primaryText)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12)
            ],
            spacing: 16
        ) {
            ForEach(vm.items) { item in
                NavigationLink(value: item) {
                    PosterCard(item: item)
                }
                .buttonStyle(.plain)
            }
            if vm.loading {
                ForEach(0..<6, id: \.self) { _ in
                    PosterCardSkeleton()
                }
            }
        }
    }
}

@MainActor
final class CatalogViewModel: ObservableObject {
    let kind: ContentKind
    @Published var items: [ContentItem] = []
    @Published var loading: Bool = false
    @Published var filter: CatalogFilter = CatalogFilter()
    @Published var availableGenres: [Genre] = []

    init(kind: ContentKind) { self.kind = kind }

    private var didLoad = false
    private var didLoadGenres = false

    func loadIfNeeded() async {
        if didLoad && !items.isEmpty { return }
        await forceReload()
    }

    func forceReload() async {
        loading = true
        let res = await ContentSourceRegistry.shared.aggregate({ [filter, kind] src in
            try await src.search(filter: filter, kind: kind, page: 1)
        }, for: kind)
        // Don't blow away last-known-good results just because a transient
        // cancellation came back empty.
        if !res.isEmpty || items.isEmpty {
            items = applySort(res)
            ProfileLookup.shared.register(items)
        }
        loading = false
        didLoad = true
    }

    private func applySort(_ list: [ContentItem]) -> [ContentItem] {
        switch filter.sort {
        case .popularity: return list
        case .recent:     return list.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .year:       return list.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .rating:     return list.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .name:       return list.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
    }

    func loadGenresIfNeeded() async {
        if didLoadGenres { return }
        // Walk every source that supports this kind and merge their genres
        // by name, keeping the first source's id (so the catalog query maps
        // back to a real API genre id rather than a lowercased label).
        var merged: [String: Genre] = [:]
        for src in ContentSourceRegistry.shared.sources(for: kind) {
            do {
                let list = try await src.genres(kind: kind)
                for g in list where merged[g.name.lowercased()] == nil {
                    merged[g.name.lowercased()] = g
                }
            } catch {
                Logger.shared.warn("genres failed for \(src.id): \(error)", category: .source)
            }
        }
        availableGenres = merged.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        didLoadGenres = !merged.isEmpty
    }

    var activeFilterChips: [String] {
        var c: [String] = []
        if !filter.query.isEmpty { c.append("«\(filter.query)»") }
        if let from = filter.yearFrom, let to = filter.yearTo { c.append("\(from)–\(to)") }
        else if let from = filter.yearFrom { c.append("≥ \(from)") }
        else if let to = filter.yearTo { c.append("≤ \(to)") }
        let nameByID = Dictionary(uniqueKeysWithValues: availableGenres.map { ($0.id, $0.name) })
        c.append(contentsOf: filter.genres.map { nameByID[$0] ?? $0 })
        if filter.sort != .popularity { c.append(filter.sort.displayName) }
        return c
    }
}
