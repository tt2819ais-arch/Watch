import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var app: AppState

    var body: some View {
        applyChromeAppearance()
        return TabView(selection: $app.selectedSection) {
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

            ProfileTabRoot()
                .tabItem {
                    Label("Профиль", systemImage: "person.crop.circle.fill")
                }
                .tag(AppState.Section.profile)
        }
        .tint(theme.palette.primaryText)
        .background(theme.palette.background.ignoresSafeArea())
        .dynamicTypeSize(dynamicTypeSize(for: theme.fontScale))
        // Re-apply UIKit chrome whenever the user picks a different theme
        // so the tab bar and nav bar follow along.
        .id("root-\(theme.current.rawValue)-\(theme.accent.rawValue)")
    }

    private func dynamicTypeSize(for scale: FontScale) -> DynamicTypeSize {
        switch scale {
        case .compact: return .small
        case .normal:  return .large
        case .large:   return .xxLarge
        }
    }

    /// Push the current palette into UIKit's tab bar / nav bar global
    /// appearances. SwiftUI's `.tint` alone doesn't repaint the bars on
    /// every device, so we configure them explicitly.
    @discardableResult
    private func applyChromeAppearance() -> Void {
        let palette = theme.palette
        let bg = UIColor(palette.background)
        let surface = UIColor(palette.surface)
        let text = UIColor(palette.primaryText)
        let secondary = UIColor(palette.secondaryText)

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = surface
        tab.shadowColor = UIColor(palette.separator)
        for state in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            state.normal.iconColor = secondary
            state.normal.titleTextAttributes = [.foregroundColor: secondary]
            state.selected.iconColor = text
            state.selected.titleTextAttributes = [.foregroundColor: text]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = bg
        nav.titleTextAttributes = [.foregroundColor: text]
        nav.largeTitleTextAttributes = [.foregroundColor: text]
        nav.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = text
    }
}
