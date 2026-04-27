import Foundation
import AVFoundation
import AVKit
import Combine
import UIKit
import SwiftUI

@MainActor
final class PlayerViewModel: ObservableObject {
    let item: ContentItem
    let episodes: [Episode]

    @Published var currentEpisode: Episode
    @Published var currentSource: VideoSource?
    @Published var locked: Bool = false
    @Published var controlsVisible: Bool = true
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var availableQualities: [VideoQuality] = []
    @Published var availableVoiceTracks: [VoiceTrack] = []

    let player: AVPlayer
    let pipController: PiPController

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var controlsHideTask: Task<Void, Never>?
    private var statsAccumSeconds: Double = 0
    private var lastTickTime: Double = 0

    init(item: ContentItem, episodes: [Episode], initialEpisode: Episode) {
        self.item = item
        self.episodes = episodes
        self.currentEpisode = initialEpisode
        self.player = AVPlayer()
        self.pipController = PiPController()
        configureSource(for: initialEpisode)
    }

    var isHTMLEmbed: Bool {
        guard let url = currentSource?.url else { return false }
        return url.absoluteString.contains("kodik") || url.absoluteString.contains("/embed/")
    }

    var currentURL: URL? { currentSource?.url }

    func start() {
        installObservers()
        attemptResume()
        if !isHTMLEmbed { player.play() }
        scheduleControlsHide()
        Logger.shared.info("Player started: \(item.title) ep \(currentEpisode.number)", category: .player)
    }

    func stop() {
        recordProgress(force: true)
        player.pause()
        if let t = timeObserver { player.removeTimeObserver(t); timeObserver = nil }
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        Logger.shared.info("Player stopped", category: .player)
    }

    func togglePlay() {
        if player.rate == 0 {
            player.play()
        } else {
            player.pause()
        }
    }

    func seek(to seconds: Double) {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skip(_ delta: Double) {
        seek(to: max(0, min(currentTime + delta, duration)))
    }

    func setQuality(_ q: VideoQuality) {
        guard let voice = currentSource?.voiceTrack else { return }
        guard let next = currentEpisode.sources.first(where: { $0.quality == q && $0.voiceTrack.id == voice.id })
            ?? currentEpisode.sources.first(where: { $0.quality == q }) else { return }
        switchTo(next)
    }

    func setVoiceTrack(_ v: VoiceTrack) {
        guard let q = currentSource?.quality else { return }
        guard let next = currentEpisode.sources.first(where: { $0.voiceTrack.id == v.id && $0.quality == q })
            ?? currentEpisode.sources.first(where: { $0.voiceTrack.id == v.id }) else { return }
        switchTo(next)
    }

    func gotoEpisode(_ ep: Episode) {
        recordProgress(force: true)
        currentEpisode = ep
        configureSource(for: ep)
        attemptResume()
        if !isHTMLEmbed { player.play() }
    }

    func toggleControls() {
        controlsVisible.toggle()
        scheduleControlsHide()
    }

    func togglePiP() {
        pipController.toggle()
    }

    func toggleLock() {
        locked = true
        controlsVisible = false
    }

    // MARK: - Internals

    private func configureSource(for ep: Episode) {
        availableQualities = Array(Set(ep.sources.map { $0.quality })).sorted(by: >)
        availableVoiceTracks = Array(Set(ep.sources.map { $0.voiceTrack }))
        // Pick best quality on the first available voice track.
        let preferred = ep.sources.sorted { $0.quality > $1.quality }.first
        if let p = preferred {
            switchTo(p)
        }
    }

    private func switchTo(_ source: VideoSource) {
        let resumeAt = currentTime
        currentSource = source
        if isHTMLEmbed {
            // WebView handles loading; nothing else to do.
            return
        }
        let asset: AVURLAsset
        if !source.headers.isEmpty {
            asset = AVURLAsset(url: source.url, options: ["AVURLAssetHTTPHeaderFieldsKey": source.headers])
        } else {
            asset = AVURLAsset(url: source.url)
        }
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        if resumeAt > 1 {
            seek(to: resumeAt)
        }
    }

    private func installObservers() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.handleTick(time: time.seconds)
            }
        }
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in
                self?.isPlaying = p.rate > 0
            }
        }
        statusObserver = player.observe(\.currentItem?.status, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in
                guard let item = p.currentItem, item.status == .readyToPlay else { return }
                self?.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.recordProgress(force: true)
                if let next = self.nextEpisode() {
                    self.gotoEpisode(next)
                }
            }
        }
    }

    private func handleTick(time: Double) {
        guard time.isFinite else { return }
        let delta = time - lastTickTime
        if delta > 0 && delta < 5 && isPlaying {
            statsAccumSeconds += delta
        }
        lastTickTime = time
        currentTime = time
        // Persist progress every ~5 seconds.
        if Int(time) % 5 == 0 {
            recordProgress(force: false)
        }
    }

    private func recordProgress(force: Bool) {
        guard duration > 0 || force else { return }
        ProgressService.shared.update(
            itemID: item.id,
            episodeID: currentEpisode.id,
            episodeNumber: currentEpisode.number,
            position: currentTime,
            duration: duration
        )
        if statsAccumSeconds >= 30 || (force && statsAccumSeconds > 0) {
            StatsService.shared.record(
                itemID: item.id,
                itemTitle: item.title,
                kind: item.kind,
                episodeNumber: currentEpisode.number,
                watchedSeconds: statsAccumSeconds
            )
            statsAccumSeconds = 0
        }
    }

    private func attemptResume() {
        if let p = ProgressService.shared.progress(for: item.id, episodeID: currentEpisode.id),
           p.position > 5, !p.isFinished {
            seek(to: p.position)
        }
    }

    private func nextEpisode() -> Episode? {
        guard let i = episodes.firstIndex(where: { $0.id == currentEpisode.id }), i + 1 < episodes.count else {
            return nil
        }
        return episodes[i + 1]
    }

    private func scheduleControlsHide() {
        controlsHideTask?.cancel()
        controlsHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                guard let self else { return }
                if self.isPlaying {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.controlsVisible = false
                    }
                }
            }
        }
    }
}
