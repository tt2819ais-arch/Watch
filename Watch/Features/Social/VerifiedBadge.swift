import SwiftUI

/// Inline blue checkmark next to a nickname for verified accounts.
struct VerifiedBadge: View {
    let isOfficial: Bool

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(isOfficial ? Color.yellow : Color.blue)
            .accessibilityLabel(isOfficial ? "Официальный аккаунт" : "Подтверждённый аккаунт")
    }
}

/// "Official Watch account" caption — sits below the nickname on the
/// `Watch` profile and on any account flagged `is_official`.
struct OfficialAccountCaption: View {
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color.yellow)
            Text("Официальный аккаунт Watch")
                .foregroundStyle(theme.palette.secondaryText)
        }
        .font(AppFont.footnote())
    }
}

/// Common view that draws "@nickname • badge" with optional secondary line.
struct NicknameLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    let user: PublicUser
    var titleFont: Font = AppFont.title2()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(user.handle)
                    .font(titleFont)
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
        }
    }
}
