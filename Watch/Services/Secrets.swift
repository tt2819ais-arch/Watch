import Foundation

/// Build-time secrets bundled into the IPA. The default values here are safe
/// to commit — for the real values CI overwrites this file with one generated
/// from GitHub Actions secrets. See `.github/workflows/build.yml` and
/// `Tools/inject_secrets.sh`.
///
/// Anything baked here is also overridable at runtime via UserDefaults so the
/// user can paste their own keys in **Settings → Sources** without rebuilding.
enum BakedSecrets {
    /// Public Kodik fallback token (rotates periodically). The app also
    /// auto-recovers via `KodikTokenResolver` which fetches the freshest
    /// list from the anime_parsers_ru maintainer's repo and validates them.
    static let kodikToken: String = "56a768d08f43091901c44b54fe970049"

    /// PoiskKino API key. Empty by default in source — CI substitutes this
    /// from the `POISKKINO_API_TOKEN` repository secret at build time.
    static let poiskkinoToken: String = ""
}

/// Runtime resolver — UserDefaults override beats the baked default.
enum AppSecrets {
    static var kodikToken: String {
        let override = UserDefaults.standard.string(forKey: "kodik.token") ?? ""
        return override.isEmpty ? BakedSecrets.kodikToken : override
    }

    static var poiskkinoToken: String {
        let override = UserDefaults.standard.string(forKey: "poiskkino.token") ?? ""
        return override.isEmpty ? BakedSecrets.poiskkinoToken : override
    }
}
