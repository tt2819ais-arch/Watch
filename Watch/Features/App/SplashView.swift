import SwiftUI

/// Brief welcome animation shown on every cold launch. Picks a random
/// pair of phrases ("Подбираем фильмы под ваш вкус. / Наслаждайтесь
/// просмотром"), fades in a small loading dot animation, then dismisses
/// itself after ~2.4 seconds. Style is intentionally minimal — single
/// line of text, three pulsing dots, no logos or gradients — to match
/// the rest of the app.
struct SplashView: View {
    @EnvironmentObject private var theme: ThemeManager
    let onFinish: () -> Void

    @State private var phraseIndex: Int = Int.random(in: 0..<SplashView.phrases.count)
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 12
    @State private var subtitleOpacity: Double = 0
    @State private var dotPhase: Int = 0
    @State private var dotsTimer: Task<Void, Never>?

    static let phrases: [(primary: String, secondary: String)] = [
        ("Настраиваем вашу ленту фильмов",  "Приятного просмотра 🎬"),
        ("Подбираем фильмы под ваш вкус",   "Наслаждайтесь просмотром"),
        ("Собираем для вас лучшие фильмы",  "Хорошего вечера"),
        ("Формируем вашу кино-ленту",       "Приятного просмотра"),
        ("Ищем фильмы, которые вам понравятся", "Уютного просмотра"),
        ("Настраиваем подборку кино",       "Получайте удовольствие"),
        ("Готовим для вас идеальные фильмы","Приятного отдыха"),
        ("Подбираем кино специально для вас","Наслаждайтесь"),
        ("Создаём вашу персональную ленту фильмов", "Приятного просмотра"),
        ("Собираем кино под ваше настроение", "Хорошего просмотра")
    ]

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            VStack(spacing: 14) {
                Text(phrase.primary)
                    .font(AppFont.title3().weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.palette.primaryText)
                    .opacity(titleOpacity)
                    .offset(y: titleOffset)

                Text(phrase.secondary)
                    .font(AppFont.subheadline())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.palette.secondaryText)
                    .opacity(subtitleOpacity)

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { idx in
                        Circle()
                            .fill(theme.palette.primaryText)
                            .frame(width: 6, height: 6)
                            .opacity(dotPhase == idx ? 1.0 : 0.25)
                    }
                }
                .padding(.top, 6)
                .opacity(subtitleOpacity)
            }
            .padding(.horizontal, 32)
        }
        .onAppear { runAnimation() }
        .onDisappear { dotsTimer?.cancel() }
    }

    private var phrase: (primary: String, secondary: String) {
        SplashView.phrases[phraseIndex]
    }

    private func runAnimation() {
        withAnimation(.easeOut(duration: 0.35)) {
            titleOpacity = 1
            titleOffset = 0
        }
        withAnimation(.easeOut(duration: 0.35).delay(0.2)) {
            subtitleOpacity = 1
        }
        dotsTimer = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 280_000_000)
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    dotPhase = (dotPhase + 1) % 3
                }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            withAnimation(.easeIn(duration: 0.3)) {
                titleOpacity = 0
                subtitleOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 320_000_000)
            onFinish()
        }
    }
}
