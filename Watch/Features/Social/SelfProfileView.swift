import SwiftUI

/// Profile tab content for the signed-in user. Wraps the existing
/// `ProfileBody` (local stats / favourites / continue-watching) with a
/// social header that includes the verified badge, share button, link to
/// public profile, conversations, search, admin panel and sign-out.
struct SelfProfileView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var auth = AuthService.shared
    @State private var path = NavigationPath()
    @State private var bioDraft: String = ""
    @State private var editingBio: Bool = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let user = auth.currentUser {
                        headerCard(user: user)
                        actionRow(user: user)
                        if user.isAdmin {
                            adminLink
                        }
                    }
                    ProfileBody()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(theme.palette.background.ignoresSafeArea())
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
                }
            }
            .sheet(isPresented: $editingBio) {
                bioSheet
                    .environmentObject(theme)
            }
            .task { await auth.refreshMe() }
            .refreshable { await auth.refreshMe() }
            .onChange(of: appState.pendingProfileNickname) { _, newValue in
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

    private func headerCard(user: PublicUser) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NicknameLabel(user: user, titleFont: AppFont.title())
            if user.bio.isEmpty {
                Button {
                    bioDraft = user.bio
                    editingBio = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.line")
                        Text("Добавить био")
                    }
                    .font(AppFont.subheadline())
                    .foregroundStyle(theme.palette.secondaryText)
                }
            } else {
                Text(user.bio)
                    .font(AppFont.subheadline())
                    .foregroundStyle(theme.palette.primaryText)
                Button("Изменить био") {
                    bioDraft = user.bio
                    editingBio = true
                }
                .font(AppFont.footnote())
                .foregroundStyle(theme.palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actionRow(user: PublicUser) -> some View {
        HStack(spacing: 8) {
            NavigationLink(value: SelfProfileDest.search) {
                pillIcon("magnifyingglass", title: "Найти")
            }
            NavigationLink(value: SelfProfileDest.conversations) {
                pillIcon("message.fill", title: "Чаты")
            }
            NavigationLink(value: SocialDestination.publicProfile(nickname: user.nickname)) {
                pillIcon("person.crop.circle", title: "Публ.")
            }
            ShareLink(item: shareURL(for: user)) {
                pillIcon("square.and.arrow.up", title: "Шаринг")
            }
        }
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
        URL(string: user.shareUrl) ?? URL(string: "\(SocialConfig.urlScheme)://\(SocialConfig.userPathPrefix)/\(user.nickname)")!
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
}

enum SelfProfileDest: Hashable {
    case conversations, search, admin
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
