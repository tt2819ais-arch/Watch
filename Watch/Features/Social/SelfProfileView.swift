import SwiftUI

/// Profile tab content for the signed-in user. Renders an Insta/VK-style
/// header (avatar, stats grid, bio) plus action buttons. Settings live
/// behind the gear icon in the toolbar — there is no separate Settings
/// tab any more.
struct SelfProfileView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var stats = StatsService.shared
    @ObservedObject private var favorites = FavoritesService.shared
    @State private var path = NavigationPath()
    @State private var bioDraft: String = ""
    @State private var editingBio: Bool = false
    @State private var profile: PublicProfile?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let user = auth.currentUser {
                        ProfileHeader(
                            user: user,
                            minutesTotal: profile?.statsMinutesTotal ?? localMinutesTotal,
                            episodesTotal: profile?.statsEpisodesTotal ?? localEpisodesTotal,
                            favoritesCount: profile?.favorites?.count ?? favorites.items.count
                        )
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                        actionRow(user: user)
                        socialNav(user: user)
                        if user.isAdmin {
                            adminLink
                        }
                        if user.bio.isEmpty {
                            addBioCTA
                        }
                    }
                    Divider().background(theme.palette.separator).padding(.vertical, 4)
                    ProfileBody()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(theme.palette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(value: SelfProfileDest.settings) {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(theme.palette.primaryText)
                    }
                }
            }
            .navigationDestination(for: ContentItem.self) { DetailView(item: $0) }
            .navigationDestination(for: WatchProgress.self) { p in
                if let item = ProfileLookup.shared.item(for: p) {
                    DetailView(item: item, autoplayEpisodeNumber: p.episodeNumber)
                }
            }
            .navigationDestination(for: SocialDestination.self) { dest in
                switch dest {
                case .publicProfile(let nick): PublicProfileView(nickname: nick)
                case .conversation(let nick):
                    ConversationView(peer: stubUser(nick))
                }
            }
            .navigationDestination(for: SelfProfileDest.self) { dest in
                switch dest {
                case .conversations: ConversationListView()
                case .search: UserSearchView()
                case .admin: AdminPanelView()
                case .settings: SettingsView()
                }
            }
            .sheet(isPresented: $editingBio) {
                bioSheet
                    .environmentObject(theme)
            }
            .task {
                await auth.refreshMe()
                await loadProfileSnapshot()
            }
            .refreshable {
                await auth.refreshMe()
                await loadProfileSnapshot()
            }
            .onChange(of: appState.pendingProfileNickname) { newValue in
                guard let nick = newValue, !nick.isEmpty else { return }
                path.append(SocialDestination.publicProfile(nickname: nick))
                appState.pendingProfileNickname = nil
            }
            .onAppear {
                if let nick = appState.pendingProfileNickname, !nick.isEmpty {
                    path.append(SocialDestination.publicProfile(nickname: nick))
                    appState.pendingProfileNickname = nil
                }
            }
        }
    }

    // MARK: - Action rows

    private func actionRow(user: PublicUser) -> some View {
        HStack(spacing: 10) {
            ProfileActionButton(title: "Редактировать", systemImage: "pencil", style: .primary) {
                bioDraft = user.bio
                editingBio = true
            }
            ShareLink(item: shareURL(for: user)) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Поделиться")
                }
                .font(AppFont.button())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(theme.palette.surface)
                .foregroundStyle(theme.palette.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.palette.separator, lineWidth: 1)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func socialNav(user: PublicUser) -> some View {
        HStack(spacing: 10) {
            NavigationLink(value: SelfProfileDest.search) {
                pillIcon("magnifyingglass", title: "Найти")
            }
            NavigationLink(value: SelfProfileDest.conversations) {
                pillIcon("message.fill", title: "Чаты")
            }
            NavigationLink(value: SocialDestination.publicProfile(nickname: user.nickname)) {
                pillIcon("person.crop.circle", title: "Публ.")
            }
        }
        .padding(.horizontal, 4)
    }

    private var adminLink: some View {
        NavigationLink(value: SelfProfileDest.admin) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                Text("Открыть админку")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(AppFont.body())
            .padding(14)
            .background(theme.palette.surface)
            .foregroundStyle(theme.palette.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 4)
    }

    private var addBioCTA: some View {
        Button {
            bioDraft = ""
            editingBio = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "pencil.line")
                Text("Добавить био")
                Spacer()
            }
            .font(AppFont.subheadline())
            .padding(12)
            .background(theme.palette.surface)
            .foregroundStyle(theme.palette.secondaryText)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 4)
    }

    private func pillIcon(_ icon: String, title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .heavy))
            Text(title)
                .font(AppFont.caption())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(theme.palette.surface)
        .foregroundStyle(theme.palette.primaryText)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var bioSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $bioDraft)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(theme.palette.surface)
                    .foregroundStyle(theme.palette.primaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
            }
            .padding(16)
            .background(theme.palette.background.ignoresSafeArea())
            .navigationTitle("Био")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { editingBio = false }
                        .foregroundStyle(theme.palette.primaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        Task {
                            await auth.updateBio(bioDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                            editingBio = false
                        }
                    }
                    .foregroundStyle(theme.palette.primaryText)
                }
            }
        }
    }

    private func shareURL(for user: PublicUser) -> URL {
        // Always share the custom-scheme link so taps open the app via
        // onOpenURL. The backend's `share_url` points at a placeholder
        // domain that doesn't exist yet.
        URL(string: "\(SocialConfig.urlScheme)://\(SocialConfig.userPathPrefix)/\(user.nickname)")!
    }

    private func stubUser(_ nick: String) -> PublicUser {
        PublicUser(
            id: 0, nickname: nick, bio: "", role: "user",
            verified: false, isOfficial: false,
            createdAt: Date(),
            privacyHideStats: false, privacyHideFavorites: false, privacyHideHistory: false,
            shareUrl: "watch://u/\(nick)"
        )
    }

    // MARK: - Stats fallback

    /// Sum of `watchedSeconds` across all stat events, in minutes. Used
    /// before/while the backend `PublicProfile` is fetching, so the header
    /// never flashes em-dashes for the signed-in user.
    private var localMinutesTotal: Int? {
        let total = stats.events.reduce(0.0) { $0 + $1.watchedSeconds }
        return total > 0 ? Int(total) / 60 : nil
    }

    private var localEpisodesTotal: Int? {
        let n = stats.events.count
        return n > 0 ? n : nil
    }

    private func loadProfileSnapshot() async {
        guard let me = auth.currentUser else { return }
        do {
            let p = try await WatchAPI.shared.publicProfile(nickname: me.nickname)
            await MainActor.run { self.profile = p }
        } catch {
            Logger.shared.warn("self-profile snapshot failed: \(error)", category: .network)
        }
    }
}

enum SelfProfileDest: Hashable {
    case conversations, search, admin, settings
}

/// Profile tab root: gates the whole experience behind sign-in.
struct ProfileTabRoot: View {
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        if auth.isAuthenticated {
            SelfProfileView()
        } else {
            SignInView()
        }
    }
}
