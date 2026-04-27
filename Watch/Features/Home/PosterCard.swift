import SwiftUI

struct PosterCard: View {
    @EnvironmentObject private var theme: ThemeManager
    let item: ContentItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: item.posterURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .frame(width: 140, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(theme.palette.separator, lineWidth: 0.5)
            }
            Text(item.title)
                .font(AppFont.subheadline())
                .foregroundStyle(theme.palette.primaryText)
                .lineLimit(2)
                .frame(width: 140, alignment: .leading)
            if let y = item.year {
                Text("\(String(y))")
                    .font(AppFont.footnote())
                    .foregroundStyle(theme.palette.secondaryText)
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            theme.palette.surface
            Image(systemName: "photo")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(theme.palette.secondaryText)
        }
    }
}

struct PosterCardSkeleton: View {
    @EnvironmentObject private var theme: ThemeManager
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.palette.surface)
                .frame(width: 140, height: 200)
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.palette.surface)
                .frame(width: 110, height: 14)
        }
    }
}
