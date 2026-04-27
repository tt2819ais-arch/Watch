import Foundation
import AVFoundation
import AVKit
import Combine
import UIKit
import SwiftUI
import MediaPlayer

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

    // New: aspect / zoom / speed / overlays
    @Published var zoomMode: ZoomMode
    @Published var playbackSpeed: Double
    @Published var customZoom: CGFloat = 1.0
    @Published var showSpeedHUD: Bool = false
    @Published var brightnessOverlay: Double? = nil   // 0...1 transient
    @Published var volumeOverlay: Double? = nil       // 0...1 transient
    @Published var seekHUD: SeekHUD? = nil
    @Published var introSkipAvailable: Bool = false
    @Published var outroSkipAvailable: Bool = false
    @Published var sleepTimer: SleepTimer = .off
    @Published var sleepRemaining: TimeInterval = 0
    @Published var nextEpisodeCountdown: Int? = nil

    // Scrubbing state — owned by the slider, separate from currentTime so the
    // player's time observer doesn't fight the user's drag.
    @Published var scrubbing: Bool = false
    @Published var scrubPosition: Double = 0
    private var wasPlayingBeforeScrub: Bool = false

    let player: AVPlayer
    let pipController: PiPController
    let settings = PlayerSettings.shared

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var controlsHideTask: Task<Void, Never>?
    private var statsAccumSeconds: Double = 0
    private var lastTickTime: Double = 0
    private var sleepTask: Task<Void, Never>?
    private var nextCountdownTask: Task<Void, Never>?
    private var savedSpeedBeforeBoost: Double?
    private var didAutoSkipIntro: Bool = false
    private var didAutoSkipOutro: Bool = false
    private var hudClearTask: Task<Void, Never>?

    init(item: ContentItem, episodes: [Episode], initialEpisode: Episode) {
        self.item = item
        self.episodes = episodes
        self.currentEpisode = initialEpisode
        self.player = AVPlayer()
        self.pipController = PiPController()
        self.zoomMode = PlayerSettings.shared.defaultZoomMode
        self.playbackSpeed = PlayerSettings.shared.defaultSpeed
        configureSource(for: initialEpisode)
    }

    var isHTMLEmbed: Bool {
        guard let url = currentSource?.url else { return false }
        return url.absoluteString.contains("kodik") || url.absoluteString.contains("/embed/")
    }

    var currentURL: URL? { currentSource?.url }

    var hasIntroMarker: Bool {
        currentEpisode.openingStart != nil && currentEpisode.openingStop != nil
    }
    var hasOutroMarker: Bool {
        currentEpisode.endingStart != nil
    }

    func start() {
        installObservers()
        attemptResume()
        applyPlaybackRate()
        if !isHTMLEmbed { player.play() }
        scheduleControlsHide()
        Logger.shared.info("Player started: \(item.title) ep \(currentEpisode.number)", category: .player)
    }

    func stop() {
        recordProgress(force: true)
        player.pause()
        sleepTask?.cancel()
        nextCountdownTask?.cancel()
        if let t = timeObserver { player.removeTimeObserver(t); timeObserver = nil }
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        Logger.shared.info("Player stopped", category: .player)
    }

    func togglePlay() {
        if player.rate == 0 {
            applyPlaybackRate()
        } else {
            player.pause()
        }
    }

    func seek(to seconds: Double) {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func beginScrubbing() {
        scrubbing = true
        scrubPosition = currentTime
        wasPlayingBeforeScrub = isPlaying
        player.pause()
        scheduleControlsHide(extra: true)
    }

    func endScrubbing() {
        let target = scrubPosition
        let cm = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.scrubbing = false
                if self.wasPlayingBeforeScrub {
                    self.applyPlaybackRate()
                }
            }
        }
    }

    func skip(_ delta: Double) {
        seek(to: max(0, min(currentTime + delta, duration)))
        showSeekHUD(delta: delta)
    }

    func skipBackward() {
        skip(-Double(settings.skipSeconds))
    }
    func skipForward() {
        skip(Double(settings.skipSeconds))
    }

    func setQuality(_ q: VideoQuality) {
        guard let voice = currentSource?.voiceTrack else { return }
        guard let next = currentEpisode.sources.first(where: { $0.quality == q && $0.voiceTrack.id == voice.id })
            ?? currentEpisode.sources.first(where: { $0.quality == q }) else { return }
        switchTo(next)
        if settings.rememberQuality { settings.preferredQuality = q }
    }

    func setVoiceTrack(_ v: VoiceTrack) {
        guard let q = currentSource?.quality else { return }
        guard let next = currentEpisode.sources.first(where: { $0.voiceTrack.id == v.id && $0.quality == q })
            ?? currentEpisode.sources.first(where: { $0.voiceTrack.id == v.id }) else { return }
        switchTo(next)
    }

    func setPlaybackSpeed(_ value: Double) {
        playbackSpeed = value
        applyPlaybackRate()
    }

    func cycleZoomMode() {
        let order: [ZoomMode] = [.fit, .fill, .stretch, .original]
        let i = order.firstIndex(of: zoomMode) ?? 0
        zoomMode = order[(i + 1) % order.count]
        customZoom = 1.0
        settings.defaultZoomMode = zoomMode
    }

    func setZoomMode(_ m: ZoomMode) {
        zoomMode = m
        customZoom = 1.0
        settings.defaultZoomMode = m
    }

    func gotoEpisode(_ ep: Episode) {
        recordProgress(force: true)
        cancelNextCountdown()
        didAutoSkipIntro = false
        didAutoSkipOutro = false
        currentEpisode = ep
        configureSource(for: ep)
        attemptResume()
        applyPlaybackRate()
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

    // MARK: - Sleep timer

    enum SleepTimer: String, CaseIterable, Identifiable {
        case off, m15, m30, m45, m60, endOfEpisode
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .off: return "Выкл"
            case .m15: return "15 мин"
            case .m30: return "30 мин"
            case .m45: return "45 мин"
            case .m60: return "60 мин"
            case .endOfEpisode: return "После серии"
            }
        }
        var seconds: TimeInterval? {
            switch self {
            case .off: return nil
            case .m15: return 15 * 60
            case .m30: return 30 * 60
            case .m45: return 45 * 60
            case .m60: return 60 * 60
            case .endOfEpisode: return nil
            }
        }
    }

    func setSleepTimer(_ t: SleepTimer) {
        sleepTimer = t
        sleepTask?.cancel()
        guard let secs = t.seconds else {
            sleepRemaining = 0
            return
        }
        sleepRemaining = secs
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    if self.isPlaying {
                        self.sleepRemaining -= 1
                        if self.sleepRemaining <= 0 {
                            self.player.pause()
                            self.sleepTimer = .off
                        }
                    }
                }
            }
        }
    }

    // MARK: - Skip intro / outro

    func skipIntro() {
        if let stop = currentEpisode.openingStop {
            seek(to: stop)
        }
    }

    func skipOutro() {
        if let next = nextEpisode() {
            gotoEpisode(next)
        } else if let stop = currentEpisode.endingStop {
            seek(to: stop)
        }
    }

    // MARK: - Long press boost

    func startSpeedBoost() {
        guard settings.enableLongPressBoost else { return }
        savedSpeedBeforeBoost = playbackSpeed
        playbackSpeed = settings.longPressBoostSpeed
        applyPlaybackRate()
        showSpeedHUD = true
    }

    func endSpeedBoost() {
        if let saved = savedSpeedBeforeBoost {
            playbackSpeed = saved
            applyPlaybackRate()
            savedSpeedBeforeBoost = nil
        }
        showSpeedHUD = false
    }

    // MARK: - Brightness / Volume gestures

    func setBrightness(_ v: Double) {
        let clamped = max(0, min(1, v))
        UIScreen.main.brightness = CGFloat(clamped)
        brightnessOverlay = clamped
        scheduleHUDClear()
    }

    func currentBrightness() -> Double { Double(UIScreen.main.brightness) }

    func setSystemVolume(_ v: Double) {
        let clamped = max(0, min(1, v))
        VolumeSlider.shared.set(value: Float(clamped))
        volumeOverlay = clamped
        scheduleHUDClear()
    }

    private func scheduleHUDClear() {
        hudClearTask?.cancel()
        hudClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                self?.brightnessOverlay = nil
                self?.volumeOverlay = nil
            }
        }
    }

    private func showSeekHUD(delta: Double) {
        let direction: SeekHUD.Direction = delta >= 0 ? .forward : .backward
        seekHUD = SeekHUD(direction: direction, seconds: Int(abs(delta)))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run { self?.seekHUD = nil }
        }
    }

    // MARK: - Internals

    private func applyPlaybackRate() {
        player.rate = Float(playbackSpeed)
    }

    private func configureSource(for ep: Episode) {
        availableQualities = Array(Set(ep.sources.map { $0.quality })).sorted(by: >)
        availableVoiceTracks = Array(Set(ep.sources.map { $0.voiceTrack }))
        // Pick preferred quality if user remembers it; else best.
        let preferred: VideoSource? = {
            if settings.rememberQuality,
               let m = ep.sources.first(where: { $0.quality == settings.preferredQuality }) {
                return m
            }
            return ep.sources.sorted { $0.quality > $1.quality }.first
        }()
        if let p = preferred {
            switchTo(p)
        }
    }

    private func switchTo(_ source: VideoSource) {
        let resumeAt = currentTime
        currentSource = source
        if isHTMLEmbed {
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
        applyPlaybackRate()
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
                if self.sleepTimer == .endOfEpisode {
                    self.sleepTimer = .off
                    self.player.pause()
                    return
                }
                if self.settings.autoNextEpisode, let next = self.nextEpisode() {
                    self.startNextEpisodeCountdown(to: next)
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

        // Intro/outro markers
        if let s = currentEpisode.openingStart, let e = currentEpisode.openingStop, time >= s, time <= e {
            introSkipAvailable = true
            if settings.autoSkipIntro && !didAutoSkipIntro {
                didAutoSkipIntro = true
                seek(to: e)
                Logger.shared.info("Auto-skipped intro to \(Int(e))s", category: .player)
            }
        } else {
            introSkipAvailable = false
        }
        if let s = currentEpisode.endingStart, let e = currentEpisode.endingStop, time >= s, time <= e {
            outroSkipAvailable = true
            if settings.autoSkipOutro && !didAutoSkipOutro {
                didAutoSkipOutro = true
                seek(to: e)
                Logger.shared.info("Auto-skipped outro to \(Int(e))s", category: .player)
            }
        } else {
            outroSkipAvailable = false
        }

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

    private func startNextEpisodeCountdown(to next: Episode) {
        nextCountdownTask?.cancel()
        nextEpisodeCountdown = 5
        nextCountdownTask = Task { [weak self] in
            for _ in 0..<5 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    if let n = self.nextEpisodeCountdown { self.nextEpisodeCountdown = max(0, n - 1) }
                }
            }
            await MainActor.run {
                guard let self else { return }
                if self.nextEpisodeCountdown != nil {
                    self.gotoEpisode(next)
                }
            }
        }
    }

    func cancelNextCountdown() {
        nextCountdownTask?.cancel()
        nextEpisodeCountdown = nil
    }

    /// Bumped from 4 → 7 seconds because users were losing the controls
    /// while still actively hunting for menus.
    private func scheduleControlsHide(extra: Bool = false) {
        controlsHideTask?.cancel()
        let delayNs: UInt64 = extra ? 12_000_000_000 : 7_000_000_000
        controlsHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNs)
            await MainActor.run {
                guard let self else { return }
                if self.isPlaying && !self.scrubbing {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.controlsVisible = false
                    }
                }
            }
        }
    }
}

struct SeekHUD: Identifiable {
    enum Direction { case forward, backward }
    let id = UUID()
    let direction: Direction
    let seconds: Int
}

/// Hidden MPVolumeView so we can set the system volume programmatically.
final class VolumeSlider {
    static let shared = VolumeSlider()
    private let view = MPVolumeView(frame: .zero)
    private var slider: UISlider? {
        view.subviews.first(where: { $0 is UISlider }) as? UISlider
    }
    func set(value: Float) {
        slider?.setValue(value, animated: false)
        slider?.sendActions(for: .valueChanged)
    }
}
