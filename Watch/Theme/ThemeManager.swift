import SwiftUI
import Combine

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var current: AppTheme {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: Self.key)
            Logger.shared.info("Theme changed to \(current.rawValue)", category: .ui)
        }
    }

    private static let key = "watch.theme"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.key),
           let saved = AppTheme(rawValue: raw) {
            current = saved
        } else {
            current = .black
        }
    }

    var palette: ThemePalette {
        ThemePalette.palette(for: current)
    }

    var preferredColorScheme: ColorScheme? {
        current.preferredColorScheme
    }
}
