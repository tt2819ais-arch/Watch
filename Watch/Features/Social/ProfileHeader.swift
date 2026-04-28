import SwiftUI

/// Avatar + stats grid + bio block, shared between `SelfProfileView` and
/// `PublicProfileView` so both feel like the same kind of social profile
/// page (Instagram / VK shape — no posts, just identity + stats + actions).
struct ProfileHeader: View {
    @EnvironmentObject private var theme: ThemeManager

    let user: PublicUser
    let minutesTotal: Int?
    let episodesTotal: Int?
    let favoritesCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                avatar
                statsRow
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(user.handle)
                        .font(AppFont.title2())
                        .foregroundStyle(theme.palette.primaryText)
                    if user.verified || user.isOfficial {
                        VerifiedBadge(isOfficial: user.isOfficial)
                    }
                }
                if user.isOfficial {
                    OfficialAccountCaption()
                } else if user.isAdmin {
                    Text("Администратор")
                        .font(AppFont.footnote())
                        .foregroundStyle(theme.palette.secondaryText)
                }
                if !user.bio.isEmpty {
                    Text(user.bio)
                        .font(AppFont.subheadline())
                        .foregroundStyle(theme.palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var avatar: some View {
        Circle()
            .fill(theme.palette.surfaceElevated)
            .frame(width: 86, height: 86)
            .overlay {
                Text(String(user.nickname.prefix(1)).uppercased())
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundStyle(theme.palette.primaryText)
            }
            .overlay {
                Circle().strokeBorder(theme.palette.separator, lineWidth: 1)
            }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat(value: minutesTotal.map(formatThousands) ?? "—", label: "Минут")
            stat(value: episodesTotal.map(formatThousands) ?? "—", label: "Серий")
            stat(value: favoritesCount.map(String.init) ?? "—", label: "Любимое")
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            Text(label)
                .font(AppFont.caption())
                .foregroundStyle(theme.palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatThousands(_ n: Int) -> String {
        if n >= 1000 {
            let k = Double(n) / 1000.0
            if k >= 10 {
                return "\(Int(k.rounded()))k"
            }
            return String(format: "%.1fk", k)
        }
        return "\(n)"
    }
}

/// Pill-style action button used under the header (write / share / follow).
struct ProfileActionButton: View {
    @EnvironmentObject private var theme: ThemeManager

    let title: String
    let systemImage: String
    let style: Style
    let action: () -> Void

    enum Style {
        case primary, secondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(AppFont.button())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if style == .secondary {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.palette.separator, lineWidth: 1)
                }
            }
        }
    }

    private var background: Color {
        switch style {
        case .primary: return theme.palette.primaryText
        case .secondary: return theme.palette.surface
        }
    }
    private var foreground: Color {
        switch style {
        case .primary: return theme.palette.background
        case .secondary: return theme.palette.primaryText
        }
    }
}
