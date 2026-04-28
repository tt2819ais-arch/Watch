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

                // Always-visible escape hatch. If the embedded webview never
                // loads or the AVPlayer can't open the URL, the regular
                // controls overlay is hidden behind the gesture surface and
                // the user has no way to back out. This always-on Close
                // button guarantees they can leave the screen.
                if !vm.locked && !vm.controlsVisible {
                    VStack {
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .heavy))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.black.opacity(0.55))
                                    .clipShape(Circle())
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.leading, 14)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(true)
                    .zIndex(50)
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

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Logger.shared.warn("Embed webview failed: \(error.localizedDescription)", category: .player)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Logger.shared.warn("Embed webview provisional fail: \(error.localizedDescription)", category: .player)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.scrollView.isScrollEnabled = false
        v.backgroundColor = .black
        v.isOpaque = false
        v.navigationDelegate = context.coordinator
        // Kodik (and similar) embeds gate on document.referrer / a desktop
        // UA — without these the iframe ends up blank or shows a "this
        // domain isn't allowed" message. Pretending to be desktop Safari
        // makes the players actually serve the video.
        v.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        return v
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard let url = url, context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        // Wrap the embed URL in a tiny HTML shell whose `baseURL` we set to
        // the Kodik origin. WKWebView's URLRequest "Referer" header is
        // stripped by the system on cross-origin loads, but document.referrer
        // is honoured when the iframe is embedded inside a parent page that
        // we control. This is the only reliable way to make Kodik (and most
        // ddos-guarded embed players) hand back the actual video stream on
        // iOS.
        let host = url.host ?? "kodik.cc"
        let parent = "https://\(host == "kodikplayer.com" ? "kodik.cc" : host)/"
        // HTML-encode the URL before splicing it into the iframe `src`. A
        // hostile content source could otherwise sneak `"` into the URL
        // string and break out of the attribute, injecting arbitrary HTML
        // into the parent shell. (`url.absoluteString` already produces a
        // %-encoded string for path/query, but `&` still needs to become
        // `&amp;` to be valid HTML.)
        let safeSrc = htmlAttrEscape(url.absoluteString)
        let html = """
        <!doctype html>
        <html><head>
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <style>
            html,body{margin:0;padding:0;background:#000;height:100%;width:100%;overflow:hidden;}
            iframe{position:absolute;inset:0;width:100%;height:100%;border:0;}
          </style>
        </head><body>
          <iframe src="\(safeSrc)" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>
        </body></html>
        """
        uiView.loadHTMLString(html, baseURL: URL(string: parent))
    }

    private func htmlAttrEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&#39;")
    }
}


