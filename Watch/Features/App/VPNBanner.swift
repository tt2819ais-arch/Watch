import SwiftUI

/// Top-of-screen banner shown while a VPN appears to be active. Fully
/// dismissible — once the user taps the close button we keep it
/// hidden for the rest of the session so it never gets in the way.
struct VPNBanner: View {
    @EnvironmentObject private var theme: ThemeManager
    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.palette.primaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Похоже, у вас включён VPN")
                        .font(AppFont.caption().weight(.semibold))
                        .foregroundStyle(theme.palette.primaryText)
                    Text("Если приложение тормозит — выключите VPN.")
                        .font(AppFont.caption())
                        .foregroundStyle(theme.palette.secondaryText)
                }
                Spacer(minLength: 6)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(theme.palette.secondaryText)
                        .padding(6)
                }
                .accessibilityLabel("Закрыть предупреждение")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
