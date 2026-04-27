import SwiftUI
import AVKit
import AVFoundation
import Combine
import WebKit

struct PlayerView: View {
    @EnvironmentObject private var theme: ThemeManager
    @StateObject private var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    init(item: ContentItem, episodes: [Episode], initialEpisode: Episode) {
        _vm = StateObject(wrappedValue: PlayerViewModel(
            item: item,
            episodes: episodes,
            initialEpisode: initialEpisode
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if vm.isHTMLEmbed {
                EmbedWebPlayer(url: vm.currentURL)
                    .ignoresSafeArea()
            } else {
                AVPlayerLayerView(player: vm.player, pip: vm.pipController)
                    .ignoresSafeArea()
            }

            // Tap area to toggle controls
            Color.black.opacity(0.0001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if !vm.locked {
                        vm.toggleControls()
                    }
                }

            if vm.locked {
                LockOverlay(unlock: { vm.locked = false })
                    .ignoresSafeArea()
            } else if vm.controlsVisible {
                PlayerControlsOverlay(vm: vm, dismiss: { dismiss() })
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            vm.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            vm.stop()
        }
    }
}

/// AVPlayerLayer wrapper that also installs an AVPictureInPictureController.
struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let pip: PiPController

    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        pip.attach(to: v.playerLayer)
        return v
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
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
