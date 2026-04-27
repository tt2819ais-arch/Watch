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
            HStack(spacing: 8) {
                ForEach([Logger.Level?.none, .debug, .info, .warn, .error], id: \.self) { lvl in
                    Button {
                        filter = lvl
                    } label: {
                        Text(lvl?.rawValue.capitalized ?? "Все")
                            .font(AppFont.caption())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(filter == lvl ? theme.palette.surfaceElevated : theme.palette.surface)
                            .foregroundStyle(theme.palette.primaryText)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = Logger.shared.exportText()
                    copiedFlash = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await MainActor.run { copiedFlash = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedFlash ? "checkmark" : "doc.on.doc")
                        Text(copiedFlash ? "Скопировано" : "Копировать")
                    }
                    .font(AppFont.subheadline())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(theme.palette.surface)
                    .foregroundStyle(theme.palette.primaryText)
                    .clipShape(Capsule())
                }
                Button {
                    Logger.shared.clear()
                    entries = []
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .heavy))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(theme.palette.surface)
                        .foregroundStyle(theme.palette.primaryText)
                        .clipShape(Capsule())
                }
            }
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

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filtered.suffix(800)) { e in
                        row(for: e)
                            .id(e.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .onChange(of: filtered.count) { _, _ in
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
