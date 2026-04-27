import Foundation

/// Resolves a working Kodik API token at runtime. Kodik rotates the public
/// tokens shared by OSS libraries, so we mirror the recovery flow used by
/// `anime_parsers_ru`:
///
/// 1. Try the user override (if any).
/// 2. Try the cached previously-validated token.
/// 3. Try the baked default.
/// 4. Fetch the obfuscated token list from the anime_parsers_ru repo,
///    decode it (reverse halves -> base64 each -> concatenate), validate
///    each candidate against `kodik-api.com`, and cache the first that works.
actor KodikTokenResolver {
    static let shared = KodikTokenResolver()

    private let cacheKey = "kodik.token.cached"
    private var inFlight: Task<String?, Never>?

    /// Once we've validated a token, remember the result for this run so we
    /// don't keep firing `?title=naruto` validation pings on every list call.
    private var verifiedToken: String?
    private var verifiedAt: Date?
    private let verificationTTL: TimeInterval = 30 * 60

    private let tokensURL = URL(string:
        "https://raw.githubusercontent.com/YaNesyTortiK/AnimeParsers/refs/heads/main/kdk_tokns/tokens.json"
    )!

    /// Returns the best currently-known token. Never throws — falls back to
    /// the baked default even when validation fails so the call site can
    /// still attempt and surface a meaningful error.
    func currentToken() async -> String {
        let userOverride = UserDefaults.standard.string(forKey: "kodik.token") ?? ""
        if !userOverride.isEmpty { return userOverride }

        // Fast path: a token we've already validated this session.
        if let token = verifiedToken,
           let at = verifiedAt,
           Date().timeIntervalSince(at) < verificationTTL {
            return token
        }

        // Try persisted cache first without validating — promote it to verified
        // state. If a request later fails, `markInvalid()` triggers a refresh.
        if let cached = UserDefaults.standard.string(forKey: cacheKey),
           !cached.isEmpty {
            verifiedToken = cached
            verifiedAt = Date()
            return cached
        }

        let baked = BakedSecrets.kodikToken
        if !baked.isEmpty, await validate(baked) {
            UserDefaults.standard.set(baked, forKey: cacheKey)
            verifiedToken = baked
            verifiedAt = Date()
            return baked
        }

        if let fresh = await refresh() {
            UserDefaults.standard.set(fresh, forKey: cacheKey)
            verifiedToken = fresh
            verifiedAt = Date()
            return fresh
        }
        return baked
    }

    /// Called by `KodikSource` when a request fails with auth/token errors so
    /// we drop the cached token and re-resolve next time.
    func markInvalid() {
        verifiedToken = nil
        verifiedAt = nil
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    /// Force a refresh from the public token list and return the first
    /// working token. Coalesces concurrent calls.
    @discardableResult
    func refresh() async -> String? {
        if let task = inFlight { return await task.value }
        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.fetchAndValidate()
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    // MARK: - Internals

    private func fetchAndValidate() async -> String? {
        do {
            let envelope: TokensEnvelope = try await HTTPClient.shared.get(tokensURL, as: TokensEnvelope.self)
            let candidates: [String] =
                (envelope.stable ?? []).compactMap { decode($0.tokn) } +
                (envelope.unstable ?? []).compactMap { decode($0.tokn) }
            for candidate in candidates {
                if await validate(candidate) {
                    Logger.shared.info("Kodik token resolver picked a working token", category: .source)
                    return candidate
                }
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s rate-limit
            }
            Logger.shared.warn("Kodik token resolver: no candidate worked", category: .source)
        } catch {
            Logger.shared.warn("Kodik token resolver: failed to fetch list — \(error)", category: .source)
        }
        return nil
    }

    /// Mirrors the python decrypt_token: reverse first half + reverse second
    /// half, base64-decode each, return `secondHalf + firstHalf`.
    private func decode(_ token: String) -> String? {
        let chars = Array(token)
        guard chars.count >= 2 else { return nil }
        let mid = chars.count / 2
        let firstHalfRev  = String(chars[..<mid].reversed())
        let secondHalfRev = String(chars[mid...].reversed())
        guard let p1Data = Data(base64Encoded: firstHalfRev),
              let p2Data = Data(base64Encoded: secondHalfRev),
              let p1 = String(data: p1Data, encoding: .utf8),
              let p2 = String(data: p2Data, encoding: .utf8) else { return nil }
        return p2 + p1
    }

    private func validate(_ token: String) async -> Bool {
        var c = URLComponents(string: "https://kodik-api.com/search")!
        c.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "title", value: "naruto")
        ]
        guard let url = c.url else { return false }
        do {
            let response: ValidateResponse = try await HTTPClient.shared.post(url, body: nil, as: ValidateResponse.self)
            return response.error == nil && (response.results?.isEmpty == false || response.total != nil)
        } catch {
            return false
        }
    }
}

private struct TokensEnvelope: Decodable {
    let stable: [TokenItem]?
    let unstable: [TokenItem]?
    let legacy: [TokenItem]?
}

private struct TokenItem: Decodable {
    let tokn: String
}

private struct ValidateResponse: Decodable {
    let error: String?
    let total: Int?
    let results: [DummyResult]?
}

private struct DummyResult: Decodable {
    let id: String?
}
