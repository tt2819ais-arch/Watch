import SwiftUI

struct ContinueWatchingRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let progressItems: [WatchProgress]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(progressItems) { p in
                    NavigationLink(value: p) {
                        ContinueWatchingCard(progress: p)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Netflix-style "Continue Watching" tile: a 16:9 poster with a dark
/// bottom gradient holding the title, episode label, and a slim accent
/// progress bar pinned to the bottom edge. Falls back to a placeholder
/// when the linked ContentItem isn't in the in-memory lookup yet.
private struct ContinueWatchingCard: View {
    @EnvironmentObject private var theme: ThemeManager
    let progress: WatchProgress

    private var item: ContentItem? {
        ProfileLookup.shared.item(for: progress)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            poster

            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 84)
            .frame(maxWidth: .infinity, alignment: .bottom)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    if let title = item?.title, !title.isEmpty {
                        Text(title)
                            .font(AppFont.headline())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .heavy))
                        Text(episodeLabel(for: progress))
                            .font(AppFont.subheadline())
                        Spacer(minLength: 4)
                        Text("\(progress.positionMinutes) / \(progress.durationMinutes) мин")
                            .font(AppFont.caption())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Slim progress strip pinned to the very bottom edge
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(.white.opacity(0.25))
                        Rectangle()
                            .fill(theme.palette.accent)
                            .frame(width: max(0, min(1, progress.fractionComplete)) * geo.size.width)
                    }
                }
                .frame(height: 3)
            }
        }
        .frame(width: 240, height: 135)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var poster: some View {
        if let url = item?.bannerURL ?? item?.posterURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(theme.palette.surfaceElevated)
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(theme.palette.secondaryText)
            )
    }

    private func episodeLabel(for p: WatchProgress) -> String {
        if let item, item.kind == .movie {
            return "Фильм"
        }
        return "Серия \(p.episodeNumber)"
    }
}
