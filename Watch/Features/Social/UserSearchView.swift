import SwiftUI

struct UserSearchView: View {
    @EnvironmentObject private var theme: ThemeManager

    @State private var query: String = ""
    @State private var results: [PublicUser] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var stats: CommunityStats?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            statsHeader
            list
        }
        .background(theme.palette.background.ignoresSafeArea())
        .navigationTitle("Поиск пользователей")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshStats()
        }
    }

    @ViewBuilder
    private var statsHeader: some View {
        if let s = stats {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("\(s.online) онлайн")
                Text("•")
                Text("Всего: \(s.total)")
                if s.newLast7d > 0 {
                    Text("•")
                    Text("+\(s.newLast7d) за неделю")
                }
                Spacer()
            }
            .font(AppFont.caption())
            .foregroundStyle(theme.palette.secondaryText)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func refreshStats() async {
        do {
            let s = try await WatchAPI.shared.communityStats()
            await MainActor.run { self.stats = s }
        } catch {
            // Don't block search UI if the stats endpoint is unreachable.
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.palette.secondaryText)
            TextField("@nickname", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(theme.palette.primaryText)
                .onChange(of: query) { newValue in
                    searchTask?.cancel()
                    searchTask = Task { await runSearch(newValue) }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.palette.secondaryText)
                }
            }
        }
        .padding(12)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(results) { u in
                    NavigationLink(value: SocialDestination.publicProfile(nickname: u.nickname)) {
                        row(u)
                    }
                    .buttonStyle(.plain)
                }
                if results.isEmpty && !query.isEmpty {
                    Text("Никого не нашли")
                        .font(AppFont.subheadline())
                        .foregroundStyle(theme.palette.secondaryText)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ u: PublicUser) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(theme.palette.surfaceElevated)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(initial(of: u.nickname))
                        .font(AppFont.headline())
                        .foregroundStyle(theme.palette.primaryText)
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(u.handle)
                        .font(AppFont.subheadline())
                        .foregroundStyle(theme.palette.primaryText)
                    if u.verified || u.isOfficial {
                        VerifiedBadge(isOfficial: u.isOfficial)
                    }
                }
                if u.isOfficial {
                    Text("Официальный аккаунт Watch")
                        .font(AppFont.caption())
                        .foregroundStyle(theme.palette.secondaryText)
                } else if !u.bio.isEmpty {
                    Text(u.bio)
                        .font(AppFont.caption())
                        .foregroundStyle(theme.palette.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(theme.palette.secondaryText)
        }
        .padding(10)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func initial(of nick: String) -> String {
        String(nick.prefix(1)).uppercased()
    }

    private func runSearch(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            await MainActor.run { self.results = [] }
            return
        }
        // Debounce — wait 200 ms before firing the request to avoid one
        // round-trip per keystroke.
        try? await Task.sleep(nanoseconds: 200_000_000)
        if Task.isCancelled { return }
        do {
            let arr = try await WatchAPI.shared.searchUsers(query: trimmed)
            if Task.isCancelled { return }
            await MainActor.run { self.results = arr }
        } catch {
            await MainActor.run { self.results = [] }
        }
    }
}

/// Strong-typed navigation destinations used inside the social stack.
enum SocialDestination: Hashable {
    case publicProfile(nickname: String)
    case conversation(nickname: String)
}
