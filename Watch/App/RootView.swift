import SwiftUI

struct RootView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            theme.palette.background.ignoresSafeArea()

            // Main content
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: app.sidebarVisible ? sidebarWidth : 0)
                .disabled(app.sidebarVisible)
                .overlay(alignment: .topLeading) {
                    if !app.sidebarVisible {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                app.sidebarVisible = true
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 18, weight: .heavy))
                                .padding(12)
                                .foregroundStyle(theme.palette.primaryText)
                        }
                        .padding(.top, 4)
                        .padding(.leading, 4)
                    }
                }

            // Dimmer when sidebar is open
            if app.sidebarVisible {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            app.sidebarVisible = false
                        }
                    }
                    .transition(.opacity)
            }

            // Sidebar
            SidebarView()
                .frame(width: sidebarWidth)
                .background(theme.palette.surface.ignoresSafeArea())
                .offset(x: app.sidebarVisible ? 0 : -sidebarWidth)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: app.sidebarVisible)
    }

    private var sidebarWidth: CGFloat { 280 }

    @ViewBuilder
    private var mainContent: some View {
        switch app.selectedSection {
        case .home:      HomeView()
        case .anime:     CatalogView(kind: .anime)
        case .movies:    CatalogView(kind: .movie)
        case .series:    CatalogView(kind: .series)
        case .favorites: FavoritesView()
        case .stats:     StatsView()
        case .settings:  SettingsView()
        }
    }
}
