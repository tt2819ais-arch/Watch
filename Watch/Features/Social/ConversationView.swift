import SwiftUI

struct ConversationView: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var auth = AuthService.shared

    /// We accept a `PublicUser` so the navigation bar can show the
    /// verified / official badges immediately. If the caller only knows
    /// the nickname, pass a stub with id=0 — we'll re-fetch on appear.
    let peer: PublicUser

    @State private var messages: [SocialMessage] = []
    @State private var draft: String = ""
    @State private var loading: Bool = false
    @State private var sending: Bool = false
    @State private var errorText: String?
    @State private var showReactionPicker: Int?

    private let reactionEmojis = ["👍", "❤️", "🔥", "😂", "😮", "😢", "🎉"]

    var body: some View {
        VStack(spacing: 0) {
            messageList
            composer
        }
        .background(theme.palette.background.ignoresSafeArea())
        .navigationTitle("@\(peer.nickname)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text("@\(peer.nickname)")
                        .font(AppFont.headline())
                        .foregroundStyle(theme.palette.primaryText)
                    if peer.verified || peer.isOfficial {
                        VerifiedBadge(isOfficial: peer.isOfficial)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: SocialDestination.publicProfile(nickname: peer.nickname)) {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(theme.palette.primaryText)
                }
            }
        }
        .task(id: peer.nickname) {
            ConversationCatalog.shared.touch(peer.nickname)
            await reload()
        }
        .refreshable { await reload() }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if loading && messages.isEmpty {
                        ProgressView().tint(theme.palette.primaryText).padding(.top, 40)
                    }
                    ForEach(messages) { msg in
                        bubble(msg)
                            .id(msg.id)
                    }
                    if let err = errorText {
                        Text(err)
                            .font(AppFont.footnote())
                            .foregroundStyle(theme.palette.danger)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ msg: SocialMessage) -> some View {
        let mine = msg.senderNickname.lowercased() == auth.currentUser?.nickname.lowercased()
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                if msg.deleted {
                    Text("Сообщение удалено")
                        .font(AppFont.subheadline().italic())
                        .foregroundStyle(theme.palette.secondaryText)
                        .padding(10)
                        .background(theme.palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    if let title = msg.itemTitle {
                        attachedItemBadge(title: title, poster: msg.itemPosterUrl)
                    }
                    Text(msg.body)
                        .font(AppFont.body())
                        .foregroundStyle(mine ? theme.palette.background : theme.palette.primaryText)
                        .padding(10)
                        .background(mine ? theme.palette.primaryText : theme.palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                HStack(spacing: 4) {
                    Text(msg.createdAt, style: .time)
                        .font(AppFont.caption())
                        .foregroundStyle(theme.palette.secondaryText)
                    if !msg.reactions.isEmpty {
                        ForEach(reactionGroups(msg.reactions), id: \.0) { (emoji, count) in
                            Text(count > 1 ? "\(emoji) \(count)" : emoji)
                                .font(AppFont.caption())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(theme.palette.surfaceElevated)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .contextMenu {
                if !msg.deleted {
                    Menu("Реакция") {
                        ForEach(reactionEmojis, id: \.self) { emoji in
                            Button(emoji) { Task { await react(to: msg.id, emoji: emoji) } }
                        }
                    }
                    if mine {
                        Button(role: .destructive) {
                            Task { await deleteMsg(msg.id) }
                        } label: { Label("Удалить", systemImage: "trash") }
                    }
                }
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    private func attachedItemBadge(title: String, poster: String?) -> some View {
        HStack(spacing: 8) {
            if let s = poster, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: theme.palette.surfaceElevated
                    }
                }
                .frame(width: 28, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Text(title)
                .font(AppFont.footnote())
                .foregroundStyle(theme.palette.secondaryText)
                .lineLimit(1)
        }
        .padding(8)
        .background(theme.palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func reactionGroups(_ list: [SocialReaction]) -> [(String, Int)] {
        var counts: [String: Int] = [:]
        for r in list { counts[r.emoji, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Сообщение", text: $draft, axis: .vertical)
                .textInputAutocapitalization(.sentences)
                .lineLimit(1...4)
                .padding(10)
                .background(theme.palette.surface)
                .foregroundStyle(theme.palette.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button {
                Task { await send() }
            } label: {
                Image(systemName: sending ? "hourglass" : "paperplane.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .frame(width: 40, height: 40)
                    .background(canSend ? theme.palette.primaryText : theme.palette.surface)
                    .foregroundStyle(canSend ? theme.palette.background : theme.palette.secondaryText)
                    .clipShape(Circle())
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(theme.palette.background)
    }

    private var canSend: Bool {
        !sending && !draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            messages = try await WatchAPI.shared.conversation(with: peer.nickname)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            let msg = try await WatchAPI.shared.sendMessage(to: peer.nickname, body: text)
            draft = ""
            messages.append(msg)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func react(to messageID: Int, emoji: String) async {
        do {
            let updated = try await WatchAPI.shared.reactToMessage(messageID, emoji: emoji)
            replace(updated)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func deleteMsg(_ id: Int) async {
        do {
            try await WatchAPI.shared.deleteMessage(id)
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func replace(_ msg: SocialMessage) {
        if let idx = messages.firstIndex(where: { $0.id == msg.id }) {
            messages[idx] = msg
        }
    }
}
