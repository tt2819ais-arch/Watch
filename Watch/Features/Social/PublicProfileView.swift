import SwiftUI

struct PublicProfileView: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var auth = AuthService.shared

    let nickname: String

    @State private var profile: PublicProfile?
    @State private var loading: Bool = false
    @State private var errorText: String?
    @State private var openConversation: Bool = false
    @State private var blockBusy: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let p = profile {
                    headerCard(p: p)
                    if !p.isBlockingViewer {
                        actionRow(p: p)
                        statsCard(p: p)
                        if let favs = p.favorites, !favs.isEmpty {
                            section(title: "Избранное") {
                                horizontalPosters(items: favs.map { ($0.itemId, $0.title, $0.posterUrl) })
                            }
                        }
                        if let hist = p.recentHistory, !hist.isEmpty {
                            section(title: "Недавно смотрел") {
                                historyList(points: hist)
                            }
                        }
                    } else {
                        blockedNotice
                    }
                } else if loading {
                    ProgressView().tint(theme.palette.primaryText).padding(.top, 80)
                } else if let err = errorText {
                    Text(err)
                        .font(AppFont.subheadline())
                        .foregroundStyle(theme.palette.danger)
                        .padding()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(theme.palette.background.ignoresSafeArea())
        .navigationTitle("@\(nickname)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $openConversation) {
            if let p = profile {
                ConversationView(peer: p.user)
            }
        }
        .task(id: nickname) {
            await load()
        }
        .refreshable { await load() }
    }

    // MARK: - Header

    private func headerCard(p: PublicProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NicknameLabel(user: p.user, titleFont: AppFont.title())
            if !p.user.bio.isEmpty {
                Text(p.user.bio)
                    .font(AppFont.subheadline())
                    .foregroundStyle(theme.palette.primaryText)
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text("На Watch с \(p.user.createdAt, format: .dateTime.year().month().day())")
            }
            .font(AppFont.footnote())
            .foregroundStyle(theme.palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actionRow(p: PublicProfile) -> some View {
        HStack(spacing: 10) {
            if !isMe(p.user) {
                Button {
                    openConversation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "message.fill")
                        Text("Написать")
                    }
                    .font(AppFont.button())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(theme.palette.primaryText)
                    .foregroundStyle(theme.palette.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            ShareLink(item: shareURL(for: p.user)) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Поделиться")
                }
                .font(AppFont.button())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(theme.palette.surface)
                .foregroundStyle(theme.palette.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !isMe(p.user) {
                Menu {
                    if p.isBlockedByViewer {
                        Button("Разблокировать", systemImage: "lock.open.fill") {
                            Task { await unblock(nick: p.user.nickname) }
                        }
                    } else {
                        Button(role: .destructive) {
                            Task { await block(nick: p.user.nickname) }
                        } label: {
                            Label("Заблокировать", systemImage: "hand.raised.fill")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(AppFont.button())
                        .frame(width: 44, height: 44)
                        .background(theme.palette.surface)
                        .foregroundStyle(theme.palette.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(blockBusy)
            }
        }
    }

    private func statsCard(p: PublicProfile) -> some View {
        HStack(spacing: 10) {
            stat(icon: "clock.fill", title: "Минут",
                 value: p.statsMinutesTotal.map(String.init) ?? "—")
            stat(icon: "play.tv.fill", title: "Серий",
                 value: p.statsEpisodesTotal.map(String.init) ?? "—")
        }
    }

    private func stat(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(theme.palette.primaryText)
            Text(value)
                .font(AppFont.title2())
                .foregroundStyle(theme.palette.primaryText)
            Text(title)
                .font(AppFont.footnote())
                .foregroundStyle(theme.palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var blockedNotice: some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(theme.palette.secondaryText)
            Text("Этот пользователь вас заблокировал")
                .font(AppFont.subheadline())
                .foregroundStyle(theme.palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Sections

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            content()
        }
    }

    private func horizontalPosters(items: [(String, String, String?)]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items.indices, id: \.self) { idx in
                    let (_, title, poster) = items[idx]
                    VStack(alignment: .leading, spacing: 4) {
                        if let s = poster, let url = URL(string: s) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: theme.palette.surface
                                }
                            }
                            .frame(width: 110, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 10).fill(theme.palette.surface)
                                .frame(width: 110, height: 160)
                        }
                        Text(title)
                            .font(AppFont.footnote())
                            .foregroundStyle(theme.palette.primaryText)
                            .lineLimit(2)
                            .frame(width: 110, alignment: .leading)
                    }
                }
            }
        }
    }

    private func historyList(points: [SocialStatPoint]) -> some View {
        VStack(spacing: 6) {
            ForEach(points.prefix(20)) { p in
                HStack(spacing: 10) {
                    if let s = p.posterUrl, let url = URL(string: s) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: theme.palette.surface
                            }
                        }
                        .frame(width: 36, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title)
                            .font(AppFont.subheadline())
                            .foregroundStyle(theme.palette.primaryText)
                            .lineLimit(1)
                        if let ep = p.episodeNumber {
                            Text("Серия \(ep) • \((p.secondsWatched ?? 0) / 60) мин")
                                .font(AppFont.footnote())
                                .foregroundStyle(theme.palette.secondaryText)
                        }
                    }
                    Spacer()
                    Text(p.createdAt, style: .relative)
                        .font(AppFont.footnote())
                        .foregroundStyle(theme.palette.secondaryText)
                }
                .padding(10)
                .background(theme.palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: - Loading

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            profile = try await WatchAPI.shared.publicProfile(nickname: nickname)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func block(nick: String) async {
        blockBusy = true
        defer { blockBusy = false }
        do { try await WatchAPI.shared.block(nickname: nick); await load() }
        catch { errorText = error.localizedDescription }
    }

    private func unblock(nick: String) async {
        blockBusy = true
        defer { blockBusy = false }
        do { try await WatchAPI.shared.unblock(nickname: nick); await load() }
        catch { errorText = error.localizedDescription }
    }

    private func isMe(_ user: PublicUser) -> Bool {
        auth.currentUser?.id == user.id
    }

    private func shareURL(for user: PublicUser) -> URL {
        URL(string: user.shareUrl) ?? URL(string: "\(SocialConfig.urlScheme)://\(SocialConfig.userPathPrefix)/\(user.nickname)")!
    }
}
