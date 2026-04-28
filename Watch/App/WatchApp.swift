import SwiftUI
import AVFoundation

@main
struct WatchApp: App {
    @StateObject private var theme = ThemeManager.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var notifications = NotificationsService.shared
    @UIApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    init() {
        configureAudioSession()
        Logger.shared.info("App launched", category: .app)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(theme)
                .environmentObject(appState)
                .environmentObject(notifications)
                .preferredColorScheme(theme.preferredColorScheme)
                .tint(theme.palette.accent)
                .background(theme.palette.background.ignoresSafeArea())
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
