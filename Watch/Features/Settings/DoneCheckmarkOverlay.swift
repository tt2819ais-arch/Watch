import SwiftUI

/// Floating "Готово!" checkmark shown briefly after a destructive action.
/// Animates the checkmark drawing in with the spring scale used by Apple's
/// SF-Symbol bounce effect, dimming the rest of the screen behind a blur.
struct DoneCheckmarkOverlay: View {
    @EnvironmentObject private var theme: ThemeManager
    @State private var checked: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(theme.palette.primaryText)
                        .frame(width: 84, height: 84)
                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(theme.palette.background)
                        .scaleEffect(checked ? 1.0 : 0.2)
                        .opacity(checked ? 1.0 : 0.0)
                }
                .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 12)

                Text("Готово")
                    .font(AppFont.title3())
                    .foregroundStyle(.white)
                    .opacity(checked ? 1.0 : 0.0)
            }
            .padding(28)
        }
        .onAppear {
            withAnimation(.interpolatingSpring(stiffness: 240, damping: 14).delay(0.05)) {
                checked = true
            }
        }
    }
}
