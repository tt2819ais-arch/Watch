import SwiftUI
import AVKit
import AVFoundation
import Combine
import WebKit

struct PlayerView: View {
    @EnvironmentObject private var theme: ThemeManager
    @StateObject private var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var dragStartBrightness: Double = 0
    @State private var didStartLeftDrag = false

    init(item: ContentItem, episodes: [Episode], initialEpisode: Episode) {
        _vm = StateObject(wrappedValue: PlayerViewModel(
            item: item,
            episodes: episodes,
            initialEpisode: initialEpisode
        ))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                videoLayer(in: geo.size)

                // Tap & gesture surface — only active when no controls are
                // visible. While the controls overlay is on screen the
                // overlay's own buttons / menus / scrubber take priority and
                // gestures here would steal taps and cause "auto collapse"
                // weirdness reported in earlier builds.
                if !vm.locked && !vm.controlsVisible {
                    gestureSurface(size: geo.size)
                }

                hudOverlays

                if vm.locked {
                    LockOverlay(unlock: { vm.locked = false })
                        .ignoresSafeArea()
                } else if vm.controlsVisible {
                    PlayerControlsOverlay(vm: vm, dismiss: { dismiss() })
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            OrientationLock.lock(.landscape)
            vm.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            OrientationLock.lock(.all)
            vm.stop()
        }
    }

    @ViewBuilder
    private func videoLayer(in size: CGSize) -> some View {
        if vm.isHTMLEmbed {
            EmbedWebPlayer(url: vm.currentURL)
                .ignoresSafeArea()
        } else {
            AVPlayerLayerView(player: vm.player, pip: vm.pipController, mode: vm.zoomMode, customZoom: vm.customZoom)
                .ignoresSafeArea()
        }
    }

    private func gestureSurface(size: CGSize) -> some View {
        Color.black.opacity(0.0001)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            // Single tap → toggle controls
            .onTapGesture {
                guard !vm.locked else { return }
                vm.toggleControls()
            }
            // Double tap → skip ±N
            .gesture(
                SpatialTapGesture(count: 2)
                    .onEnded { value in
                        guard !vm.locked, vm.settings.enableDoubleTapSkip else { return }
                        let half = size.width / 2
                        if value.location.x < half {
                            vm.skipBackward()
                        } else {
                            vm.skipForward()
                        }
                    }
            )
            // Long press → speed boost while held
            .gesture(
                LongPressGesture(minimumDuration: 0.45)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        switch value {
                        case .second(true, _): vm.startSpeedBoost()
                        default: break
                        }
                    }
                    .onEnded { _ in vm.endSpeedBoost() }
            )
            // Vertical drag on the left half adjusts brightness. The right
            // half is intentionally a no-op — system volume is only changed
            // via the iPhone hardware buttons / Control Center, never via a
            // swipe gesture (per UX request).
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard !vm.locked, vm.settings.enableSwipeGestures else { return }
                        // Ignore mostly-horizontal drags so we don't fight scrubbing.
                        if abs(value.translation.width) > abs(value.translation.height) { return }
                        let half = size.width / 2
                        guard value.startLocation.x < half else { return }
                        let progress = -Double(value.translation.height / max(1, size.height))
                        if !didStartLeftDrag {
                            didStartLeftDrag = true
                            dragStartBrightness = vm.currentBrightness()
                        }
                        vm.setBrightness(dragStartBrightness + progress)
                    }
                    .onEnded { _ in
                        didStartLeftDrag = false
                    }
            )
    }

    private var hudOverlays: some View {
        ZStack {
            if let v = vm.brightnessOverlay {
                hud(systemImage: "sun.max.fill", value: v)
            }
            if let s = vm.seekHUD {
                Text("\(s.direction == .forward ? "+" : "−")\(s.seconds) с")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
            }
            if vm.showSpeedHUD {
                Text("\(String(format: "%.2f", vm.playbackSpeed))×")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .offset(y: -160)
            }
        }
        .allowsHitTesting(false)
    }

    private func hud(systemImage: String, value: Double) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(.white)
            Capsule()
                .fill(.white.opacity(0.25))
                .frame(width: 4, height: 100)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(.white)
                        .frame(width: 4, height: 100 * CGFloat(value))
                }
        }
        .padding(.vertical, 14).padding(.horizontal, 22)
        .background(.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// AVPlayerLayer wrapper that also installs an AVPictureInPictureController
/// and respects the user's chosen zoom mode.
struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let pip: PiPController
    let mode: ZoomMode
    let customZoom: CGFloat

    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.playerLayer.player = player
        applyMode(to: v.playerLayer)
        pip.attach(to: v.playerLayer)
        return v
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
        applyMode(to: uiView.playerLayer)
        let scale = max(1.0, min(2.5, customZoom))
        uiView.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    private func applyMode(to layer: AVPlayerLayer) {
        switch mode {
        case .fit:      layer.videoGravity = .resizeAspect
        case .fill:     layer.videoGravity = .resizeAspectFill
        case .stretch:  layer.videoGravity = .resize
        case .original: layer.videoGravity = .resizeAspect
        }
    }
}

final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct EmbedWebPlayer: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.scrollView.isScrollEnabled = false
        v.backgroundColor = .black
        v.isOpaque = false
        return v
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let url = url, uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }
}


