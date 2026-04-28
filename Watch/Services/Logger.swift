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
        // Bring forward the previous session's log so the LogsView can show
        // "Вчера / Сегодня" sections even after the user has relaunched the
        // app. Keep only the last `maxEntries` lines so the in-memory ring
        // stays bounded; the on-disk file we leave intact for the user to
        // copy/share manually.
        loadPersistedLogs()
        info("Logger initialized — file: \(fileURL.path)", category: .app)
    }

    private func loadPersistedLogs() {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Disk format: `<iso8601> [<level>] [<category>] <message>` per line.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var loaded: [Entry] = []
        loaded.reserveCapacity(min(lines.count, maxEntries))
        let slice = lines.suffix(maxEntries)
        for raw in slice {
            let line = String(raw)
            // Find first space — separates date from the rest.
            guard let firstSpace = line.firstIndex(of: " ") else { continue }
            let dateRaw = String(line[..<firstSpace])
            guard let date = parser.date(from: dateRaw) else { continue }
            var rest = line[line.index(after: firstSpace)...]
            // Level: `[level] `
            guard rest.hasPrefix("["),
                  let levelEnd = rest.firstIndex(of: "]") else { continue }
            let levelRaw = String(rest[rest.index(after: rest.startIndex)..<levelEnd])
            guard let level = Level(rawValue: levelRaw) else { continue }
            rest = rest[rest.index(after: levelEnd)...].drop(while: { $0 == " " })
            // Category: `[category] `
            guard rest.hasPrefix("["),
                  let catEnd = rest.firstIndex(of: "]") else { continue }
            let catRaw = String(rest[rest.index(after: rest.startIndex)..<catEnd])
            let category = Category(rawValue: catRaw) ?? .app
            rest = rest[rest.index(after: catEnd)...].drop(while: { $0 == " " })
            let message = String(rest)
            loaded.append(Entry(id: UUID(), date: date, level: level, category: category, message: message))
        }
        ring = loaded
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
        rotateIfNeeded()
    }

    /// Cap the on-disk log at ~2 MB; when the file grows past that we
    /// keep only the second half so logs survive across launches without
    /// growing unbounded.
    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int, size > 2_000_000 else { return }
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.suffix(lines.count / 2).joined(separator: "\n")
        try? kept.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }
}
