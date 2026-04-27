import SwiftUI
import Combine

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var current: AppTheme {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: Self.themeKey)
            Logger.shared.info("Theme changed to \(current.rawValue)", category: .ui)
        }
    }

    @Published var accent: AccentColor {
        didSet {
            UserDefaults.standard.set(accent.rawValue, forKey: Self.accentKey)
        }
    }

    @Published var fontScale: FontScale {
        didSet {
            UserDefaults.standard.set(fontScale.rawValue, forKey: Self.fontKey)
        }
    }

    private static let themeKey = "watch.theme"
    private static let accentKey = "watch.accent"
    private static let fontKey = "watch.fontScale"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.themeKey),
           let saved = AppTheme(rawValue: raw) {
            current = saved
        } else {
            current = .black
        }
        if let raw = UserDefaults.standard.string(forKey: Self.accentKey),
           let v = AccentColor(rawValue: raw) {
            accent = v
        } else {
            accent = .neutral
        }
        if let raw = UserDefaults.standard.string(forKey: Self.fontKey),
           let v = FontScale(rawValue: raw) {
            fontScale = v
        } else {
            fontScale = .normal
        }
    }

    var palette: ThemePalette {
        let base = ThemePalette.palette(for: current)
        return ThemePalette(
            background: base.background,
            surface: base.surface,
            surfaceElevated: base.surfaceElevated,
            primaryText: base.primaryText,
            secondaryText: base.secondaryText,
            separator: base.separator,
            accent: accent == .neutral ? base.accent : accent.color,
            danger: base.danger
        )
    }

    var preferredColorScheme: ColorScheme? {
        current.preferredColorScheme
    }
}

enum AccentColor: String, CaseIterable, Identifiable {
    case neutral, blue, red, green, orange, purple, pink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .neutral: return "Без акцента"
        case .blue:    return "Синий"
        case .red:     return "Красный"
        case .green:   return "Зелёный"
        case .orange:  return "Оранжевый"
        case .purple:  return "Фиолетовый"
        case .pink:    return "Розовый"
        }
    }

    var color: Color {
        switch self {
        case .neutral: return .white
        case .blue:    return Color(red: 0.30, green: 0.55, blue: 1.00)
        case .red:     return Color(red: 0.95, green: 0.30, blue: 0.30)
        case .green:   return Color(red: 0.30, green: 0.85, blue: 0.50)
        case .orange:  return Color(red: 1.00, green: 0.60, blue: 0.20)
        case .purple:  return Color(red: 0.70, green: 0.45, blue: 0.95)
        case .pink:    return Color(red: 0.95, green: 0.45, blue: 0.65)
        }
    }
}

enum FontScale: String, CaseIterable, Identifiable {
    case compact, normal, large

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .compact: return "Компактный"
        case .normal:  return "Стандарт"
        case .large:   return "Крупный"
        }
    }
    var multiplier: CGFloat {
        switch self {
        case .compact: return 0.92
        case .normal:  return 1.0
        case .large:   return 1.10
        }
    }
}
