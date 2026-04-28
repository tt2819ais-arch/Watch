import SwiftUI

struct SearchBar: View {
    @EnvironmentObject private var theme: ThemeManager
    @State private var text: String = ""
    @State private var showResults: Bool = false

    var body: some View {
        NavigationLink {
            SearchView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(theme.palette.secondaryText)
                Text("Поиск аниме, фильмов, сериалов")
                    .font(AppFont.body())
                    .foregroundStyle(theme.palette.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
