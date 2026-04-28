import Foundation
import Combine
import SwiftUI

/// Polls the backend's `/messages/inbox` endpoint at a steady cadence so
/// the in-app bell can show a live unread count + a list of recent
/// conversations. Lives on the main actor because every published value
/// is consumed directly by SwiftUI views (toolbar bell, drawer rows).
///
/// Polling cadence:
/// - 25 seconds while authenticated and the app is in the foreground.
/// - Pauses entirely on sign-out / when the app is backgrounded.
/// - Honors transport cancellations (URLError -999) silently.
@MainActor
final class NotificationsService: ObservableObject {
    static let shared = NotificationsService()

    @Published private(set) var inbox: [InboxEntry] = []
    @Published private(set) var lastError: String?

    /// Sum of unread messages across all conversations.
    var totalUnread: Int { inbox.reduce(0) { $0 + $1.unreadCount } }

    /// Whether the bell badge should be red right now.
    var hasUnread: Bool { totalUnread > 0 }

    private var pollTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var isPolling = false

    private init() {
        // React to auth changes — start when the user signs in, stop on
        // sign-out. Using `objectWillChange` avoids a tight binding to
        // AuthService internals.
        AuthService.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncWithAuthState()
                }
            }
            .store(in: &cancellables)

        // React to foreground/background transitions so we don't poll
        // when the app isn't visible.
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncWithAuthState()
                    await self?.refresh()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stop()
                }
            }
            .store(in: &cancellables)

        syncWithAuthState()
    }

    private func syncWithAuthState() {
        if AuthService.shared.isAuthenticated {
            start()
        } else {
            stop()
            inbox = []
        }
    }

    func start() {
        guard !isPolling, AuthService.shared.isAuthenticated else { return }
        isPolling = true
        pollTask = Task { @MainActor [weak self] in
            // First refresh runs immediately so the bell hydrates as soon
            // as the user signs in / the app comes to the foreground.
            await self?.refresh()
            while let self, self.isPolling, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                if Task.isCancelled { break }
                await self.refresh()
            }
        }
    }

    func stop() {
        isPolling = false
        pollTask?.cancel()
        pollTask = nil
    }

    /// Mark a conversation locally as read. The backend zeroes `read_at`
    /// the next time `/messages/<nick>` is fetched, but we update the UI
    /// optimistically so the bell badge clears the moment the user opens
    /// the dialog.
    func markRead(nickname: String) {
        let target = nickname.lowercased()
        inbox = inbox.map { e in
            guard e.id == target else { return e }
            return InboxEntry(
                otherNickname: e.otherNickname,
                otherIsOfficial: e.otherIsOfficial,
                otherVerified: e.otherVerified,
                lastMessage: e.lastMessage,
                unreadCount: 0
            )
        }
    }

    func refresh() async {
        do {
            let next = try await WatchAPI.shared.inbox()
            await MainActor.run {
                self.inbox = next
                self.lastError = nil
            }
        } catch WatchAPIError.unauthorized {
            // Sign-out is owned by AuthService — just stop here.
            await MainActor.run { self.stop() }
        } catch WatchAPIError.transport(let inner) {
            // Suppress SwiftUI .task cancellations.
            if (inner as NSError).code != NSURLErrorCancelled {
                Logger.shared.warn("inbox refresh failed: \(inner)", category: .network)
            }
        } catch {
            Logger.shared.warn("inbox refresh failed: \(error)", category: .network)
            await MainActor.run { self.lastError = error.localizedDescription }
        }
    }
}
