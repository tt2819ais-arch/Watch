import SwiftUI

/// Sheet shown before launching the player so the user can pick voice track
/// and quality up-front instead of during playback.
struct PrePlayPicker: View {
    @EnvironmentObject private var theme: ThemeManager
    let item: ContentItem
    let episode: Episode
    /// Called with `nil` if cancelled, or with the (possibly mutated) episode
    /// re-ordered so the chosen source is first — the player picks the head
    /// of `sources` by default.
    let onSelect: (Episode?) -> Void

    @State private var selectedVoiceID: String?
    @State private var selectedQuality: VideoQuality?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    voiceSection
                    qualitySection
                    playButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(theme.palette.background.ignoresSafeArea())
            .navigationTitle("Перед просмотром")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { onSelect(nil) }
                }
            }
        }
        .onAppear { restoreDefaults() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(AppFont.title3())
                .foregroundStyle(theme.palette.primaryText)
            if item.kind != .movie {
                Text("Серия \(episode.number)")
                    .font(AppFont.subheadline())
                    .foregroundStyle(theme.palette.secondaryText)
            }
        }
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Озвучка")
                .font(AppFont.headline())
                .foregroundStyle(theme.palette.primaryText)
            if availableVoices.isEmpty {
                Text("Источник предоставляет один трек")
                    .font(AppFont.subheadline())
                    .foregroundStyle(theme.palette.secondaryText)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(availableVoices) { v in
                        let active = (selectedVoiceID ?? availableVoices.first?.id) == v.id
                        Button {
                            selectedVoiceID = v.id
                        } label: {
                            Text(v.studio)
                                .font(AppFont.subheadline())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(active ? theme.palette.primaryText : theme.palette.surface)
                                .foregroundStyle(active ? theme.palette.background : theme.palette.primaryText)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Качество")
                .font(AppFont.headline())
                .foregroundStyle(theme.palette.primaryText)
            HStack(spacing: 8) {
                ForEach(availableQualities, id: \.self) { q in
                    let active = (selectedQuality ?? defaultQuality) == q
                    Button {
                        selectedQuality = q
                    } label: {
                        Text(q.displayName)
                            .font(AppFont.subheadline())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(active ? theme.palette.primaryText : theme.palette.surface)
                            .foregroundStyle(active ? theme.palette.background : theme.palette.primaryText)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private var playButton: some View {
        Button {
            let chosenVoice = selectedVoiceID ?? availableVoices.first?.id
            let chosenQuality = selectedQuality ?? defaultQuality
            let reordered = reorderSources(voiceID: chosenVoice, quality: chosenQuality)
            let updated = Episode(
                id: episode.id,
                number: episode.number,
                title: episode.title,
                durationSeconds: episode.durationSeconds,
                thumbnailURL: episode.thumbnailURL,
                sources: reordered,
                openingStart: episode.openingStart,
                openingStop: episode.openingStop,
                endingStart: episode.endingStart,
                endingStop: episode.endingStop
            )
            onSelect(updated)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .heavy))
                Text("Запустить")
                    .font(AppFont.headline())
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(theme.palette.primaryText)
            .foregroundStyle(theme.palette.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(episode.sources.isEmpty)
    }

    private var availableVoices: [VoiceTrack] {
        var seen: Set<String> = []
        return episode.sources.compactMap { s -> VoiceTrack? in
            guard !seen.contains(s.voiceTrack.id) else { return nil }
            seen.insert(s.voiceTrack.id)
            return s.voiceTrack
        }
    }

    private var availableQualities: [VideoQuality] {
        let voiceID = selectedVoiceID ?? availableVoices.first?.id
        let scoped = episode.sources.filter { voiceID == nil || $0.voiceTrack.id == voiceID }
        let unique = Array(Set(scoped.map { $0.quality }))
        return unique.sorted { $0.orderValue > $1.orderValue }
    }

    private var defaultQuality: VideoQuality {
        if PlayerSettings.shared.rememberQuality {
            return PlayerSettings.shared.preferredQuality
        }
        return availableQualities.first ?? .hd
    }

    private func restoreDefaults() {
        selectedVoiceID = availableVoices.first?.id
        selectedQuality = defaultQuality
    }

    private func reorderSources(voiceID: String?, quality: VideoQuality) -> [VideoSource] {
        // Put the chosen (voice, quality) match first, then the rest in
        // unchanged order so the player can still fall back if needed.
        guard !episode.sources.isEmpty else { return episode.sources }
        let perfect = episode.sources.first(where: { src in
            (voiceID == nil || src.voiceTrack.id == voiceID) && src.quality == quality
        })
        let perVoice = episode.sources.first(where: { src in
            voiceID == nil || src.voiceTrack.id == voiceID
        })
        let head = perfect ?? perVoice ?? episode.sources.first!
        var rest = episode.sources
        if let idx = rest.firstIndex(where: { $0.id == head.id }) {
            rest.remove(at: idx)
        }
        return [head] + rest
    }
}
