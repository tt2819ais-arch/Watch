import Foundation

enum HTTPMethod: String {
    case GET, POST
}

enum HTTPError: Error, LocalizedError {
    case invalidURL
    case status(Int, body: String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .status(let c, let b): return "HTTP \(c): \(b.prefix(200))"
        case .decoding(let e): return "Decoding error: \(e.localizedDescription)"
        case .transport(let e): return "Network error: \(e.localizedDescription)"
        }
    }
}

actor HTTPClient {
    static let shared = HTTPClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    /// Run the URLSession data task on a detached, non-cancellable Task so
    /// SwiftUI's `.task` modifier tearing down (e.g. TabView reordering or
    /// theme changes that cascade through the view tree) does not propagate
    /// cancellation into the network request itself.
    private func detachedFetch(_ req: URLRequest) async throws -> (Data, URLResponse) {
        let session = self.session
        return try await Task.detached(priority: .userInitiated) {
            try await session.data(for: req)
        }.value
    }

    func get<T: Decodable>(
        _ url: URL,
        as: T.Type,
        headers: [String: String] = [:]
    ) async throws -> T {
        try await request(url: url, method: .GET, body: nil, headers: headers, as: T.self)
    }

    func post<T: Decodable>(
        _ url: URL,
        body: Data?,
        as: T.Type,
        headers: [String: String] = [:]
    ) async throws -> T {
        try await request(url: url, method: .POST, body: body, headers: headers, as: T.self)
    }

    private func request<T: Decodable>(
        url: URL,
        method: HTTPMethod,
        body: Data?,
        headers: [String: String],
        as: T.Type
    ) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if !headers.keys.contains("User-Agent") {
            req.setValue("Watch/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        }
        if !headers.keys.contains("Accept") {
            req.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        req.httpBody = body
        Logger.shared.debug("HTTP \(method.rawValue) \(url.absoluteString)", category: .network)

        // Retry transparently on transient transport failures, including
        // SwiftUI `.task` cancellations (NSURLErrorCancelled) that bubble out
        // when a TabView re-evaluates its children. We wrap the data load in
        // a detached Task so the network call survives the parent cancelling.
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let (data, resp) = try await detachedFetch(req)
                guard let http = resp as? HTTPURLResponse else {
                    throw HTTPError.transport(URLError(.badServerResponse))
                }
                if !(200...299).contains(http.statusCode) {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    Logger.shared.warn("HTTP \(http.statusCode) for \(url.absoluteString) — \(body.prefix(200))", category: .network)
                    throw HTTPError.status(http.statusCode, body: body)
                }
                do {
                    return try decoder.decode(T.self, from: data)
                } catch {
                    Logger.shared.warn("Decode failed for \(url.absoluteString): \(error)", category: .network)
                    throw HTTPError.decoding(error)
                }
            } catch let e as HTTPError {
                throw e
            } catch {
                lastError = error
                let nsErr = error as NSError
                let isCancelled = nsErr.code == NSURLErrorCancelled
                let isTimeout = nsErr.code == NSURLErrorTimedOut
                let isConnLost = nsErr.code == NSURLErrorNetworkConnectionLost
                if attempt < 2 && (isCancelled || isTimeout || isConnLost) {
                    Logger.shared.warn("Transient \(nsErr.code) on \(url.absoluteString), retrying…", category: .network)
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    continue
                }
                Logger.shared.error("Transport error \(url.absoluteString): \(error)", category: .network)
                throw HTTPError.transport(error)
            }
        }
        throw HTTPError.transport(lastError ?? URLError(.unknown))
    }
}
