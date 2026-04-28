import SwiftUI

/// Bell icon + red unread badge that lives in the trailing edge of every
/// tab's nav bar. Tapping it opens the inbox drawer.
///
/// `AuthService` is intentionally read via the shared singleton instead of
/// `@EnvironmentObject` to match the rest of the codebase (and to avoid
/// crashing when the bell is rendered outside of a view hierarchy that
/// happens to inject the service).
struct NotificationBell: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var notifications: NotificationsService
    @ObservedObject private var auth = AuthService.shared
    @State private var showInbox = false

    var body: some View {
        if auth.isAuthenticated {
            Button {
                showInbox = true
                Task { await notifications.refresh() }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.palette.primaryText)
                        .frame(width: 32, height: 32)
                    if notifications.hasUnread {
                        let count = notifications.totalUnread
                        Text(count > 9 ? "9+" : "\(count)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(theme.palette.background, lineWidth: 1.5)
                            )
                            .offset(x: 4, y: -2)
                            .accessibilityLabel("\(count) непрочитанных")
                    }
                }
            }
            .accessibilityLabel("Уведомления")
            .sheet(isPresented: $showInbox) {
                NotificationInboxView()
                    .environmentObject(theme)
                    .environmentObject(notifications)
            }
        }
    }
}

/// Drawer shown when the bell is tapped. Lists every conversation,
/// newest first; unread rows have a colored dot. Tapping a row pushes
/// the existing `ConversationView` and clears that row's unread count
/// optimistically.
struct NotificationInboxView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var notifications: NotificationsService
    @ObservedObject private var auth = AuthService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if notifications.inbox.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(theme.palette.background.ignoresSafeArea())
            .navigationTitle("Уведомления")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(theme.palette.primaryText)
                }
            }
            .refreshable { await notifications.refresh() }
        }
    }

    /// Build a placeholder `PublicUser` from an inbox entry. The
    /// ConversationView re-fetches the real profile on appear; we just
    /// need enough fields to render the title bar correctly until then.
    private func stubPeer(for entry: InboxEntry) -> PublicUser {
        PublicUser(
            id: 0,
            nickname: entry.otherNickname,
            bio: "",
            role: "user",
            verified: entry.otherVerified,
            isOfficial: entry.otherIsOfficial,
            createdAt: Date(),
            privacyHideStats: false,
            privacyHideFavorites: false,
            privacyHideHistory: false,
            shareUrl: ""
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(theme.palette.secondaryText)
            Text("Уведомлений пока нет")
                .font(AppFont.subheadline())
                .foregroundStyle(theme.palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(notifications.inbox) { entry in
                    NavigationLink {
                        ConversationView(peer: stubPeer(for: entry))
                            .onAppear {
                                notifications.markRead(nickname: entry.otherNickname)
                            }
                    } label: {
                        InboxRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }
}

private struct InboxRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let entry: InboxEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar placeholder — first letter of nickname inside a
            // colored circle so the inbox doesn't look like a flat list.
            Text(String(entry.otherNickname.first ?? "?").uppercased())
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(avatarColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("@\(entry.otherNickname)")
                        .font(AppFont.subheadline().weight(.semibold))
                        .foregroundStyle(theme.palette.primaryText)
                        .lineLimit(1)
                    if entry.otherIsOfficial || entry.otherVerified {
                        VerifiedBadge(isOfficial: entry.otherIsOfficial)
                    }
                    Spacer()
                    Text(timeFormatter.localizedString(for: entry.lastMessage.createdAt, relativeTo: Date()))
                        .font(AppFont.caption())
                        .foregroundStyle(theme.palette.secondaryText)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(preview)
                    .font(AppFont.caption())
                    .foregroundStyle(entry.unreadCount > 0
                        ? theme.palette.primaryText
                        : theme.palette.secondaryText)
                    .lineLimit(2)
            }

            if entry.unreadCount > 0 {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                    .padding(.top, 6)
            }
        }
        .padding(12)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var preview: String {
        let m = entry.lastMessage
        if m.deleted { return "Сообщение удалено" }
        if !m.body.isEmpty { return m.body }
        if let title = m.itemTitle { return "📺 \(title)" }
        return "…"
    }

    private var avatarColor: Color {
        // Stable per-nickname color so the same person keeps the same
        // circle across launches.
        let hash = entry.otherNickname.lowercased()
            .unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) }
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green]
        return palette[abs(hash) % palette.count]
    }
}

private let timeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "ru_RU")
    f.unitsStyle = .short
    return f
}()
