import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var theme: ThemeManager
    @StateObject private var vm = SearchViewModel()
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            input
            kindPicker
            content
        }
        .background(theme.palette.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(false)
        .navigationTitle("Поиск")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .onChange(of: vm.query) { _, _ in vm.fetchSuggestionsDebounced() }
        .onChange(of: vm.kind) { _, _ in vm.fetchSuggestionsDebounced() }
    }

    private var input: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(theme.palette.secondaryText)
            TextField("Введите название…", text: $vm.query)
                .font(AppFont.body())
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .foregroundStyle(theme.palette.primaryText)
            if !vm.query.isEmpty {
                Button { vm.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.palette.secondaryText)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach(ContentKind.allCases) { kind in
                Button {
                    vm.kind = kind
                } label: {
                    Text(kind.title)
                        .font(AppFont.subheadline())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(vm.kind == kind ? theme.palette.surfaceElevated : Color.clear)
                        .foregroundStyle(theme.palette.primaryText)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if vm.query.isEmpty {
            emptyState
        } else if vm.suggestions.isEmpty && !vm.loading {
            VStack {
                Spacer()
                Text("Ничего не найдено")
                    .font(AppFont.headline())
                    .foregroundStyle(theme.palette.secondaryText)
                Spacer()
            }
        } else {
            List {
                ForEach(vm.suggestions) { item in
                    NavigationLink(value: item) {
                        SearchSuggestionRow(item: item, query: vm.query)
                    }
                    .listRowBackground(theme.palette.background)
                    .listRowSeparatorTint(theme.palette.separator)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationDestination(for: ContentItem.self) { item in
                DetailView(item: item)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(theme.palette.secondaryText)
            Text("Начни печатать —\nприложение угадает что ты ищешь")
                .multilineTextAlignment(.center)
                .font(AppFont.body())
                .foregroundStyle(theme.palette.secondaryText)
            Spacer()
        }
    }
}

struct SearchSuggestionRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let item: ContentItem
    let query: String

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.posterURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color.clear
            }
            .frame(width: 50, height: 70)
            .background(theme.palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                highlighted(item.title, query: query)
                    .font(AppFont.headline())
                    .foregroundStyle(theme.palette.primaryText)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.kind.title)
                        .font(AppFont.caption())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.palette.surfaceElevated)
                        .clipShape(Capsule())
                    if let y = item.year {
                        Text("\(String(y))")
                            .font(AppFont.caption())
                    }
                    if !item.genres.isEmpty {
                        Text(item.genres.prefix(2).joined(separator: " · "))
                            .font(AppFont.caption())
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(theme.palette.secondaryText)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func highlighted(_ s: String, query: String) -> Text {
        guard !query.isEmpty,
              let range = s.range(of: query, options: .caseInsensitive) else {
            return Text(s)
        }
        let pre = String(s[..<range.lowerBound])
        let mid = String(s[range])
        let post = String(s[range.upperBound...])
        return Text(pre) + Text(mid).underline() + Text(post)
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var kind: ContentKind = .anime
    @Published var suggestions: [ContentItem] = []
    @Published var loading: Bool = false

    private var debounceTask: Task<Void, Never>?

    func fetchSuggestionsDebounced() {
        debounceTask?.cancel()
        let q = query
        let k = kind
        if q.trimmingCharacters(in: .whitespaces).isEmpty {
            suggestions = []
            return
        }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await self?.fetch(query: q, kind: k)
        }
    }

    private func fetch(query: String, kind: ContentKind) async {
        loading = true
        let results = await ContentSourceRegistry.shared.aggregate({ src in
            try await src.suggest(query: query, kind: kind)
        }, for: kind)
        // Sort by best match (prefix > contains).
        let q = query.lowercased()
        suggestions = results.sorted { a, b in
            let aP = a.title.lowercased().hasPrefix(q) ? 0 : 1
            let bP = b.title.lowercased().hasPrefix(q) ? 0 : 1
            if aP != bP { return aP < bP }
            return a.title.count < b.title.count
        }
        loading = false
    }
}
