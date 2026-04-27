import SwiftUI

struct FilterSheet: View {
    @EnvironmentObject private var theme: ThemeManager
    @Binding var filter: CatalogFilter
    let availableGenres: [Genre]
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CatalogFilter = CatalogFilter()
    private let yearOptions: [Int] = Array(stride(from: 2025, through: 1960, by: -1))

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    sortSection
                    yearSection
                    genresSection
                }
                .padding(20)
            }
            .background(theme.palette.background.ignoresSafeArea())
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Сброс") {
                        draft = CatalogFilter()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Применить") {
                        filter = draft
                        dismiss()
                    }
                    .font(AppFont.headline())
                }
            }
        }
        .onAppear { draft = filter }
        .preferredColorScheme(theme.preferredColorScheme)
    }

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Сортировка")
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            HStack(spacing: 8) {
                ForEach(CatalogFilter.Sort.allCases) { s in
                    Button {
                        draft.sort = s
                    } label: {
                        Text(s.displayName)
                            .font(AppFont.subheadline())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(draft.sort == s ? theme.palette.surfaceElevated : theme.palette.surface)
                            .foregroundStyle(theme.palette.primaryText)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var yearSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Год выпуска")
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            HStack(spacing: 12) {
                yearPicker(title: "От", binding: Binding(
                    get: { draft.yearFrom ?? 0 },
                    set: { draft.yearFrom = $0 == 0 ? nil : $0 }
                ))
                yearPicker(title: "До", binding: Binding(
                    get: { draft.yearTo ?? 0 },
                    set: { draft.yearTo = $0 == 0 ? nil : $0 }
                ))
            }
        }
    }

    private func yearPicker(title: String, binding: Binding<Int>) -> some View {
        Menu {
            Button("Любой") { binding.wrappedValue = 0 }
            ForEach(yearOptions, id: \.self) { y in
                Button("\(String(y))") { binding.wrappedValue = y }
            }
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(theme.palette.secondaryText)
                Spacer()
                Text(binding.wrappedValue == 0 ? "Любой" : "\(String(binding.wrappedValue))")
                    .foregroundStyle(theme.palette.primaryText)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(theme.palette.secondaryText)
            }
            .font(AppFont.body())
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var genresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Жанры")
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            FlowLayout(spacing: 8) {
                ForEach(availableGenres) { g in
                    let selected = draft.genres.contains(g.id)
                    Button {
                        if selected { draft.genres.remove(g.id) } else { draft.genres.insert(g.id) }
                    } label: {
                        Text(g.name)
                            .font(AppFont.subheadline())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selected ? theme.palette.primaryText : theme.palette.surface)
                            .foregroundStyle(selected ? theme.palette.background : theme.palette.primaryText)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Simple flow layout for genre chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let result = layout(width: width, subviews: subviews)
        return CGSize(width: width.isInfinite ? result.usedWidth : width, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(width: bounds.width, subviews: subviews)
        for (i, frame) in result.frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func layout(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat, usedWidth: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxRowWidth = max(maxRowWidth, x)
        }
        return (frames, y + lineHeight, maxRowWidth)
    }
}
