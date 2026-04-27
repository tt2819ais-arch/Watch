import Foundation
import Combine

/// User-tunable playback / UI preferences. Persisted in UserDefaults so they
/// survive app restarts and stay consistent across episodes.
@MainActor
final class PlayerSettings: ObservableObject {
    static let shared = PlayerSettings()

    // MARK: - Skip behavior
    @Published var skipSeconds: Int { didSet { d.set(skipSeconds, forKey: K.skip) } }
    @Published var autoSkipIntro: Bool { didSet { d.set(autoSkipIntro, forKey: K.autoSkipIntro) } }
    @Published var autoSkipOutro: Bool { didSet { d.set(autoSkipOutro, forKey: K.autoSkipOutro) } }
    @Published var autoNextEpisode: Bool { didSet { d.set(autoNextEpisode, forKey: K.autoNext) } }

    // MARK: - Playback
    @Published var defaultSpeed: Double { didSet { d.set(defaultSpeed, forKey: K.speed) } }
    @Published var defaultZoomMode: ZoomMode {
        didSet { d.set(defaultZoomMode.rawValue, forKey: K.zoom) }
    }
    @Published var rememberQuality: Bool { didSet { d.set(rememberQuality, forKey: K.rememberQ) } }
    @Published var preferredQualityRaw: String {
        didSet { d.set(preferredQualityRaw, forKey: K.prefQ) }
    }

    // MARK: - Gestures
    @Published var enableSwipeGestures: Bool { didSet { d.set(enableSwipeGestures, forKey: K.swipe) } }
    @Published var enableDoubleTapSkip: Bool { didSet { d.set(enableDoubleTapSkip, forKey: K.dbltap) } }
    @Published var enableLongPressBoost: Bool { didSet { d.set(enableLongPressBoost, forKey: K.boost) } }
    @Published var longPressBoostSpeed: Double { didSet { d.set(longPressBoostSpeed, forKey: K.boostSpeed) } }

    private let d = UserDefaults.standard

    private init() {
        skipSeconds = d.integer(forKey: K.skip).positiveOr(10)
        autoSkipIntro = d.bool(forKey: K.autoSkipIntro)
        autoSkipOutro = d.bool(forKey: K.autoSkipOutro)
        autoNextEpisode = d.object(forKey: K.autoNext) == nil ? true : d.bool(forKey: K.autoNext)
        defaultSpeed = d.double(forKey: K.speed).positiveOr(1.0)
        if let raw = d.string(forKey: K.zoom), let z = ZoomMode(rawValue: raw) {
            defaultZoomMode = z
        } else {
            defaultZoomMode = .fit
        }
        rememberQuality = d.object(forKey: K.rememberQ) == nil ? true : d.bool(forKey: K.rememberQ)
        preferredQualityRaw = d.string(forKey: K.prefQ) ?? VideoQuality.fhd.rawValue
        enableSwipeGestures = d.object(forKey: K.swipe) == nil ? true : d.bool(forKey: K.swipe)
        enableDoubleTapSkip = d.object(forKey: K.dbltap) == nil ? true : d.bool(forKey: K.dbltap)
        enableLongPressBoost = d.object(forKey: K.boost) == nil ? true : d.bool(forKey: K.boost)
        longPressBoostSpeed = d.double(forKey: K.boostSpeed).positiveOr(2.0)
    }

    var preferredQuality: VideoQuality {
        get { VideoQuality(rawValue: preferredQualityRaw) ?? .fhd }
        set { preferredQualityRaw = newValue.rawValue }
    }

    private enum K {
        static let skip = "player.skipSeconds"
        static let autoSkipIntro = "player.autoSkipIntro"
        static let autoSkipOutro = "player.autoSkipOutro"
        static let autoNext = "player.autoNextEpisode"
        static let speed = "player.defaultSpeed"
        static let zoom = "player.defaultZoomMode"
        static let rememberQ = "player.rememberQuality"
        static let prefQ = "player.preferredQuality"
        static let swipe = "player.swipeGestures"
        static let dbltap = "player.dblTapSkip"
        static let boost = "player.longPressBoost"
        static let boostSpeed = "player.longPressBoostSpeed"
    }
}

enum ZoomMode: String, CaseIterable, Identifiable {
    /// Letterboxed: the whole frame is visible, may have black bars.
    case fit
    /// Crop: frame fills the screen, edges are clipped.
    case fill
    /// Stretch to screen size (distorts aspect ratio).
    case stretch
    /// Original pixel size, no scaling beyond intrinsic.
    case original

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fit: return "По размеру"
        case .fill: return "На весь экран"
        case .stretch: return "Растянуть"
        case .original: return "Оригинал"
        }
    }

    var systemImage: String {
        switch self {
        case .fit: return "rectangle.center.inset.filled"
        case .fill: return "rectangle.expand.vertical"
        case .stretch: return "arrow.up.left.and.arrow.down.right"
        case .original: return "rectangle"
        }
    }
}

private extension Int {
    func positiveOr(_ fallback: Int) -> Int { self > 0 ? self : fallback }
}
private extension Double {
    func positiveOr(_ fallback: Double) -> Double { self > 0 ? self : fallback }
}
