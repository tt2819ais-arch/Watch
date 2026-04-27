import SwiftUI

struct ContinueWatchingRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let progressItems: [WatchProgress]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(progressItems) { p in
                    NavigationLink(value: p) {
                        card(for: p)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func card(for p: WatchProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.palette.surfaceElevated)
                    .frame(width: 220, height: 124)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Серия \(p.episodeNumber)")
                    }
                    .font(AppFont.headline())
                    .foregroundStyle(theme.palette.primaryText)
                    Text("\(p.positionMinutes) / \(p.durationMinutes) мин")
                        .font(AppFont.footnote())
                        .foregroundStyle(theme.palette.secondaryText)
                    ProgressView(value: p.fractionComplete)
                        .progressViewStyle(.linear)
                        .tint(theme.palette.accent)
                        .frame(width: 200)
                }
                .padding(12)
            }
        }
    }
}
