import Foundation
import Combine
import Darwin
#if canImport(UIKit)
import UIKit
#endif

/// Live state of the "ISP → Router → Your Device" topology diagram shown at
/// the top of the Speed tab.
///
/// Before this monitor existed, the topology card was a static graphic —
/// the ISP always said "Available", the router always said "192.168.0.1",
/// and the device always said "Connected". It didn't actually reflect the
/// state of the network. Users rightly noticed it looked like a logo, not
/// a diagnostic.
///
/// Now every node and hop is driven by real measurements:
///
/// - `localIP` comes from `en0` via `getifaddrs` (or the active cellular
///   interface as a fallback).
/// - `gatewayIP` is inferred from the local IP (e.g. `192.168.1.42` →
///   `192.168.1.1`). This matches what the router almost always is in
///   consumer home networks and is consistent with the inference already
///   used by `NetworkScanner`.
/// - `gatewayLatencyMs` is a live TCP ping to the gateway (port 80,
///   then 443 as a fallback) — the two most commonly-open ports on a
///   router admin interface.
/// - `ispLatencyMs` is a live TCP ping to `8.8.8.8:53` — exactly the
///   probe already used elsewhere in the app, so results line up with
///   the Signal tab's latency readings.
///
/// The monitor refreshes every `refreshInterval` seconds, and also on
/// demand when the `NetworkInterfaceMonitor` status changes (so
/// flipping from Wi-Fi to cellular, or going offline, updates the
/// diagram within a tick rather than after a whole refresh cycle).
@MainActor
final class NetworkTopologyMonitor: ObservableObject {

    // MARK: - Published state

    /// Local device IPv4 (e.g. `192.168.1.42`). `nil` when offline or on
    /// an interface we can't resolve via `getifaddrs` (rare outside the
    /// simulator).
    @Published private(set) var localIP: String?

    /// Inferred gateway IPv4 (e.g. `192.168.1.1`). `nil` when we don't
    /// have a local IP to infer from, or when the current connection is
    /// cellular (no LAN gateway in the traditional sense).
    @Published private(set) var gatewayIP: String?

    /// Latest measured TCP RTT to the gateway, in ms. `nil` means either
    /// the gateway isn't reachable, we're not on Wi-Fi, or we haven't
    /// measured yet.
    @Published private(set) var gatewayLatencyMs: Double?

    /// Latest measured TCP RTT to `8.8.8.8:53`, in ms. `nil` means the
    /// internet isn't reachable or we haven't measured yet.
    @Published private(set) var ispLatencyMs: Double?

    /// Timestamp of the last completed refresh pass. Used by the UI so a
    /// stale reading doesn't keep showing green forever if the refresh
    /// loop breaks.
    @Published private(set) var lastUpdated: Date?

    /// `true` while a refresh pass is currently in flight — lets the UI
    /// animate a subtle "pulse" on the connectors instead of just
    /// showing a frozen value.
    @Published private(set) var isRefreshing: Bool = false

    // MARK: - Derived UI state
    //
    // Kept here (rather than in the view) so any view that wants to show
    // the same health signal gets the same classification. A latency
    // band maps directly to a traffic-light color.

    enum LinkHealth {
        case good       // Link is working and fast enough to not notice.
        case fair       // Link is working but sluggish; streaming may stutter.
        case poor       // Link is working but painful; calls will break up.
        case offline    // Link failed entirely this pass.
        case unknown    // Not measured yet (first load).

        /// True when the link carried data this refresh pass, regardless
        /// of how fast. Used to decide whether to animate the connector.
        var isCarryingTraffic: Bool {
            switch self {
            case .good, .fair, .poor: return true
            case .offline, .unknown: return false
            }
        }
    }

    /// Health of the WAN hop — router out to the public internet. Based
    /// on ISP latency (since we can't measure the router→ISP leg in
    /// isolation without root access).
    var wanHealth: LinkHealth {
        classify(latency: ispLatencyMs, reachable: ispLatencyMs != nil)
    }

    /// Health of the LAN hop — device to router. Based on gateway RTT.
    /// When the device is on cellular we return `.unknown` rather than
    /// `.offline` because there simply isn't a local Wi-Fi router to
    /// ping; showing red would be misleading.
    var lanHealth: LinkHealth {
        switch interfaceStatus {
        case .cellular, .offline: return .unknown
        default: break
        }
        return classify(latency: gatewayLatencyMs, reachable: gatewayLatencyMs != nil)
    }

    /// Friendly label for the local device node in the topology card
    /// (e.g. "Your iPhone", "Your iPad"). Defaults to "Your Device" so
    /// the UI never reads as a placeholder.
    let deviceLabel: String = {
        #if canImport(UIKit)
        let model = UIDevice.current.localizedModel // "iPhone" / "iPad" / ...
        if model.isEmpty { return "Your Device" }
        return "Your \(model)"
        #else
        return "Your Device"
        #endif
    }()

    // MARK: - Private state

    private let probe = LatencyProbe()
    private let refreshInterval: TimeInterval
    private var refreshTask: Task<Void, Never>?
    private var interfaceObservation: AnyCancellable?
    private var interfaceStatus: NetworkInterfaceMonitor.Status = .unknown

    // MARK: - Lifecycle

    init(refreshInterval: TimeInterval = 6) {
        self.refreshInterval = refreshInterval
    }

    /// Starts the periodic refresh loop and subscribes to interface
    /// changes. Idempotent — safe to call in `onAppear`.
    func start() {
        guard refreshTask == nil else { return }

        interfaceObservation = NetworkInterfaceMonitor.shared.$status
            .removeDuplicates()
            .sink { [weak self] status in
                Task { @MainActor in
                    self?.handleInterfaceChange(status)
                }
            }

        interfaceStatus = NetworkInterfaceMonitor.shared.status

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // Sleep is tolerant of cancellation; catching the
                // cancellation error is the normal stop path.
                try? await Task.sleep(nanoseconds: UInt64((self?.refreshInterval ?? 6) * 1_000_000_000))
            }
        }
    }

    /// Stops the refresh loop and releases the interface subscription.
    /// Call from `onDisappear` so backgrounded tabs don't keep probing
    /// the network every few seconds.
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        interfaceObservation?.cancel()
        interfaceObservation = nil
    }

    deinit {
        refreshTask?.cancel()
        interfaceObservation?.cancel()
    }

    // MARK: - Refresh

    /// One full refresh pass: re-read the local IP, re-infer the
    /// gateway, then probe both the gateway and the public internet in
    /// parallel.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let (ip, _) = Self.readLocalIPAndMask()
        localIP = ip
        gatewayIP = ip.flatMap { Self.inferGatewayIP(from: $0) }

        // Only probe the gateway when we're actually on a LAN
        // (Wi-Fi / wired). On cellular there's no meaningful
        // "gateway ping" to show the user.
        let probeGateway = (interfaceStatus == .wifi || interfaceStatus == .wired)
            && gatewayIP != nil

        async let ispTask: Double? = probeHost(host: "8.8.8.8", port: 53)
        async let gwTask: Double? = probeGateway
            ? probeGatewayLatency(ip: gatewayIP!)
            : nil

        let isp = await ispTask
        let gw = await gwTask

        ispLatencyMs = isp
        gatewayLatencyMs = gw
        lastUpdated = Date()

        // Publish to Klaus's live-context hub so the chat assistant
        // can read the current topology without re-probing the network
        // itself. Runs on every refresh because the data is cheap to
        // copy and the chat is the only consumer.
        KlausContextHub.shared.update { ctx in
            ctx.localIP = self.localIP
            ctx.gatewayIP = self.gatewayIP
            ctx.gatewayLatencyMs = self.gatewayLatencyMs
            ctx.ispLatencyMs = self.ispLatencyMs
            ctx.topologyUpdatedAt = self.lastUpdated
        }
    }

    // MARK: - Probing

    /// Thin async wrapper around `LatencyProbe` so the call site can use
    /// `async let`. Returns `nil` on timeout / connection failure.
    private func probeHost(host: String, port: UInt16, timeout: TimeInterval = 1.0) async -> Double? {
        await withCheckedContinuation { continuation in
            probe.measureLatency(host: host, port: port, timeout: timeout) { value in
                continuation.resume(returning: value)
            }
        }
    }

    /// Probes the gateway twice: once on port 80 (most common on
    /// consumer routers) and, if that fails, once on 443. Some routers
    /// redirect or close 80; trying both keeps the green indicator
    /// honest on more networks.
    private func probeGatewayLatency(ip: String) async -> Double? {
        if let ms = await probeHost(host: ip, port: 80, timeout: 0.8) {
            return ms
        }
        return await probeHost(host: ip, port: 443, timeout: 0.8)
    }

    // MARK: - Helpers

    private func handleInterfaceChange(_ status: NetworkInterfaceMonitor.Status) {
        interfaceStatus = status
        // Immediately invalidate stale gateway data when the interface
        // changes — otherwise the card would keep showing the previous
        // Wi-Fi gateway for `refreshInterval` seconds after going
        // cellular.
        if status == .cellular || status == .offline {
            gatewayLatencyMs = nil
        }
        Task { await refresh() }
    }

    private func classify(latency: Double?, reachable: Bool) -> LinkHealth {
        guard reachable, let ms = latency else { return .offline }
        if ms < 50 { return .good }
        if ms < 150 { return .fair }
        return .poor
    }

    // MARK: - Network utilities

    /// Reads the IPv4 address + subnet mask of the active network
    /// interface. Prefers `en0` (Wi-Fi on iOS) and falls back to the
    /// first non-loopback IPv4 interface so cellular-connected devices
    /// still see an IP in the topology card.
    private static func readLocalIPAndMask() -> (ip: String?, mask: String?) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (nil, nil) }
        defer { freeifaddrs(ifaddr) }

        var preferredIP: String?
        var preferredMask: String?
        var fallbackIP: String?
        var fallbackMask: String?

        var ptr = first
        while true {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // Loopback interfaces aren't useful in a topology card.
                if name != "lo0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    let ip = String(cString: hostname)

                    var mask: String?
                    if let maskAddr = interface.ifa_netmask {
                        var maskHostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(
                            maskAddr,
                            socklen_t(maskAddr.pointee.sa_len),
                            &maskHostname,
                            socklen_t(maskHostname.count),
                            nil,
                            0,
                            NI_NUMERICHOST
                        )
                        mask = String(cString: maskHostname)
                    }

                    if name == "en0" {
                        preferredIP = ip
                        preferredMask = mask
                    } else if fallbackIP == nil {
                        fallbackIP = ip
                        fallbackMask = mask
                    }
                }
            }
            guard let next = interface.ifa_next else { break }
            ptr = next
        }

        return (preferredIP ?? fallbackIP, preferredMask ?? fallbackMask)
    }

    /// Replaces the last octet of the local IP with `.1` — the
    /// overwhelming-majority convention for home routers. This matches
    /// `NetworkScanner.inferGatewayIP` so the dashboard and the device
    /// scanner agree on which IP is the router.
    private static func inferGatewayIP(from localIP: String) -> String? {
        let parts = localIP.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2]).1"
    }
}
