import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var settings = PlayerSettings.shared
    @ObservedObject private var history = SearchHistoryService.shared
    @ObservedObject private var favorites = FavoritesService.shared
    @ObservedObject private var auth = AuthService.shared
    @State private var showResetAllAlert = false
    @State private var showSignOutAlert = false
    @State private var pendingClear: ClearAction?
    @State private var doneToast: Bool = false

    private struct ClearAction: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let perform: () -> Void
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Настройки")
                        .font(AppFont.largeTitle())
                        .foregroundStyle(theme.palette.primaryText)
                        .padding(.top, 40)

                    if auth.isAuthenticated {
                        accountSection
                        privacySection
                    }
                    themeSection
                    accentSection
                    fontSection
                    playbackSection
                    gestureSection
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
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(theme.palette.background.ignoresSafeArea())
        }
        .alert("Сбросить всё?", isPresented: $showResetAllAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Сбросить", role: .destructive) {
                resetEverything()
                presentDoneToast()
            }
        } message: {
            Text("Будут удалены избранное, прогресс, статистика, история поиска и все настройки.")
        }
        .alert("Выйти из аккаунта?", isPresented: $showSignOutAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Выйти", role: .destructive) { auth.signOut() }
        } message: {
            Text("Локальные данные (избранное, прогресс, статистика) останутся на устройстве.")
        }
        .alert(item: $pendingClear) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.body),
                primaryButton: .destructive(Text("Очистить")) {
                    action.perform()
                    presentDoneToast()
                },
                secondaryButton: .cancel(Text("Отмена"))
            )
        }
        .overlay {
            if doneToast {
                DoneCheckmarkOverlay()
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(1)
            }
        }
    }

    private func presentDoneToast() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            doneToast = true
        }
        // Auto-dismiss after a moment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.25)) {
                doneToast = false
            }
        }
    }

    // MARK: - Account / Privacy

    @ViewBuilder
    private var accountSection: some View {
        if let user = auth.currentUser {
            VStack(alignment: .leading, spacing: 8) {
                Text("Аккаунт")
                    .font(AppFont.title3())
                    .foregroundStyle(theme.palette.primaryText)
                HStack(spacing: 10) {
                    Circle()
                        .fill(theme.palette.surfaceElevated)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Text(String(user.nickname.prefix(1)).uppercased())
                                .font(AppFont.headline())
                                .foregroundStyle(theme.palette.primaryText)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(user.handle)
                                .font(AppFont.headline())
                                .foregroundStyle(theme.palette.primaryText)
                            if user.verified || user.isOfficial {
                                VerifiedBadge(isOfficial: user.isOfficial)
                            }
                        }
                        if user.isOfficial {
                            Text("Официальный аккаунт Watch")
                                .font(AppFont.caption())
                                .foregroundStyle(theme.palette.secondaryText)
                        } else if user.isAdmin {
                            Text("Администратор")
                                .font(AppFont.caption())
                                .foregroundStyle(theme.palette.secondaryText)
                        }
                    }
                    Spacer()
                }
                .padding(14)
                .background(theme.palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button(role: .destructive) {
                    showSignOutAlert = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Выйти")
                            .font(AppFont.body())
                        Spacer()
                    }
                    .padding(14)
                    .background(theme.palette.surface)
                    .foregroundStyle(theme.palette.danger)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var privacySection: some View {
        if let user = auth.currentUser {
            VStack(alignment: .leading, spacing: 12) {
                Text("Приватность")
                    .font(AppFont.title3())
                    .foregroundStyle(theme.palette.primaryText)
                Text("Скрывает соответствующие блоки на твоём публичном профиле для других пользователей.")
                    .font(AppFont.footnote())
                    .foregroundStyle(theme.palette.secondaryText)
                privacyToggle(
                    title: "Скрывать статистику",
                    isOn: user.privacyHideStats
                ) { newValue in
                    Task { await auth.updatePrivacy(hideStats: newValue) }
                }
                privacyToggle(
                    title: "Скрывать избранное",
                    isOn: user.privacyHideFavorites
                ) { newValue in
                    Task { await auth.updatePrivacy(hideFavorites: newValue) }
                }
                privacyToggle(
                    title: "Скрывать историю просмотра",
                    isOn: user.privacyHideHistory
                ) { newValue in
                    Task { await auth.updatePrivacy(hideHistory: newValue) }
                }
            }
        }
    }

    private func privacyToggle(title: String, isOn current: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title)
                .font(AppFont.body())
                .foregroundStyle(theme.palette.primaryText)
            Spacer()
            Toggle("", isOn: Binding(
                get: { current },
                set: { onChange($0) }
            ))
            .labelsHidden()
        }
    }

    // MARK: - Sections

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

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Акцентный цвет")
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AccentColor.allCases) { c in
                        Button { theme.accent = c } label: {
                            Circle()
                                .fill(c.color)
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Circle().stroke(theme.palette.primaryText.opacity(c == theme.accent ? 1 : 0.0), lineWidth: 3)
                                )
                                .overlay(
                                    Circle().stroke(theme.palette.separator, lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
    }

    private var fontSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Размер шрифта")
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            Picker("", selection: $theme.fontScale) {
                ForEach(FontScale.allCases) { f in
                    Text(f.displayName).tag(f)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Воспроизведение")
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)

            HStack {
                Text("Шаг перемотки")
                    .font(AppFont.body())
                    .foregroundStyle(theme.palette.primaryText)
                Spacer()
                Picker("", selection: $settings.skipSeconds) {
                    ForEach([5, 10, 15, 30], id: \.self) { v in
                        Text("\(v)с").tag(v)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            HStack {
                Text("Скорость по умолчанию")
                    .font(AppFont.body())
                    .foregroundStyle(theme.palette.primaryText)
                Spacer()
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { v in
                        Button {
                            settings.defaultSpeed = v
                        } label: {
                            Text("\(speedLabel(v))×")
                        }
                    }
                } label: {
                    Text("\(speedLabel(settings.defaultSpeed))×")
                        .font(AppFont.body())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(theme.palette.surface)
                        .foregroundStyle(theme.palette.primaryText)
                        .clipShape(Capsule())
                }
            }

            HStack {
                Text("Ширина экрана по умолчанию")
                    .font(AppFont.body())
                    .foregroundStyle(theme.palette.primaryText)
                Spacer()
                Menu {
                    ForEach(ZoomMode.allCases) { z in
                        Button { settings.defaultZoomMode = z } label: { Text(z.displayName) }
                    }
                } label: {
                    Text(settings.defaultZoomMode.displayName)
                        .font(AppFont.body())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(theme.palette.surface)
                        .foregroundStyle(theme.palette.primaryText)
                        .clipShape(Capsule())
                }
            }

            toggle("Авто-пропуск опенинга", on: $settings.autoSkipIntro)
            toggle("Авто-пропуск эндинга", on: $settings.autoSkipOutro)
            toggle("Авто-переход на следующую серию", on: $settings.autoNextEpisode)
            toggle("Запоминать качество", on: $settings.rememberQuality)
        }
    }

    private var gestureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Жесты в плеере")
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            toggle("Свайп: яркость", on: $settings.enableSwipeGestures)
            toggle("Двойной тап: перемотка", on: $settings.enableDoubleTapSkip)
            toggle("Удержание: ускорение", on: $settings.enableLongPressBoost)
            HStack {
                Text("Скорость удержания")
                    .font(AppFont.body())
                    .foregroundStyle(theme.palette.primaryText)
                Spacer()
                Picker("", selection: $settings.longPressBoostSpeed) {
                    Text("1.5×").tag(1.5)
                    Text("2×").tag(2.0)
                    Text("2.5×").tag(2.5)
                    Text("3×").tag(3.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Данные")
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            VStack(spacing: 8) {
                resetRow("Очистить избранное", icon: "heart.slash") {
                    pendingClear = ClearAction(
                        title: "Очистить избранное?",
                        body: "Все добавленные в избранное тайтлы будут удалены.",
                        perform: { favorites.clearAll() }
                    )
                }
                resetRow("Очистить прогресс", icon: "play.slash.fill") {
                    pendingClear = ClearAction(
                        title: "Очистить прогресс?",
                        body: "Позиции просмотра по всем сериям будут удалены.",
                        perform: { ProgressService.shared.clearAll() }
                    )
                }
                resetRow("Очистить статистику", icon: "chart.bar.xaxis") {
                    pendingClear = ClearAction(
                        title: "Очистить статистику?",
                        body: "Накопленная статистика просмотра будет удалена.",
                        perform: { StatsService.shared.clearAll() }
                    )
                }
                resetRow("Очистить историю поиска", icon: "magnifyingglass.circle") {
                    pendingClear = ClearAction(
                        title: "Очистить историю поиска?",
                        body: "Последние поисковые запросы будут удалены.",
                        perform: { history.clear() }
                    )
                }
                resetRow("Сбросить всё", icon: "trash.fill", destructive: true) {
                    showResetAllAlert = true
                }
            }
        }
    }

    private func resetRow(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .font(AppFont.body())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.caption())
            }
            .padding(14)
            .background(theme.palette.surface)
            .foregroundStyle(destructive ? theme.palette.danger : theme.palette.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func toggle(_ title: String, on: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(AppFont.body())
                .foregroundStyle(theme.palette.primaryText)
            Spacer()
            Toggle("", isOn: on)
                .labelsHidden()
        }
    }

    private func speedLabel(_ value: Double) -> String {
        if value == floor(value) { return "\(Int(value))" }
        return String(format: "%g", value)
    }

    private func resetEverything() {
        favorites.clearAll()
        ProgressService.shared.clearAll()
        StatsService.shared.clearAll()
        history.clear()
        // Reset player settings: just remove keys, the singleton will keep
        // current values until next launch — that's acceptable.
        let d = UserDefaults.standard
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("player.") {
            d.removeObject(forKey: key)
        }
        Logger.shared.warn("Full reset performed", category: .ui)
    }
}
