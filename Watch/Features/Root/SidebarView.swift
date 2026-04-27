import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(theme.palette.separator)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(AppState.Section.allCases) { section in
                    row(for: section)
                }
            }
            .padding(.vertical, 12)
            Spacer()
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Watch")
                .font(AppFont.largeTitle())
                .foregroundStyle(theme.palette.primaryText)
            Text("Аниме · Фильмы · Сериалы")
                .font(AppFont.subheadline())
                .foregroundStyle(theme.palette.secondaryText)
        }
        .padding(.top, 60)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func row(for section: AppState.Section) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                app.selectedSection = section
                app.sidebarVisible = false
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 18, weight: .heavy))
                    .frame(width: 28)
                Text(section.title)
                    .font(AppFont.headline())
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                app.selectedSection == section
                    ? theme.palette.surfaceElevated
                    : Color.clear
            )
            .foregroundStyle(theme.palette.primaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().background(theme.palette.separator)
            HStack {
                Text("v1.0")
                    .font(AppFont.footnote())
                    .foregroundStyle(theme.palette.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}
