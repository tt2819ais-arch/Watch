import SwiftUI

struct PlayerControlsOverlay: View {
    @ObservedObject var vm: PlayerViewModel
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.7), .clear, Color.black.opacity(0.7)],
                startPoint: .top, endPoint: .bottom
            )
            VStack {
                topBar
                Spacer()
                centerControls
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .foregroundStyle(.white)
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button(action: dismiss) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 22, weight: .heavy))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.item.title)
                    .font(AppFont.headline())
                    .lineLimit(1)
                Text(vm.item.kind == .movie ? "Фильм" : "Серия \(vm.currentEpisode.number)")
                    .font(AppFont.subheadline())
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            qualityMenu
            voiceMenu
            Button { vm.togglePiP() } label: {
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 18, weight: .heavy))
            }
            Button { vm.toggleLock() } label: {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .heavy))
            }
        }
    }

    private var centerControls: some View {
        HStack(spacing: 56) {
            Button { vm.skip(-10) } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 32, weight: .heavy))
            }
            Button { vm.togglePlay() } label: {
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 56, weight: .heavy))
            }
            Button { vm.skip(10) } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 32, weight: .heavy))
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Slider(value: Binding(
                get: { vm.currentTime },
                set: { vm.seek(to: $0) }
            ), in: 0...max(vm.duration, 1))
            .tint(.white)
            HStack {
                Text(format(vm.currentTime))
                Spacer()
                if vm.duration > 0 {
                    Text("-\(format(max(vm.duration - vm.currentTime, 0)))")
                }
            }
            .font(AppFont.mono(13))
            .foregroundStyle(.white.opacity(0.85))
            episodePicker
        }
    }

    @ViewBuilder
    private var episodePicker: some View {
        if vm.episodes.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.episodes) { ep in
                        Button {
                            vm.gotoEpisode(ep)
                        } label: {
                            Text("\(ep.number)")
                                .font(AppFont.subheadline())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(ep.id == vm.currentEpisode.id ? Color.white : Color.white.opacity(0.15))
                                .foregroundStyle(ep.id == vm.currentEpisode.id ? Color.black : Color.white)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var qualityMenu: some View {
        Menu {
            ForEach(vm.availableQualities) { q in
                Button {
                    vm.setQuality(q)
                } label: {
                    HStack {
                        Text(q.displayName)
                        if vm.currentSource?.quality == q {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "4k.tv")
                Text(vm.currentSource?.quality.displayName ?? "—")
            }
            .font(AppFont.subheadline())
        }
    }

    private var voiceMenu: some View {
        Menu {
            ForEach(vm.availableVoiceTracks) { v in
                Button {
                    vm.setVoiceTrack(v)
                } label: {
                    HStack {
                        Text(v.displayName)
                        if vm.currentSource?.voiceTrack.id == v.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .heavy))
        }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let s = Int(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }
}
