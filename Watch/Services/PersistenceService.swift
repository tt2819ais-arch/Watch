import Foundation

/// JSON-backed key-value persistence under Documents/.
/// Used by FavoritesService, ProgressService and StatsService.
final class PersistenceService: @unchecked Sendable {
    static let shared = PersistenceService()

    private let directory: URL
    private let queue = DispatchQueue(label: "watch.persistence", qos: .utility)

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        directory = docs.appendingPathComponent("storage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let url = self.url(for: key)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            Logger.shared.error("Persistence decode failed for \(key): \(error)", category: .persistence)
            return nil
        }
    }

    func save<T: Encodable>(_ value: T, key: String) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(value)
                try data.write(to: self.url(for: key), options: .atomic)
            } catch {
                Logger.shared.error("Persistence encode failed for \(key): \(error)", category: .persistence)
            }
        }
    }

    func remove(key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }
}
