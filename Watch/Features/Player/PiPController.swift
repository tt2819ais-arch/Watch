import Foundation
import AVKit
import AVFoundation

/// Wraps AVPictureInPictureController so the SwiftUI view can toggle PiP.
final class PiPController: NSObject, AVPictureInPictureControllerDelegate {
    private var pip: AVPictureInPictureController?

    func attach(to layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            Logger.shared.warn("PiP not supported on this device", category: .player)
            return
        }
        let controller = AVPictureInPictureController(playerLayer: layer)
        controller?.delegate = self
        if #available(iOS 14.2, *) {
            controller?.canStartPictureInPictureAutomaticallyFromInline = true
        }
        pip = controller
    }

    func toggle() {
        guard let pip else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    // MARK: - Delegate

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Logger.shared.error("PiP failed: \(error)", category: .player)
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Logger.shared.info("PiP will start", category: .player)
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Logger.shared.info("PiP will stop", category: .player)
    }
}
