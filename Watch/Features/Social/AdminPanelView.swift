import SwiftUI

/// Admin tools — only reachable when the signed-in user has `role == "admin"`.
/// Exposes the three privileged endpoints exposed by the backend:
///   POST   /admin/verify/{nickname}
///   DELETE /admin/verify/{nickname}
///   POST   /admin/promote/{nickname}
struct AdminPanelView: View {
    @EnvironmentObject private var theme: ThemeManager

    @State private var query: String = ""
    @State private var lookupResult: PublicProfile?
    @State private var inFlight: Bool = false
    @State private var errorText: String?
    @State private var status: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                searchField
                if let p = lookupResult {
                    targetCard(p)
                    actions(p)
                }
                if let s = status {
                    Text(s)
                        .font(AppFont.subheadline())
                        .foregroundStyle(.green)
                }
                if let err = errorText {
                    Text(err)
                        .font(AppFont.subheadline())
                        .foregroundStyle(theme.palette.danger)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(theme.palette.background.ignoresSafeArea())
        .navigationTitle("Админка")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Управление аккаунтами")
                .font(AppFont.title2())
                .foregroundStyle(theme.palette.primaryText)
            Text("Выдавай галочку, повышай до администратора, снимай галочку")
                .font(AppFont.subheadline())
                .foregroundStyle(theme.palette.secondaryText)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.palette.secondaryText)
            TextField("@nickname", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await lookup() } }
                .foregroundStyle(theme.palette.primaryText)
            Button("Найти") { Task { await lookup() } }
                .font(AppFont.button())
                .foregroundStyle(theme.palette.primaryText)
                .disabled(inFlight || query.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func targetCard(_ p: PublicProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NicknameLabel(user: p.user, titleFont: AppFont.title3())
            HStack(spacing: 8) {
                badge("Роль", p.user.role)
                badge("Галочка", p.user.verified ? "ДА" : "НЕТ")
                badge("Официальный", p.user.isOfficial ? "ДА" : "НЕТ")
            }
        }
        .padding(14)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func badge(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(AppFont.caption()).foregroundStyle(theme.palette.secondaryText)
            Text(value).font(AppFont.footnote()).foregroundStyle(theme.palette.primaryText)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(theme.palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func actions(_ p: PublicProfile) -> some View {
        VStack(spacing: 8) {
            actionButton(
                title: p.user.verified ? "Снять галочку" : "Выдать галочку",
                icon: p.user.verified ? "seal" : "checkmark.seal.fill",
                destructive: p.user.verified
            ) {
                Task { await toggleVerify(p.user) }
            }
            if !p.user.isAdmin {
                actionButton(
                    title: "Повысить до администратора",
                    icon: "arrow.up.circle.fill"
                ) {
                    Task { await promote(p.user) }
                }
            }
        }
    }

    private func actionButton(title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
            }
            .font(AppFont.button())
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(destructive ? theme.palette.danger : theme.palette.primaryText)
            .foregroundStyle(destructive ? Color.white : theme.palette.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(inFlight)
    }

    // MARK: - Calls

    private func lookup() async {
        let nick = query.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !nick.isEmpty else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            lookupResult = try await WatchAPI.shared.publicProfile(nickname: nick)
            errorText = nil
            status = nil
        } catch {
            lookupResult = nil
            errorText = error.localizedDescription
        }
    }

    private func toggleVerify(_ u: PublicUser) async {
        inFlight = true
        defer { inFlight = false }
        do {
            let updated: PublicUser
            if u.verified {
                updated = try await WatchAPI.shared.adminUnverify(nickname: u.nickname)
                status = "Галочка снята у @\(updated.nickname)"
            } else {
                updated = try await WatchAPI.shared.adminVerify(nickname: u.nickname)
                status = "Галочка выдана @\(updated.nickname)"
            }
            // Reload the card so the current state stays in sync.
            await lookup()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func promote(_ u: PublicUser) async {
        inFlight = true
        defer { inFlight = false }
        do {
            let updated = try await WatchAPI.shared.adminPromote(nickname: u.nickname)
            status = "@\(updated.nickname) теперь администратор"
            await lookup()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
