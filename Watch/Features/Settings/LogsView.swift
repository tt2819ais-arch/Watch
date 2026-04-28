import SwiftUI
import Combine

struct LogsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @State private var entries: [Logger.Entry] = []
    @State private var filter: Logger.Level? = nil
    @State private var search: String = ""
    @State private var copiedFlash: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            controlBar
            list
        }
        .background(theme.palette.background.ignoresSafeArea())
        .navigationTitle("Логи")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            entries = Logger.shared.snapshot()
        }
        .onReceive(Logger.shared.publisher.collect(.byTime(DispatchQueue.main, .seconds(1)))) { batch in
            entries.append(contentsOf: batch)
            if entries.count > 5000 {
                entries.removeFirst(entries.count - 5000)
            }
        }
    }

    private var controlBar: some View {
        VStack(spacing: 8) {
            // Level chips can overflow on narrow devices, so put them in a
            // horizontal scroll instead of competing with the action buttons
            // for space (which used to squash "Копировать" into a single
            // 1-character-wide column).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([Logger.Level?.none, .debug, .info, .warn, .error], id: \.self) { lvl in
                        Button {
                            filter = lvl
                        } label: {
                            Text(lvl?.rawValue.capitalized ?? "Все")
                                .font(AppFont.caption())
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(filter == lvl ? theme.palette.surfaceElevated : theme.palette.surface)
                                .foregroundStyle(theme.palette.primaryText)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.palette.secondaryText)
                    TextField("Фильтр по тексту…", text: $search)
                        .font(AppFont.subheadline())
                        .foregroundStyle(theme.palette.primaryText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(theme.palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: .infinity)

                Button {
                    UIPasteboard.general.string = Logger.shared.exportText()
                    copiedFlash = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await MainActor.run { copiedFlash = false }
                    }
                } label: {
                    Image(systemName: copiedFlash ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 16, weight: .heavy))
                        .frame(width: 36, height: 36)
                        .background(theme.palette.surface)
                        .foregroundStyle(theme.palette.primaryText)
                        .clipShape(Circle())
                }
                .accessibilityLabel(copiedFlash ? "Скопировано" : "Копировать лог")

                Button {
                    Logger.shared.clear()
                    entries = []
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .heavy))
                        .frame(width: 36, height: 36)
                        .background(theme.palette.surface)
                        .foregroundStyle(theme.palette.primaryText)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Очистить логи")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var filtered: [Logger.Entry] {
        var arr = entries
        if let f = filter { arr = arr.filter { $0.level == f } }
        if !search.isEmpty {
            arr = arr.filter { $0.message.localizedCaseInsensitiveContains(search) }
        }
        return arr
    }

    private struct LogSection: Identifiable {
        let title: String
        let entries: [Logger.Entry]
        var id: String { title }
    }

    private var sections: [LogSection] {
        let recent = Array(filtered.suffix(800))
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        var buckets: [(String, Int, [Logger.Entry])] = []  // (title, sortKey, entries)
        var byDay: [Date: [Logger.Entry]] = [:]
        for e in recent {
            let day = cal.startOfDay(for: e.date)
            byDay[day, default: []].append(e)
        }
        for (day, list) in byDay {
            let title: String
            if day == today { title = "Сегодня" }
            else if day == yesterday { title = "Вчера" }
            else { title = sectionFormatter.string(from: day) }
            buckets.append((title, Int(day.timeIntervalSince1970), list))
        }
        // Newest day on top.
        buckets.sort { $0.1 > $1.1 }
        return buckets.map { LogSection(title: $0.0, entries: $0.2) }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.entries) { e in
                                row(for: e)
                                    .id(e.id)
                            }
                        } header: {
                            Text(section.title)
                                .font(AppFont.caption().weight(.semibold))
                                .foregroundStyle(theme.palette.secondaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(theme.palette.background)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .onChange(of: filtered.count) { _ in
                if let last = filtered.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func row(for e: Logger.Entry) -> some View {
        let color: Color = {
            switch e.level {
            case .debug: return theme.palette.secondaryText
            case .info:  return theme.palette.primaryText
            case .warn:  return Color.orange
            case .error: return theme.palette.danger
            }
        }()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(timeFormatter.string(from: e.date))
                Text("[\(e.level.rawValue)]")
                    .foregroundStyle(color)
                Text("[\(e.category.rawValue)]")
                    .foregroundStyle(theme.palette.secondaryText)
            }
            .font(AppFont.mono(11))
            Text(e.message)
                .font(AppFont.mono(12))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contextMenu {
            Button("Скопировать") {
                UIPasteboard.general.string = e.message
            }
        }
    }
}

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

private let sectionFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ru_RU")
    f.dateFormat = "d MMMM"
    return f
}()
