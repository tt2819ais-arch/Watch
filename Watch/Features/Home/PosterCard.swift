import SwiftUI

struct PosterCard: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var progress = ProgressService.shared
    let item: ContentItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
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

                if watchedCount > 0 {
                    badge
                        .padding(8)
                }
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

    private var watchedCount: Int { progress.watchedCount(for: item.id) }

    private var badge: some View {
        Text("\(watchedCount)")
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.65))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 0.5))
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
