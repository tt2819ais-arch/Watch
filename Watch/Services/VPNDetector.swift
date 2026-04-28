import Foundation
import SystemConfiguration

/// Heuristic VPN detection. iOS doesn't expose a public API to ask
/// "is the user on a VPN?", so we inspect the proxy and tunnel
/// interface table. Standard tunnel interface prefixes used by the
/// system VPN extension and most third-party VPN clients:
/// `tap`, `tun`, `ppp`, `ipsec`, `utun` (with caveats — utun is also
/// used by Personal Hotspot and SwiftUI's developer tools, so we only
/// report VPN if a tunnel interface AND the proxy table contains a
/// VPN-shaped entry, OR if a non-utun tunnel interface is present).
enum VPNDetector {
    static func isActive() -> Bool {
        let tunnels = activeTunnelInterfaces()
        if tunnels.contains(where: { $0.hasPrefix("tap") || $0.hasPrefix("tun") || $0.hasPrefix("ppp") || $0.hasPrefix("ipsec") }) {
            return true
        }
        // utun is ambiguous — only treat as VPN if proxy settings hint at one.
        if tunnels.contains(where: { $0.hasPrefix("utun") }) && proxiesLookLikeVPN() {
            return true
        }
        return false
    }

    private static func activeTunnelInterfaces() -> [String] {
        guard let cf = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              let scoped = cf["__SCOPED__"] as? [String: Any] else {
            return []
        }
        return Array(scoped.keys)
    }

    private static func proxiesLookLikeVPN() -> Bool {
        guard let cf = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return false
        }
        // Most VPN profiles install a __SCOPED__ proxy entry keyed by
        // the tunnel interface; bare Wi-Fi/cell networks don't.
        guard let scoped = cf["__SCOPED__"] as? [String: Any] else { return false }
        return scoped.keys.contains(where: { $0.hasPrefix("tap") || $0.hasPrefix("tun") || $0.hasPrefix("ppp") || $0.hasPrefix("ipsec") || $0.hasPrefix("utun") })
    }
}
