import SwiftUI
import AVFoundation

@main
struct WatchApp: App {
    @StateObject private var theme = ThemeManager.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var notifications = NotificationsService.shared
    @UIApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    @State private var splashFinished = false
    @State private var vpnBannerVisible = VPNDetector.isActive()

    init() {
        configureAudioSession()
        Logger.shared.info("App launched", category: .app)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(theme)
                    .environmentObject(appState)
                    .environmentObject(notifications)
                    .preferredColorScheme(theme.preferredColorScheme)
                    .tint(theme.palette.accent)
                    .background(theme.palette.background.ignoresSafeArea())
                    .overlay(alignment: .top) {
                        VPNBanner(isVisible: $vpnBannerVisible)
                            .environmentObject(theme)
                            .padding(.top, 4)
                    }
                    .onAppear {
                        UIApplication.shared.isIdleTimerDisabled = false
                    }
                    // Deep-link handler for `watch://u/<nickname>` (and the
                    // universal-link shape `https://.../u/<nickname>`). Routes
                    // the user to the Profile tab and asks `ProfileTabRoot`
                    // to push the matching `PublicProfileView`.
                    .onOpenURL { url in
                        appState.handle(url: url)
                    }

                if !splashFinished {
                    SplashView(onFinish: {
                        splashFinished = true
                    })
                    .environmentObject(theme)
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: splashFinished)
        }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .moviePlayback,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Logger.shared.error("AudioSession setup failed: \(error)", category: .player)
        }
    }
}

final class WatchAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.supported
    }
}
