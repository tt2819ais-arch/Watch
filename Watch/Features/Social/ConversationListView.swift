import SwiftUI

/// Local cache of recently-talked-to peers. The backend doesn't expose a
/// "list my conversations" endpoint, so we keep a simple list on-device of
/// nicknames the user has interacted with via `ConversationView`.
@MainActor
final class ConversationCatalog: ObservableObject {
    static let shared = ConversationCatalog()
    private let key = "social.conversations.peers"

    @Published private(set) var peers: [String] = []

    private init() {
        peers = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func touch(_ nickname: String) {
        var arr = peers.filter { $0.lowercased() != nickname.lowercased() }
        arr.insert(nickname, at: 0)
        if arr.count > 50 { arr = Array(arr.prefix(50)) }
        peers = arr
        UserDefaults.standard.set(arr, forKey: key)
    }

    func remove(_ nickname: String) {
        peers.removeAll { $0.lowercased() == nickname.lowercased() }
        UserDefaults.standard.set(peers, forKey: key)
    }
}

struct ConversationListView: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var catalog = ConversationCatalog.shared

    @State private var openSearch: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if catalog.peers.isEmpty {
                    emptyState
                } else {
                    ForEach(catalog.peers, id: \.self) { nick in
                        NavigationLink(value: SocialDestination.conversation(nickname: nick)) {
                            row(nickname: nick)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(theme.palette.background.ignoresSafeArea())
        .navigationTitle("Сообщения")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    openSearch = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(theme.palette.primaryText)
                }
            }
        }
        .sheet(isPresented: $openSearch) {
            NavigationStack {
                UserSearchView()
                    .navigationDestination(for: SocialDestination.self) { dest in
                        switch dest {
                        case .publicProfile(let nick): PublicProfileView(nickname: nick)
                        case .conversation(let nick): ConversationView(peer: stubUser(nick))
                        }
                    }
            }
            .environmentObject(theme)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(theme.palette.secondaryText)
            Text("Здесь будут твои переписки")
                .font(AppFont.subheadline())
                .foregroundStyle(theme.palette.secondaryText)
            Button {
                openSearch = true
            } label: {
                Text("Найти пользователя")
                    .font(AppFont.button())
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(theme.palette.primaryText)
                    .foregroundStyle(theme.palette.background)
                    .clipShape(Capsule())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func row(nickname: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(theme.palette.surfaceElevated)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(nickname.prefix(1)).uppercased())
                        .font(AppFont.headline())
                        .foregroundStyle(theme.palette.primaryText)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(nickname)")
                    .font(AppFont.subheadline())
                    .foregroundStyle(theme.palette.primaryText)
                Text("Нажми, чтобы открыть переписку")
                    .font(AppFont.caption())
                    .foregroundStyle(theme.palette.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(theme.palette.secondaryText)
        }
        .padding(10)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
