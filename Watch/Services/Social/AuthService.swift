import Foundation
import Combine
import Security

/// Owns authentication state for the social layer. Exposes the current
/// `PublicUser`, persists the bearer token in the Keychain (falling back to
/// UserDefaults), and pushes the token into `WatchAPI`.
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var currentUser: PublicUser?
    @Published var lastError: String?

    /// True while a sign-in / sign-up / refresh request is in flight.
    @Published private(set) var inFlight: Bool = false

    private let keychainAccount = "watch.auth.token"
    private let userKey = "watch.auth.user"

    private init() {
        // Restore the cached user immediately so the UI has something to
        // render before the network refresh finishes.
        if let data = UserDefaults.standard.data(forKey: userKey) {
            let dec = JSONDecoder()
            dec.keyDecodingStrategy = .convertFromSnakeCase
            dec.dateDecodingStrategy = .iso8601
            currentUser = try? dec.decode(PublicUser.self, from: data)
        }
        if let token = readToken() {
            Task { @MainActor in
                await WatchAPI.shared.setToken(token)
                await refreshMe()
            }
        }
    }

    var isAuthenticated: Bool { currentUser != nil }

    // MARK: - Flows

    func signUp(nickname: String, password: String) async {
        await runAuth { try await WatchAPI.shared.signup(nickname: nickname, password: password) }
    }

    func signIn(nickname: String, password: String) async {
        await runAuth { try await WatchAPI.shared.login(nickname: nickname, password: password) }
    }

    func signOut() {
        currentUser = nil
        deleteToken()
        UserDefaults.standard.removeObject(forKey: userKey)
        Task { await WatchAPI.shared.setToken(nil) }
    }

    func refreshMe() async {
        guard readToken() != nil else { return }
        do {
            let me = try await WatchAPI.shared.me()
            await MainActor.run { self.persist(user: me) }
        } catch WatchAPIError.unauthorized {
            await MainActor.run { self.signOut() }
        } catch {
            Logger.shared.warn("auth refresh failed: \(error)", category: .network)
        }
    }

    func updatePrivacy(hideStats: Bool? = nil, hideFavorites: Bool? = nil, hideHistory: Bool? = nil) async {
        do {
            let me = try await WatchAPI.shared.updateMe(
                privacyHideStats: hideStats,
                privacyHideFavorites: hideFavorites,
                privacyHideHistory: hideHistory
            )
            await MainActor.run { self.persist(user: me) }
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
        }
    }

    func updateBio(_ bio: String) async {
        do {
            let me = try await WatchAPI.shared.updateMe(bio: bio)
            await MainActor.run { self.persist(user: me) }
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
        }
    }

    // MARK: - Internals

    private func runAuth(_ block: @escaping () async throws -> SocialTokenResponse) async {
        inFlight = true
        defer { inFlight = false }
        lastError = nil
        do {
            let resp = try await block()
            saveToken(resp.accessToken)
            persist(user: resp.user)
        } catch {
            lastError = error.localizedDescription
            Logger.shared.warn("auth flow failed: \(error)", category: .network)
        }
    }

    private func persist(user: PublicUser) {
        currentUser = user
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }

    // MARK: - Keychain

    private func saveToken(_ token: String) {
        let data = Data(token.utf8)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != errSecSuccess {
            // Fall back to UserDefaults if keychain isn't available
            // (e.g. running in an environment without entitlements).
            UserDefaults.standard.set(token, forKey: keychainAccount)
        }
        Task { await WatchAPI.shared.setToken(token) }
    }

    private func readToken() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return UserDefaults.standard.string(forKey: keychainAccount)
    }

    private func deleteToken() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(q as CFDictionary)
        UserDefaults.standard.removeObject(forKey: keychainAccount)
    }
}
