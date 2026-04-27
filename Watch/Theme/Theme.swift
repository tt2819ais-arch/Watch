import SwiftUI

enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case black
    case white
    case gray

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .black: return "Чёрная"
        case .white: return "Белая"
        case .gray:  return "Серая"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .black: return .dark
        case .white: return .light
        case .gray:  return .dark
        }
    }
}

struct ThemePalette {
    let background: Color
    let surface: Color
    let surfaceElevated: Color
    let primaryText: Color
    let secondaryText: Color
    let separator: Color
    let accent: Color
    let danger: Color

    static let black = ThemePalette(
        background: Color(red: 0.00, green: 0.00, blue: 0.00),
        surface: Color(red: 0.07, green: 0.07, blue: 0.07),
        surfaceElevated: Color(red: 0.12, green: 0.12, blue: 0.12),
        primaryText: Color.white,
        secondaryText: Color(white: 0.70),
        separator: Color(white: 0.15),
        accent: Color.white,
        danger: Color(red: 0.95, green: 0.30, blue: 0.30)
    )

    static let white = ThemePalette(
        background: Color.white,
        surface: Color(red: 0.96, green: 0.96, blue: 0.97),
        surfaceElevated: Color(red: 0.92, green: 0.92, blue: 0.94),
        primaryText: Color.black,
        secondaryText: Color(white: 0.30),
        separator: Color(white: 0.85),
        accent: Color.black,
        danger: Color(red: 0.85, green: 0.25, blue: 0.25)
    )

    static let gray = ThemePalette(
        background: Color(red: 0.18, green: 0.18, blue: 0.20),
        surface: Color(red: 0.23, green: 0.23, blue: 0.25),
        surfaceElevated: Color(red: 0.28, green: 0.28, blue: 0.31),
        primaryText: Color.white,
        secondaryText: Color(white: 0.78),
        separator: Color(white: 0.40),
        accent: Color.white,
        danger: Color(red: 0.95, green: 0.40, blue: 0.40)
    )

    static func palette(for theme: AppTheme) -> ThemePalette {
        switch theme {
        case .black: return .black
        case .white: return .white
        case .gray:  return .gray
        }
    }
}
