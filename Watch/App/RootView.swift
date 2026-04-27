import SwiftUI

struct RootView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView(selection: $app.selectedSection) {
            HomeView()
                .tabItem {
                    Label("Главная", systemImage: "house.fill")
                }
                .tag(AppState.Section.home)

            CatalogView(kind: .anime)
                .tabItem {
                    Label("Аниме", systemImage: "sparkles.tv.fill")
                }
                .tag(AppState.Section.anime)

            CatalogView(kind: .movie)
                .tabItem {
                    Label("Фильмы", systemImage: "film.fill")
                }
                .tag(AppState.Section.movies)

            CatalogView(kind: .series)
                .tabItem {
                    Label("Сериалы", systemImage: "tv.fill")
                }
                .tag(AppState.Section.series)

            ProfileView()
                .tabItem {
                    Label("Профиль", systemImage: "person.crop.circle.fill")
                }
                .tag(AppState.Section.profile)

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape.fill")
                }
                .tag(AppState.Section.settings)
        }
        .tint(theme.palette.primaryText)
        .background(theme.palette.background.ignoresSafeArea())
        .dynamicTypeSize(dynamicTypeSize(for: theme.fontScale))
    }

    private func dynamicTypeSize(for scale: FontScale) -> DynamicTypeSize {
        switch scale {
        case .compact: return .small
        case .normal:  return .large
        case .large:   return .xxLarge
        }
    }
}
