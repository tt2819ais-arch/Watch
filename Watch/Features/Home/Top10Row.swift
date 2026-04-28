import SwiftUI

/// Netflix-style "Top 10 this week" row: each tile pairs a giant rank
/// number with the item's poster. Picks the highest-rated items across
/// all three kinds (anime / movies / series). Items with no rating are
/// excluded so the ranking always reflects user-visible scores.
struct Top10Row: View {
    @EnvironmentObject private var theme: ThemeManager
    let items: [ContentItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item) {
                        Top10Tile(rank: index + 1, item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct Top10Tile: View {
    @EnvironmentObject private var theme: ThemeManager
    let rank: Int
    let item: ContentItem

    private var rankWidth: CGFloat { rank == 10 ? 110 : 78 }

    var body: some View {
        HStack(alignment: .bottom, spacing: -22) {
            Text("\(rank)")
                .font(.system(size: 140, weight: .black, design: .rounded))
                .foregroundStyle(theme.palette.primaryText.opacity(0.92))
                .frame(width: rankWidth, alignment: .leading)
                // The big digit's natural ascender / descender pads more
                // than we want; pull it down so the baseline aligns with
                // the bottom of the poster, which is what reads correctly.
                .padding(.bottom, -18)

            poster
                .frame(width: 110, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private var poster: some View {
        if let url = item.posterURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(theme.palette.surfaceElevated)
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(theme.palette.secondaryText)
            )
    }
}
