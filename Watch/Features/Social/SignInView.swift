import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var auth = AuthService.shared

    @State private var nickname: String = ""
    @State private var password: String = ""
    @State private var showSignUp: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    field(title: "Никнейм", placeholder: "your_nick", text: $nickname)
                    secureField(title: "Пароль", placeholder: "••••••••", text: $password)
                    primaryButton

                    if let err = auth.lastError {
                        Text(err)
                            .font(AppFont.footnote())
                            .foregroundStyle(theme.palette.danger)
                    }

                    Divider().background(theme.palette.separator).padding(.vertical, 4)

                    HStack {
                        Text("Нет аккаунта?")
                            .font(AppFont.subheadline())
                            .foregroundStyle(theme.palette.secondaryText)
                        Button("Зарегистрироваться") { showSignUp = true }
                            .font(AppFont.subheadline())
                            .foregroundStyle(theme.palette.primaryText)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 32)
            }
            .background(theme.palette.background.ignoresSafeArea())
            .sheet(isPresented: $showSignUp) {
                SignUpView()
                    .environmentObject(theme)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(theme.palette.primaryText)
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Войти в Watch")
                .font(AppFont.largeTitle())
                .foregroundStyle(theme.palette.primaryText)
            Text("Сохраняй прогресс, общайся, делись профилем")
                .font(AppFont.subheadline())
                .foregroundStyle(theme.palette.secondaryText)
        }
        .padding(.bottom, 8)
    }

    private var primaryButton: some View {
        Button {
            Task { await auth.signIn(nickname: trimmedNick, password: password) }
        } label: {
            HStack {
                if auth.inFlight {
                    ProgressView().tint(theme.palette.background)
                }
                Text(auth.inFlight ? "Входим…" : "Войти")
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
    private var canSubmit: Bool {
        !auth.inFlight && !trimmedNick.isEmpty && !password.isEmpty
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
