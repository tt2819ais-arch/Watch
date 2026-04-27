import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var auth = AuthService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var nickname: String = ""
    @State private var password: String = ""
    @State private var passwordRepeat: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    field(title: "Никнейм", placeholder: "your_nick", text: $nickname)
                    secureField(title: "Пароль", placeholder: "не короче 6 символов", text: $password)
                    secureField(title: "Повтор пароля", placeholder: "повторите", text: $passwordRepeat)
                    rules
                    primaryButton

                    if let err = auth.lastError {
                        Text(err)
                            .font(AppFont.footnote())
                            .foregroundStyle(theme.palette.danger)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(theme.palette.background.ignoresSafeArea())
            .navigationTitle("Регистрация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(theme.palette.primaryText)
                }
            }
            .onChange(of: auth.currentUser?.id) { _, newValue in
                if newValue != nil { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Создать аккаунт")
                .font(AppFont.title())
                .foregroundStyle(theme.palette.primaryText)
            Text("Никнейм нельзя будет изменить — выбирай вдумчиво")
                .font(AppFont.subheadline())
                .foregroundStyle(theme.palette.secondaryText)
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 4) {
            ruleRow("Никнейм: 3–32 символа, латиница / цифры / `_`", ok: nickIsValid)
            ruleRow("Пароль не короче 6 символов", ok: password.count >= 6)
            ruleRow("Пароли совпадают", ok: !password.isEmpty && password == passwordRepeat)
        }
    }

    private func ruleRow(_ text: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? Color.green : theme.palette.secondaryText)
            Text(text)
                .font(AppFont.footnote())
                .foregroundStyle(theme.palette.secondaryText)
            Spacer()
        }
    }

    private var primaryButton: some View {
        Button {
            Task { await auth.signUp(nickname: trimmedNick, password: password) }
        } label: {
            HStack {
                if auth.inFlight {
                    ProgressView().tint(theme.palette.background)
                }
                Text(auth.inFlight ? "Создаём…" : "Создать аккаунт")
                    .font(AppFont.button())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.palette.primaryText)
            .foregroundStyle(theme.palette.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.5)
    }

    private var trimmedNick: String { nickname.trimmingCharacters(in: .whitespaces) }
    private var nickIsValid: Bool {
        let n = trimmedNick
        guard (3...32).contains(n.count) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        return n.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
    private var canSubmit: Bool {
        !auth.inFlight && nickIsValid && password.count >= 6 && password == passwordRepeat
    }

    private func field(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.footnote()).foregroundStyle(theme.palette.secondaryText)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(theme.palette.surface)
                .foregroundStyle(theme.palette.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func secureField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.footnote()).foregroundStyle(theme.palette.secondaryText)
            SecureField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(theme.palette.surface)
                .foregroundStyle(theme.palette.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
