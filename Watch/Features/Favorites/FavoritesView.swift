import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var theme: ThemeManager
    @StateObject private var fav = FavoritesService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Избранное")
                        .font(AppFont.largeTitle())
                        .foregroundStyle(theme.palette.primaryText)
                        .padding(.top, 40)

                    if fav.items.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "heart")
                                .font(.system(size: 44, weight: .heavy))
                                .foregroundStyle(theme.palette.secondaryText)
                            Text("Здесь будет твоё избранное.\nДобавляй сериалы и аниме сердечком.")
                                .multilineTextAlignment(.center)
                                .font(AppFont.body())
                                .foregroundStyle(theme.palette.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 16) {
                            ForEach(fav.items) { item in
                                NavigationLink(value: item) {
                                    PosterCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(theme.palette.background.ignoresSafeArea())
            .navigationDestination(for: ContentItem.self) { item in
                DetailView(item: item)
            }
        }
    }
}
