import Foundation
import Network
import Combine

/// Publishes the current network interface (Wi-Fi, cellular, wired, or none)
/// so UI surfaces can adapt their copy and behavior.
///
/// Most of this app — device discovery, latency/ping, speed tests — only
/// makes sense over Wi-Fi. Before adding this monitor, kicking off a
/// network scan while on cellular looked like a silent no-op (the
/// `en0` interface has no IPv4 address when Wi-Fi is off, so the scanner
/// would just report "Could not determine local network" to itself and
/// stop). Users had no idea their cellular connection was the reason.
/// With this monitor in place, every affected tab can show a clear
/// "you're on cellular" message instead.
///
/// Uses a single long-lived `NWPathMonitor`; callers observe the
/// published `status` on the main actor.
@MainActor
final class NetworkInterfaceMonitor: ObservableObject {
    /// Shared instance so multiple views can observe the same monitor
    /// without each spinning up their own `NWPathMonitor`.
    static let shared = NetworkInterfaceMonitor()

    enum Status: Equatable {
        case wifi
        case cellular
        case wired
        case offline
        case unknown

        /// True only when the active path is Wi-Fi. Every feature that
        /// talks to the local network (device discovery, LAN latency,
        /// gateway probes) should gate on this.
        var isWiFi: Bool { self == .wifi }

        /// True when there is any usable connection — useful for tests
        /// that still run over cellular but should be labeled as such.
        var isOnline: Bool {
            switch self {
            case .wifi, .cellular, .wired: return true
            case .offline, .unknown: return false
            }
        }

        /// Short label suitable for inline badges ("Cellular", "Wi-Fi").
        var shortLabel: String {
            switch self {
            case .wifi: return "Wi-Fi"
            case .cellular: return "Cellular"
            case .wired: return "Wired"
            case .offline: return "Offline"
            case .unknown: return "Unknown"
            }
        }
    }

    @Published private(set) var status: Status = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "network.interface.monitor", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let next = Self.classify(path)
            Task { @MainActor in
                if self.status != next {
                    self.status = next
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    /// Maps an `NWPath` to our simplified `Status`. Called on the
    /// monitor's background queue, so it must be `nonisolated` even
    /// though the enclosing class is `@MainActor`. We intentionally treat
    /// a path without a usable interface as `.offline` rather than trying
    /// to interpret `.requiresConnection`, because UX-wise "no internet"
    /// and "waiting to connect" should look the same to the user.
    private nonisolated static func classify(_ path: NWPath) -> Status {
        guard path.status == .satisfied else { return .offline }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        if path.usesInterfaceType(.cellular) { return .cellular }
        return .unknown
    }
}
