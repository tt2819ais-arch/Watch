import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @State private var kodikToken: String = UserDefaults.standard.string(forKey: "kodik.token") ?? ""
    @State private var poiskKinoToken: String = UserDefaults.standard.string(forKey: "poiskkino.token") ?? ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Настройки")
                        .font(AppFont.largeTitle())
                        .foregroundStyle(theme.palette.primaryText)
                        .padding(.top, 40)

                    themeSection
                    sourcesSection
                    storageSection
                    NavigationLink {
                        LogsView()
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.fill")
                            Text("Логи приложения")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(AppFont.body())
                        .padding(14)
                        .background(theme.palette.surface)
                        .foregroundStyle(theme.palette.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(theme.palette.background.ignoresSafeArea())
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Тема")
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            HStack(spacing: 8) {
                ForEach(AppTheme.allCases) { t in
                    Button {
                        theme.current = t
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(ThemePalette.palette(for: t).background)
                                .overlay {
                                    Circle()
                                        .stroke(theme.palette.separator, lineWidth: t == theme.current ? 3 : 1)
                                }
                                .frame(width: 56, height: 56)
                            Text(t.displayName)
                                .font(AppFont.footnote())
                                .foregroundStyle(theme.palette.primaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Источники")
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            Text("AniLibria и PoiskKino встроены. Kodik использует публичный токен с авто-восстановлением. Здесь можно подменить любой ключ своим.")
                .font(AppFont.subheadline())
                .foregroundStyle(theme.palette.secondaryText)

            tokenField(
                label: "Kodik API ключ (необязательно)",
                placeholder: "Свой kodik token (32-symbol hex)",
                text: $kodikToken,
                key: "kodik.token",
                logName: "Kodik"
            )
            tokenField(
                label: "PoiskKino API ключ",
                placeholder: "X-API-KEY от api.poiskkino.dev",
                text: $poiskKinoToken,
                key: "poiskkino.token",
                logName: "PoiskKino"
            )
        }
    }

    private func tokenField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        key: String,
        logName: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.subheadline())
                .foregroundStyle(theme.palette.primaryText)
            TextField(placeholder, text: text)
                .font(AppFont.body())
                .padding(12)
                .background(theme.palette.surface)
                .foregroundStyle(theme.palette.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
            Button {
                UserDefaults.standard.set(text.wrappedValue, forKey: key)
                Logger.shared.info("\(logName) token saved (length \(text.wrappedValue.count))", category: .source)
            } label: {
                Text("Сохранить")
                    .font(AppFont.button())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(theme.palette.primaryText)
                    .foregroundStyle(theme.palette.background)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Данные")
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            HStack(spacing: 8) {
                Button {
                    Task { @MainActor in
                        ProgressService.shared.clearAll()
                    }
                } label: {
                    Text("Очистить прогресс")
                        .font(AppFont.subheadline())
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(theme.palette.surface)
                        .foregroundStyle(theme.palette.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Button {
                    Task { @MainActor in
                        StatsService.shared.clearAll()
                    }
                } label: {
                    Text("Очистить статистику")
                        .font(AppFont.subheadline())
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(theme.palette.surface)
                        .foregroundStyle(theme.palette.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Spacer()
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("О приложении")
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            Text("Watch v1.0\nМинималистичный плеер для аниме, фильмов и сериалов.\nИсходники: github.com/tt2819ais-arch/Watch")
                .font(AppFont.subheadline())
                .foregroundStyle(theme.palette.secondaryText)
        }
    }
}
