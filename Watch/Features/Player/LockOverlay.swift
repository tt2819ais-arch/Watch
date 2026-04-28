import SwiftUI

/// Full-screen overlay shown when the player is locked. Single small lock
/// button in the corner so the user can unlock by tapping the icon twice.
struct LockOverlay: View {
    let unlock: () -> Void
    @State private var armed: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001).ignoresSafeArea()
            Button {
                if armed {
                    unlock()
                } else {
                    armed = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await MainActor.run { armed = false }
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(armed ? 0.85 : 0.55))
                        .frame(width: 56, height: 56)
                    Image(systemName: armed ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .padding(.top, 60)
            .padding(.trailing, 24)
        }
    }
}
