import UIKit
import SwiftUI

/// Drives both AppDelegate's supported orientations and forces an immediate
/// rotation when the player presents/dismisses.
enum OrientationLock {
    static var supported: UIInterfaceOrientationMask = .all

    static func lock(_ mask: UIInterfaceOrientationMask) {
        supported = mask
        DispatchQueue.main.async {
            applyImmediateRotation(mask: mask)
        }
    }

    private static func applyImmediateRotation(mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else { return }
        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
            scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        } else {
            // Fallback: not used since deployment target is iOS 16
        }
    }
}
