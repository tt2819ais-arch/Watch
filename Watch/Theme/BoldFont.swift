import SwiftUI

/// Apple-style bold typography helpers.
/// Uses SF Pro Rounded with heavy weights to feel solid and minimal.
enum AppFont {
    static func largeTitle() -> Font { .system(size: 34, weight: .heavy, design: .rounded) }
    static func title() -> Font      { .system(size: 28, weight: .heavy, design: .rounded) }
    static func title2() -> Font     { .system(size: 22, weight: .heavy, design: .rounded) }
    static func title3() -> Font     { .system(size: 20, weight: .bold,  design: .rounded) }
    static func headline() -> Font   { .system(size: 17, weight: .heavy, design: .rounded) }
    static func body() -> Font       { .system(size: 16, weight: .semibold, design: .rounded) }
    static func subheadline() -> Font { .system(size: 14, weight: .semibold, design: .rounded) }
    static func footnote() -> Font   { .system(size: 12, weight: .semibold, design: .rounded) }
    static func caption() -> Font    { .system(size: 11, weight: .bold,  design: .rounded) }
    static func button() -> Font     { .system(size: 16, weight: .heavy, design: .rounded) }

    static func mono(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
}

/// Common modifier to apply bold body styling everywhere.
struct BoldBody: ViewModifier {
    func body(content: Content) -> some View {
        content.font(AppFont.body())
    }
}

extension View {
    func boldBody() -> some View { modifier(BoldBody()) }
}
