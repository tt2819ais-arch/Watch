import Foundation
import Combine

/// In-app logger. Writes to memory ring buffer and to disk so users can
/// copy logs from the Settings screen when something goes wrong.
final class Logger: @unchecked Sendable {
    static let shared = Logger()

    enum Level: String, Codable {
        case debug, info, warn, error
        var symbol: String {
            switch self {
            case .debug: return "·"
            case .info:  return "i"
            case .warn:  return "!"
            case .error: return "x"
            }
        }
    }

    enum Category: String, Codable {
        case app, ui, network, player, persistence, stats, source
    }

    struct Entry: Codable, Identifiable {
        let id: UUID
        let date: Date
        let level: Level
        let category: Category
        let message: String
    }

    private let queue = DispatchQueue(label: "watch.logger", qos: .utility)
    private let maxEntries: Int = 5000
    private var ring: [Entry] = []
    private let fileURL: URL
    private let dateFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Subject for live updates in the LogsView.
    let publisher = PassthroughSubject<Entry, Never>()

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = dir.appendingPathComponent("watch.log")
        ring.reserveCapacity(maxEntries)
        info("Logger initialized — file: \(fileURL.path)", category: .app)
    }

    func debug(_ message: @autoclosure () -> String, category: Category = .app) {
        log(.debug, message(), category: category)
    }
    func info(_ message: @autoclosure () -> String, category: Category = .app) {
        log(.info, message(), category: category)
    }
    func warn(_ message: @autoclosure () -> String, category: Category = .app) {
        log(.warn, message(), category: category)
    }
    func error(_ message: @autoclosure () -> String, category: Category = .app) {
        log(.error, message(), category: category)
    }

    private func log(_ level: Level, _ message: String, category: Category) {
        let entry = Entry(id: UUID(), date: Date(), level: level, category: category, message: message)
        queue.async { [weak self] in
            guard let self else { return }
            self.ring.append(entry)
            if self.ring.count > self.maxEntries {
                self.ring.removeFirst(self.ring.count - self.maxEntries)
            }
            self.appendToDisk(entry)
        }
        // Console mirror
        #if DEBUG
        print("[\(level.symbol)][\(category.rawValue)] \(message)")
        #endif
        publisher.send(entry)
    }

    func snapshot() -> [Entry] {
        queue.sync { ring }
    }

    func exportText() -> String {
        let entries = snapshot()
        return entries.map { e in
            "\(dateFmt.string(from: e.date)) [\(e.level.rawValue)] [\(e.category.rawValue)] \(e.message)"
        }.joined(separator: "\n")
    }

    func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            self.ring.removeAll(keepingCapacity: true)
            try? FileManager.default.removeItem(at: self.fileURL)
        }
    }

    private func appendToDisk(_ entry: Entry) {
        let line = "\(dateFmt.string(from: entry.date)) [\(entry.level.rawValue)] [\(entry.category.rawValue)] \(entry.message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let h = try? FileHandle(forWritingTo: fileURL) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            }
        } else {
            try? data.write(to: fileURL)
        }
    }
}
