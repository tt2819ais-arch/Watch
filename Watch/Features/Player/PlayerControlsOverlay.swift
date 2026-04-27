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
                skipBanners
                bottomBar
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)

            if let count = vm.nextEpisodeCountdown, count > 0 {
                nextEpisodeBanner(count: count)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(28)
            }
        }
        .foregroundStyle(.white)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button(action: dismiss) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 22, weight: .heavy))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.item.title)
                    .font(AppFont.headline())
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(vm.item.kind == .movie ? "Фильм" : "Серия \(vm.currentEpisode.number)")
                    if vm.sleepTimer != .off {
                        Text("· 💤 \(formatRemaining(vm.sleepRemaining))")
                    }
                }
                .font(AppFont.subheadline())
                .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            zoomButton
            speedMenu
            sleepMenu
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
            Button { vm.skipBackward() } label: {
                VStack(spacing: 2) {
                    Image(systemName: "gobackward")
                        .font(.system(size: 30, weight: .heavy))
                    Text("\(vm.settings.skipSeconds)")
                        .font(AppFont.caption())
                }
            }
            Button { vm.togglePlay() } label: {
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 56, weight: .heavy))
            }
            Button { vm.skipForward() } label: {
                VStack(spacing: 2) {
                    Image(systemName: "goforward")
                        .font(.system(size: 30, weight: .heavy))
                    Text("\(vm.settings.skipSeconds)")
                        .font(AppFont.caption())
                }
            }
        }
    }

    @ViewBuilder
    private var skipBanners: some View {
        HStack {
            Spacer()
            if vm.introSkipAvailable {
                pillButton("Пропустить заставку", icon: "forward.fill") { vm.skipIntro() }
            }
            if vm.outroSkipAvailable {
                pillButton("К следующей серии", icon: "forward.end.fill") { vm.skipOutro() }
            }
        }
        .padding(.bottom, 6)
    }

    private func pillButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(AppFont.subheadline())
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.18))
            .foregroundStyle(.white)
            .clipShape(Capsule())
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

    private var zoomButton: some View {
        Menu {
            ForEach(ZoomMode.allCases) { m in
                Button {
                    vm.setZoomMode(m)
                } label: {
                    HStack {
                        Image(systemName: m.systemImage)
                        Text(m.displayName)
                        if vm.zoomMode == m { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Image(systemName: vm.zoomMode.systemImage)
                .font(.system(size: 18, weight: .heavy))
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { v in
                Button {
                    vm.setPlaybackSpeed(v)
                } label: {
                    HStack {
                        Text("\(formatSpeed(v))×")
                        if abs(vm.playbackSpeed - v) < 0.01 { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Text("\(formatSpeed(vm.playbackSpeed))×")
                .font(AppFont.subheadline())
        }
    }

    private var sleepMenu: some View {
        Menu {
            ForEach(PlayerViewModel.SleepTimer.allCases) { t in
                Button {
                    vm.setSleepTimer(t)
                } label: {
                    HStack {
                        Text(t.displayName)
                        if vm.sleepTimer == t { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Image(systemName: vm.sleepTimer == .off ? "moon" : "moon.fill")
                .font(.system(size: 18, weight: .heavy))
        }
    }

    private func nextEpisodeBanner(count: Int) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Следующая серия")
                    .font(AppFont.subheadline())
                    .foregroundStyle(.white.opacity(0.8))
                Text("через \(count)…")
                    .font(AppFont.headline())
                    .foregroundStyle(.white)
            }
            Button { vm.cancelNextCountdown() } label: {
                Text("Отмена")
                    .font(AppFont.button())
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.white.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    private func formatSpeed(_ value: Double) -> String {
        if value == floor(value) { return "\(Int(value))" }
        return String(format: "%g", value)
    }

    private func formatRemaining(_ s: TimeInterval) -> String {
        let total = Int(max(0, s))
        let m = total / 60
        let sec = total % 60
        return String(format: "%d:%02d", m, sec)
    }
}
