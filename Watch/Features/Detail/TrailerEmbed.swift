import SwiftUI
import WebKit

/// Inline auto-playing muted YouTube trailer for the detail hero.
/// Accepts any YouTube URL form (watch?v=, youtu.be, /embed/) and
/// rewrites it to the embed form with `autoplay=1&mute=1&playsinline=1`.
struct TrailerEmbed: View {
    let trailerURL: URL

    var body: some View {
        if let embed = Self.youtubeAutoplayEmbed(from: trailerURL) {
            TrailerWebView(url: embed)
                .allowsHitTesting(false) // hero is decorative; tap goes to "Смотреть"
        } else {
            EmptyView()
        }
    }

    /// Convert a YouTube URL of any form to a muted-autoplay-loop embed.
    /// Returns nil if the URL is not a recognisable YouTube link.
    static func youtubeAutoplayEmbed(from url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        var videoID: String?
        if host.contains("youtu.be") {
            videoID = url.lastPathComponent
        } else if host.contains("youtube.com") || host.contains("youtube-nocookie.com") {
            if url.path.hasPrefix("/embed/") {
                videoID = url.lastPathComponent
            } else if let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?
                        .first(where: { $0.name == "v" })?.value {
                videoID = q
            }
        }
        guard let id = videoID, !id.isEmpty else { return nil }
        // `playlist=<id>` is required for `loop=1` on a single-video embed.
        return URL(string:
            "https://www.youtube-nocookie.com/embed/\(id)?" +
            "autoplay=1&mute=1&controls=0&loop=1&playlist=\(id)" +
            "&modestbranding=1&playsinline=1&rel=0&iv_load_policy=3"
        )
    }
}

private struct TrailerWebView: UIViewRepresentable {
    let url: URL

    final class Coordinator: NSObject {
        var loadedURL: URL?
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
        return v
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        let html = """
        <!doctype html>
        <html><head>
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <style>
            html, body { margin: 0; padding: 0; background: #000; height: 100%; overflow: hidden; }
            iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
          </style>
        </head><body>
          <iframe src="\(url.absoluteString)" allow="autoplay; encrypted-media" allowfullscreen></iframe>
        </body></html>
        """
        uiView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com/"))
    }
}
