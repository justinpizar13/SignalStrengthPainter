import Foundation
import Network
import Darwin

/// Tiny `@Sendable`-safe one-shot latch. `setIfUnset()` returns `true` the
/// first time it is called from any thread and `false` on every subsequent
/// call. Used by the TCP-probe completion guards below to replace the
/// `var hasResumed = false` + `NSLock` pattern, which Swift 6's
/// strict-concurrency checker rejects when the enclosing `finish` helper is
/// marked `@Sendable` (mutable local `var`s cannot be captured by `@Sendable`
/// closures). `@unchecked Sendable` is safe here because the only mutable
/// state is guarded by the lock.
private final class AtomicBool: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func setIfUnset() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !value else { return false }
        value = true
        return true
    }
}

struct DiscoveredDevice: Identifiable {
    let id: String
    let ipAddress: String
    var hostname: String?
    var bonjourName: String?
    var services: [String]
    var deviceType: DeviceType
    var openPorts: [UInt16]
    var latencyMs: Double?
    var manufacturer: String?
    /// Colon-separated lowercase MAC (e.g. "3c:22:fb:1a:2b:3c") from the
    /// kernel ARP table. Optional because some IPs may not have an ARP
    /// entry by the time we read the table.
    var macAddress: String?
    /// Manufacturer resolved from the MAC's OUI (e.g. "Apple", "Amazon").
    /// May differ from `manufacturer` when HTTP fingerprinting produced a
    /// more specific brand (e.g., "Sonos" model information).
    var ouiVendor: String?
    /// `true` when the MAC has the locally-administered bit set, meaning
    /// the OS is using a randomized (privacy) MAC address. iOS 14+,
    /// Android 10+, Windows 10+, and macOS 12+ default to randomized MACs
    /// per network, so we can't look up the real manufacturer.
    var hasRandomizedMAC: Bool
    let firstSeen: Date
    var isCurrentDevice: Bool
    var isTrusted: Bool
    /// User-assigned nickname persisted in `UserDefaults`. When set, this
    /// takes priority over every auto-detected label (Bonjour name,
    /// hostname, vendor, device type) in both the list row and the detail
    /// sheet. Lets users keep track of devices that otherwise show up with
    /// no hostname/DNS — e.g., "Kitchen Roku", "Kid's iPad".
    var customName: String?

    var displayHostname: String? {
        if let name = bonjourName, !name.isEmpty { return name }
        if let h = hostname, !h.isEmpty, h != ipAddress { return Self.cleanHostname(h) }
        return nil
    }

    static func cleanHostname(_ raw: String) -> String {
        var name = raw
        for suffix in [".local", ".home", ".lan", ".internal", ".localdomain", ".fritz.box", ".gateway", ".attlocal.net"] {
            if name.lowercased().hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
                break
            }
        }
        return name
    }

    var portHint: String? {
        if openPorts.isEmpty { return nil }
        var hints: [String] = []
        if openPorts.contains(62078) { hints.append("Apple Sync") }
        if openPorts.contains(548) { hints.append("AFP") }
        if openPorts.contains(445) || openPorts.contains(139) { hints.append("SMB") }
        if openPorts.contains(7000) { hints.append("AirPlay") }
        if openPorts.contains(9100) || openPorts.contains(631) || openPorts.contains(515) { hints.append("Printing") }
        if openPorts.contains(554) { hints.append("RTSP") }
        if openPorts.contains(8008) || openPorts.contains(8443) { hints.append("Cast") }
        if openPorts.contains(1883) { hints.append("MQTT") }
        if openPorts.contains(3689) { hints.append("Media") }
        if openPorts.contains(22) { hints.append("SSH") }
        if openPorts.contains(5353) { hints.append("mDNS") }
        if hints.isEmpty {
            let webPorts = openPorts.filter { [80, 443, 8080, 8888, 3000, 5000].contains($0) }
            if !webPorts.isEmpty { hints.append("Web") }
        }
        return hints.isEmpty ? nil : hints.joined(separator: ", ")
    }

    enum DeviceType: String {
        case router = "Router / Gateway"
        case phone = "Phone / Tablet"
        case computer = "Computer"
        case smartTV = "Smart TV / Media"
        case printer = "Printer"
        case speaker = "Smart Speaker"
        case iotDevice = "IoT / Smart Home"
        case gameConsole = "Game Console"
        case unknown = "Unknown Device"

        var icon: String {
            switch self {
            case .router: return "wifi.router"
            case .phone: return "iphone"
            case .computer: return "laptopcomputer"
            case .smartTV: return "tv"
            case .printer: return "printer.fill"
            case .speaker: return "hifispeaker.fill"
            case .iotDevice: return "sensor.fill"
            case .gameConsole: return "gamecontroller.fill"
            case .unknown: return "desktopcomputer"
            }
        }

        var color: Color {
            switch self {
            case .router: return .blue
            case .phone: return Color(red: 0.25, green: 0.86, blue: 0.43)
            case .computer: return .cyan
            case .smartTV: return .purple
            case .printer: return .orange
            case .speaker: return .pink
            case .iotDevice: return Color(red: 0.98, green: 0.78, blue: 0.28)
            case .gameConsole: return .red
            case .unknown: return .gray
            }
        }

        var shortName: String {
            switch self {
            case .router: return "Router"
            case .phone: return "Phone"
            case .computer: return "Computer"
            case .smartTV: return "Media Player"
            case .printer: return "Printer"
            case .speaker: return "Speaker"
            case .iotDevice: return "Device"
            case .gameConsole: return "Console"
            case .unknown: return "Device"
            }
        }
    }
}

import SwiftUI

@MainActor
final class NetworkScanner: ObservableObject {
    @Published var devices: [DiscoveredDevice] = []
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var localIP: String = "—"
    @Published var subnetMask: String = "—"
    @Published var scanStatusMessage: String = "Ready to scan"

    private var scanTask: Task<Void, Never>?
    private let probeQueue = DispatchQueue(label: "network.scanner.probe", attributes: .concurrent)

    private var discoveredIPs: Set<String> = []

    /// Bonjour results keyed by resolved IP → array of (name, service)
    private var bonjourByIP: [String: [(name: String, service: String)]] = [:]

    /// Bonjour hostnames (e.g., "Justins-Mac-mini.local") keyed by resolved IP
    private var bonjourHostByIP: [String: String] = [:]

    /// Long-lived Bonjour browsers kept alive for the full scan duration so
    /// late-arriving services (and services that appear after the iOS Local
    /// Network permission prompt is accepted) are still picked up.
    private var activeBonjourBrowsers: [NWBrowser] = []

    /// Deduplicated Bonjour results collected over the full scan window.
    /// Held by a reference-typed nonisolated collector so that NWBrowser
    /// callbacks (which fire on a background queue) can write into it
    /// without tripping main-actor isolation.
    private let bonjourCollector = BonjourCollector()

    /// SSDP/UPnP results keyed by IP → HTTP headers from M-SEARCH response
    private var ssdpByIP: [String: [String: String]] = [:]

    /// UPnP device descriptions fetched from SSDP LOCATION URLs
    private var upnpDescriptions: [String: (friendlyName: String, manufacturer: String?, modelName: String?)] = [:]

    /// Gateway IP for the most recent scan. Captured at scan start and
    /// used together with the ARP table at scan end to derive a stable
    /// per-network fingerprint (see `currentNetworkID`).
    private var currentGatewayIP: String?

    /// Stable fingerprint for the network the last completed scan was run
    /// on. Derived from the gateway's hardware (MAC) address, which is
    /// unique per router and — unlike client devices — is never privacy
    /// randomized on the LAN-facing interface. All persisted trust flags
    /// and custom device names are scoped to this ID so that moving to
    /// another Wi-Fi network that reuses the same IP schema (e.g., every
    /// home router defaults to `192.168.1.x`) never causes a stranger's
    /// device at `192.168.1.10` to be treated as your own trusted gear.
    /// Nil when we haven't finished a scan yet, or when the ARP table
    /// didn't contain a usable gateway MAC (rare).
    @Published private(set) var currentNetworkID: String?

    /// New, network-scoped storage. Key structure:
    ///   trustedDevicesByNetwork : [networkID: [trustedIP]]
    ///   customDeviceNamesByNetwork : [networkID: [ip: nickname]]
    private static let trustedByNetworkKey = "trustedDevicesByNetwork"
    private static let customNamesByNetworkKey = "customDeviceNamesByNetwork"

    /// One-shot flag: set the first time we successfully migrate the
    /// legacy flat (IP-only) trust/name storage into the new
    /// network-scoped storage.
    private static let trustMigrationKey = "trustMigrationCompleted_v2"

    /// Persisted baseline of non-randomized MAC addresses seen per
    /// network, keyed by `currentNetworkID`. When a scan on a trusted
    /// network turns up a MAC we've never seen before, we post a local
    /// notification — this is the single most re-engaging feature in a
    /// Wi-Fi utility. Storage shape: `[networkID: [mac]]`.
    private static let seenMACsByNetworkKey = "seenMACsByNetwork"

    /// Legacy UserDefaults keys from before trust/names were scoped to a
    /// network. Read once during migration, then deleted.
    private static let legacyTrustedKey = "trustedDeviceIPs"
    private static let legacyCustomNamesKey = "customDeviceNames"

    /// Maximum characters allowed in a user-assigned device nickname.
    /// Keeps UI rows from overflowing and bounds the stored data.
    private static let customNameMaxLength = 40

    private static let probePorts: [UInt16] = [
        80, 443, 62078, 548, 445, 7000, 8080,
        9100, 631, 554, 8008, 8443, 1883, 3689,
        22, 139, 5353, 8888, 5000, 515, 3000
    ]

    /// Full persisted trust map: networkID → array of trusted IPs on that
    /// network. Read lazily so we stay consistent across launches.
    private var trustedByNetwork: [String: [String]] {
        UserDefaults.standard.dictionary(forKey: Self.trustedByNetworkKey) as? [String: [String]] ?? [:]
    }

    /// Full persisted custom-name map: networkID → (IP → nickname).
    private var customNamesByNetwork: [String: [String: String]] {
        UserDefaults.standard.dictionary(forKey: Self.customNamesByNetworkKey) as? [String: [String: String]] ?? [:]
    }

    /// Trust flags persisted for the supplied network.
    private func trustedIPs(for networkID: String) -> Set<String> {
        Set(trustedByNetwork[networkID] ?? [])
    }

    /// Custom nicknames persisted for the supplied network.
    private func customNames(for networkID: String) -> [String: String] {
        customNamesByNetwork[networkID] ?? [:]
    }

    /// Marks (or un-marks) a device as trusted for the current network.
    /// No-op until a scan has resolved the gateway MAC and set
    /// `currentNetworkID`, so we never write trust data to an unknown or
    /// ambiguous network.
    func setTrusted(_ ip: String, trusted: Bool) {
        guard let networkID = currentNetworkID else { return }
        var byNetwork = trustedByNetwork
        var current = Set(byNetwork[networkID] ?? [])
        if trusted { current.insert(ip) } else { current.remove(ip) }
        if current.isEmpty {
            byNetwork.removeValue(forKey: networkID)
        } else {
            byNetwork[networkID] = Array(current)
        }
        UserDefaults.standard.set(byNetwork, forKey: Self.trustedByNetworkKey)

        if let idx = devices.firstIndex(where: { $0.ipAddress == ip }) {
            devices[idx].isTrusted = trusted
            // If the user un-trusts a device, drop their custom name too so
            // a device they no longer recognize stops carrying a nickname
            // that implies they know it.
            if !trusted {
                devices[idx].customName = nil
                removeStoredCustomName(for: ip, in: networkID)
            }
        }
        objectWillChange.send()
    }

    /// Assigns (or clears) a custom nickname for a device on the current
    /// network. The name is sanitized: trimmed of whitespace/control
    /// characters and capped to `customNameMaxLength`. Passing `nil` or
    /// an empty string removes the stored nickname. Only allowed for
    /// trusted devices — renaming an unknown host would give the user a
    /// false sense of recognition.
    func setCustomName(_ ip: String, name: String?) {
        guard let networkID = currentNetworkID else { return }
        guard let idx = devices.firstIndex(where: { $0.ipAddress == ip }) else { return }
        guard devices[idx].isTrusted else { return }

        let sanitized = Self.sanitizeCustomName(name)
        if let sanitized {
            var byNetwork = customNamesByNetwork
            var current = byNetwork[networkID] ?? [:]
            current[ip] = sanitized
            byNetwork[networkID] = current
            UserDefaults.standard.set(byNetwork, forKey: Self.customNamesByNetworkKey)
            devices[idx].customName = sanitized
        } else {
            removeStoredCustomName(for: ip, in: networkID)
            devices[idx].customName = nil
        }
        objectWillChange.send()
    }

    private func removeStoredCustomName(for ip: String, in networkID: String) {
        var byNetwork = customNamesByNetwork
        guard var current = byNetwork[networkID] else { return }
        if current.removeValue(forKey: ip) != nil {
            if current.isEmpty {
                byNetwork.removeValue(forKey: networkID)
            } else {
                byNetwork[networkID] = current
            }
            UserDefaults.standard.set(byNetwork, forKey: Self.customNamesByNetworkKey)
        }
    }

    /// Derives a stable per-network fingerprint from the gateway's MAC
    /// address. Returns `nil` when the ARP table doesn't yet contain an
    /// entry for the gateway, or when the gateway somehow reports a
    /// locally-administered (randomized) MAC — both are rare on home
    /// routers but we refuse to key trust data on something unstable.
    private func computeNetworkID(gatewayIP: String, arpTable: [String: String]) -> String? {
        guard let mac = arpTable[gatewayIP], !mac.isEmpty else { return nil }
        let normalized = mac.lowercased()
        guard !MACAddressResolver.isLocallyAdministered(normalized) else { return nil }
        return "gw:\(normalized)"
    }

    /// One-shot migration from the pre-upgrade, IP-only trust/name store
    /// to the new network-scoped store. We only carry legacy data
    /// forward when we have strong evidence the current scan is running
    /// on the same network the data was created on — specifically, when
    /// at least half of the previously-trusted IPs are currently present
    /// in `devices`. Otherwise we drop the legacy entries: untrusting
    /// everything is a far better failure mode than silently re-trusting
    /// strangers' hardware on a new network that reuses the same IP
    /// schema. Always clears the legacy keys so migration is a one-shot.
    private func migrateLegacyTrustIfNeeded(into networkID: String) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.trustMigrationKey) else { return }
        let legacyTrustedList = defaults.stringArray(forKey: Self.legacyTrustedKey) ?? []
        let legacyNames = defaults.dictionary(forKey: Self.legacyCustomNamesKey) as? [String: String] ?? [:]
        let legacyTrustedSet = Set(legacyTrustedList)

        let currentIPs = Set(devices.map(\.ipAddress))
        let overlap = legacyTrustedSet.intersection(currentIPs).count
        let shouldMigrate = !legacyTrustedSet.isEmpty && overlap * 2 >= legacyTrustedSet.count

        if shouldMigrate {
            var byNetTrust = trustedByNetwork
            var existing = Set(byNetTrust[networkID] ?? [])
            existing.formUnion(legacyTrustedSet)
            byNetTrust[networkID] = Array(existing)
            defaults.set(byNetTrust, forKey: Self.trustedByNetworkKey)

            if !legacyNames.isEmpty {
                var byNetNames = customNamesByNetwork
                var names = byNetNames[networkID] ?? [:]
                names.merge(legacyNames, uniquingKeysWith: { _, new in new })
                byNetNames[networkID] = names
                defaults.set(byNetNames, forKey: Self.customNamesByNetworkKey)
            }
        }

        defaults.removeObject(forKey: Self.legacyTrustedKey)
        defaults.removeObject(forKey: Self.legacyCustomNamesKey)
        defaults.set(true, forKey: Self.trustMigrationKey)
    }

    /// Applies the stored trust flags and custom nicknames for the
    /// current network to every discovered device. Deferred until the
    /// ARP table is populated so we know which network we're actually on
    /// — before that point we cannot distinguish e.g. "my home router"
    /// from "a coffee shop router that also uses 192.168.1.1".
    private func applyTrustAndCustomNames(arpTable: [String: String], gatewayIP: String) {
        let networkID = computeNetworkID(gatewayIP: gatewayIP, arpTable: arpTable)
        currentNetworkID = networkID

        guard let networkID else {
            // Without a stable network ID we cannot safely apply any
            // persisted trust state. Leave every device as untrusted so
            // the user cannot accidentally act on cross-network data.
            for i in devices.indices {
                devices[i].isTrusted = false
                devices[i].customName = nil
            }
            return
        }

        migrateLegacyTrustIfNeeded(into: networkID)

        let trusted = trustedIPs(for: networkID)
        let names = customNames(for: networkID)
        for i in devices.indices {
            let ip = devices[i].ipAddress
            let isTrusted = trusted.contains(ip)
            devices[i].isTrusted = isTrusted
            devices[i].customName = isTrusted ? names[ip] : nil
        }

        // Once trust state is known, diff the MAC list against the
        // per-network baseline to detect newcomers. Must happen after
        // trust is applied so we can skip notifications on untrusted
        // networks (coffee shops, airports, etc.).
        detectNewDeviceArrivals(networkID: networkID)
    }

    /// Persisted per-network baseline of MACs we've already seen.
    private var seenMACsByNetwork: [String: [String]] {
        UserDefaults.standard.dictionary(forKey: Self.seenMACsByNetworkKey) as? [String: [String]] ?? [:]
    }

    /// Compares the current scan's non-randomized MACs against the
    /// persisted baseline for `networkID` and fires a local notification
    /// for each newcomer. Skipped entirely on first scan of a network
    /// (otherwise every device would "alert") and on networks where
    /// the user hasn't trusted anything (not *their* network, don't
    /// spam).
    ///
    /// Randomized MACs are ignored — they churn by design and would
    /// produce a constant stream of false positives.
    private func detectNewDeviceArrivals(networkID: String) {
        let trusted = trustedIPs(for: networkID)
        var baseline = seenMACsByNetwork

        guard !trusted.isEmpty else {
            // Not a known-trusted network — drop any stale baseline
            // we might have so a later trust designation gets a clean
            // "first scan" pass.
            if baseline.removeValue(forKey: networkID) != nil {
                UserDefaults.standard.set(baseline, forKey: Self.seenMACsByNetworkKey)
            }
            return
        }

        let hasPriorBaseline = baseline[networkID] != nil
        let previouslySeen = Set(baseline[networkID] ?? [])

        var observed: Set<String> = []
        var newDevices: [DiscoveredDevice] = []
        for device in devices {
            guard let mac = device.macAddress, !mac.isEmpty else { continue }
            guard !device.hasRandomizedMAC else { continue }
            guard !device.isCurrentDevice else { continue }
            let normalized = mac.lowercased()
            observed.insert(normalized)
            if hasPriorBaseline, !previouslySeen.contains(normalized) {
                newDevices.append(device)
            }
        }

        // Union — keep devices that happened to be offline during this
        // scan in the baseline so they don't re-trigger later.
        let updated = previouslySeen.union(observed)
        baseline[networkID] = Array(updated)
        UserDefaults.standard.set(baseline, forKey: Self.seenMACsByNetworkKey)

        if hasPriorBaseline, !newDevices.isEmpty {
            NewDeviceAlertNotifier.shared.postNewDeviceAlerts(newDevices)
        }
    }

    /// Allow-list style sanitization: strip control characters and newlines,
    /// collapse whitespace, trim, and cap length. Returns `nil` when the
    /// result is empty so callers can treat "clear the name" as a single
    /// code path.
    private static func sanitizeCustomName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let stripped = raw.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) &&
            !CharacterSet.newlines.contains(scalar)
        }
        var cleaned = String(String.UnicodeScalarView(stripped))
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { return nil }
        if cleaned.count > customNameMaxLength {
            cleaned = String(cleaned.prefix(customNameMaxLength))
                .trimmingCharacters(in: .whitespaces)
        }
        return cleaned.isEmpty ? nil : cleaned
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0
        devices = []
        discoveredIPs = []
        bonjourByIP = [:]
        bonjourHostByIP = [:]
        ssdpByIP = [:]
        upnpDescriptions = [:]
        bonjourCollector.reset()
        stopBonjourBrowsers()
        // Clear any stale network fingerprint from a previous scan. We'll
        // recompute it at the end of this scan once the ARP table is
        // populated — until then, every newly-built device is treated as
        // untrusted (see `applyTrustAndCustomNames`).
        currentNetworkID = nil
        currentGatewayIP = nil
        scanStatusMessage = "Discovering local network..."

        let (ip, mask) = getLocalIPAndMask()
        localIP = ip ?? "Unknown"
        subnetMask = mask ?? "Unknown"

        scanTask = Task {
            guard let ip, let mask else {
                scanStatusMessage = "Could not determine local network"
                isScanning = false
                return
            }

            // Start long-lived Bonjour browsers now and keep them running for
            // the full scan. Results accumulate in `bonjourCollected` until we
            // resolve them near the end. This fixes two problems:
            //   1. iOS's Local Network permission prompt can eat the first few
            //      seconds of Bonjour discovery on the first scan of a session.
            //   2. Some services announce themselves only after a short delay.
            startBonjourBrowsers()

            scanStatusMessage = "Discovering SSDP/UPnP devices..."
            await discoverSSDPDevices()

            if !ssdpByIP.isEmpty {
                scanStatusMessage = "Fetching device details..."
                await fetchUPnPDescriptions()
            }

            let subnet = calculateSubnetRange(ip: ip, mask: mask)
            let gatewayIP = inferGatewayIP(localIP: ip)
            currentGatewayIP = gatewayIP
            let totalHosts = subnet.count
            var scannedCount = 0

            scanStatusMessage = "Scanning \(totalHosts) addresses..."

            // Smaller batches keep simultaneous NWConnections under iOS's
            // silent connection cap. 10 hosts × 21 ports = 210 parallel probes
            // per batch instead of 420, which avoids dropped SYN packets.
            let batchSize = 10
            for batchStart in stride(from: 0, to: totalHosts, by: batchSize) {
                if Task.isCancelled { break }

                let batchEnd = min(batchStart + batchSize, totalHosts)
                let batch = Array(subnet[batchStart..<batchEnd])

                await withTaskGroup(of: (String, Double, [UInt16])?.self) { group in
                    for targetIP in batch {
                        group.addTask { [weak self] in
                            guard let self else { return nil }
                            guard let result = await self.probeHost(targetIP) else { return nil }
                            return (targetIP, result.latency, result.ports)
                        }
                    }

                    for await result in group {
                        if let (foundIP, latency, ports) = result {
                            if !discoveredIPs.contains(foundIP) {
                                discoveredIPs.insert(foundIP)
                                let isGateway = foundIP == gatewayIP
                                let isSelf = foundIP == ip
                                let bonjourInfo = bonjourByIP[foundIP]
                                let ssdpInfo = ssdpByIP[foundIP]
                                let deviceType = classifyDevice(
                                    ip: foundIP,
                                    isGateway: isGateway,
                                    isSelf: isSelf,
                                    bonjourEntries: bonjourInfo,
                                    openPorts: ports,
                                    ssdpHeaders: ssdpInfo
                                )
                                let bonjourNames = bonjourInfo?.map(\.name)
                                let ssdpName = self.upnpDescriptions[foundIP]?.friendlyName
                                let bonjourServices = bonjourInfo?.map(\.service) ?? []
                                var allServices = Array(Set(bonjourServices))
                                if let ssdpInfo {
                                    let hint = self.ssdpServiceHint(ssdpInfo, ip: foundIP)
                                    if !allServices.contains(hint) { allServices.append(hint) }
                                }
                                // Trust flags and custom nicknames are applied
                                // at the end of the scan (see
                                // `applyTrustAndCustomNames`) once we have
                                // resolved the gateway MAC and can tell which
                                // network we're on.
                                let device = DiscoveredDevice(
                                    id: foundIP,
                                    ipAddress: foundIP,
                                    hostname: bonjourHostByIP[foundIP],
                                    bonjourName: bonjourNames?.first ?? ssdpName,
                                    services: allServices,
                                    deviceType: deviceType,
                                    openPorts: ports,
                                    latencyMs: latency,
                                    macAddress: nil,
                                    ouiVendor: nil,
                                    hasRandomizedMAC: false,
                                    firstSeen: Date(),
                                    isCurrentDevice: isSelf,
                                    isTrusted: false,
                                    customName: nil
                                )
                                devices.append(device)
                                sortDevices()
                            }
                        }
                    }
                }

                scannedCount += batch.count
                scanProgress = Double(scannedCount) / Double(totalHosts)
                scanStatusMessage = "Scanned \(scannedCount)/\(totalHosts) — Found \(devices.count) device\(devices.count == 1 ? "" : "s")"
            }

            scanStatusMessage = "Resolving discovered services..."
            stopBonjourBrowsers()
            await resolveCollectedBonjourServices()

            // Now that Bonjour has resolved, backfill names on already-listed devices.
            applyBonjourMetadataToExistingDevices()

            scanStatusMessage = "Adding discovered-only devices..."
            addBonjourOnlyDevices(localIP: ip, gatewayIP: gatewayIP)
            addSSDPOnlyDevices(localIP: ip, gatewayIP: gatewayIP)

            scanStatusMessage = "Resolving device names..."
            await resolveHostnames()

            scanStatusMessage = "Identifying devices..."
            await httpFingerprint()

            scanStatusMessage = "Reading hardware addresses..."
            resolveMACAddresses()

            isScanning = false
            scanStatusMessage = "Scan complete — \(devices.count) device\(devices.count == 1 ? "" : "s") found"
            publishScanResultsToKlaus()
        }
    }

    /// Push the latest scan tallies into `KlausContextHub` so Klaus can
    /// speak to "your last scan saw N devices, M trusted" without
    /// re-running the scan. Called once at the end of each scan pass.
    private func publishScanResultsToKlaus() {
        let total = devices.count
        let trusted = devices.filter { $0.isTrusted }.count
        let randomized = devices.filter { $0.hasRandomizedMAC }.count
        let unknown = max(0, total - trusted)
        KlausContextHub.shared.update { ctx in
            ctx.deviceCount = total
            ctx.trustedDeviceCount = trusted
            ctx.unknownDeviceCount = unknown
            ctx.randomizedMacCount = randomized
            ctx.lastScanAt = Date()
        }
    }

    // MARK: - MAC address / OUI vendor resolution (eighth identification layer)

    /// Reads the kernel ARP table via `MACAddressResolver` and annotates
    /// every discovered device with its MAC address, OUI-derived vendor
    /// name, and a flag indicating whether the MAC is a randomized privacy
    /// address. This is the single most useful identification signal for
    /// otherwise-opaque devices: even when Bonjour/SSDP/HTTP probes all
    /// fail, the MAC's first three bytes tell us who made the hardware
    /// (Apple, Amazon, Samsung, Sonos, Nintendo, Ring, Philips Hue, …).
    /// Without this layer the user has no way to tell whether a generic
    /// "Unknown Device" is their own phone or something malicious on
    /// their Wi-Fi.
    private func resolveMACAddresses() {
        let arpTable = MACAddressResolver.readARPTable()

        // Even if the ARP table is empty we still want to call
        // `applyTrustAndCustomNames` so stale trust flags from a
        // previous scan don't bleed into the UI. The apply helper
        // gracefully falls back to "no trust" when the gateway's MAC
        // isn't resolvable.
        // Apply persisted trust state after MAC resolution (or
        // attempted resolution) finishes. Sort order doesn't depend on
        // `isTrusted`/`customName`, so we don't need to re-sort here.
        defer {
            if let gatewayIP = currentGatewayIP {
                applyTrustAndCustomNames(arpTable: arpTable, gatewayIP: gatewayIP)
            }
        }

        guard !arpTable.isEmpty else { return }

        for i in devices.indices {
            let ip = devices[i].ipAddress
            guard let mac = arpTable[ip] else { continue }

            devices[i].macAddress = mac
            let isRandom = MACAddressResolver.isLocallyAdministered(mac)
            devices[i].hasRandomizedMAC = isRandom

            // Randomized MACs (iOS 14+, Android 10+ privacy feature) have
            // no meaningful OUI — looking one up would mislead the user.
            guard !isRandom else { continue }

            guard let vendor = OUIDatabase.manufacturer(forMAC: mac) else { continue }
            devices[i].ouiVendor = vendor

            // If HTTP fingerprinting didn't already set a (usually more
            // specific) manufacturer, promote the OUI vendor into the
            // manufacturer slot so the UI's "<Manufacturer> <ShortName>"
            // fallback produces a useful label.
            if devices[i].manufacturer == nil {
                devices[i].manufacturer = vendor
            }

            // Use the vendor to refine classification when prior layers
            // couldn't narrow the type. Be conservative: only override
            // `.unknown` and generic `.iotDevice` classifications, never
            // more-specific results produced by Bonjour / SSDP / ports.
            refineClassificationFromVendor(at: i, vendor: vendor)
        }

        sortDevices()
    }

    /// Refines `devices[i].deviceType` using the OUI vendor name, but only
    /// when the current classification is weak (`.unknown` / `.iotDevice`
    /// / `.smartTV`). We never override a strong, direct signal like
    /// "Chromecast" Bonjour or "Amazon Echo" UPnP friendlyName.
    private func refineClassificationFromVendor(at i: Int, vendor: String) {
        let current = devices[i].deviceType
        let v = vendor.lowercased()
        let ports = devices[i].openPorts

        // Strong signals we should never override.
        guard current == .unknown || current == .iotDevice else { return }

        if v.contains("apple") {
            // Mac computers expose SMB/AFP/SSH/RDP ports; iPhones/iPads
            // typically expose 62078 or nothing.
            if ports.contains(548) || ports.contains(445) || ports.contains(22) {
                devices[i].deviceType = .computer
            } else if ports.contains(62078) {
                devices[i].deviceType = .phone
            }
            return
        }
        if v.contains("amazon") {
            devices[i].deviceType = .speaker
            return
        }
        if v.contains("sonos") || v.contains("bose") {
            devices[i].deviceType = .speaker
            return
        }
        if v.contains("roku") || v.contains("vizio") {
            devices[i].deviceType = .smartTV
            return
        }
        if v.contains("nintendo") {
            devices[i].deviceType = .gameConsole
            return
        }
        if v.contains("hp") || v.contains("epson") || v.contains("canon") ||
           v.contains("brother") {
            // Only override if the device clearly looks like a printer
            // (common printer ports). HP makes both printers and PCs.
            if ports.contains(9100) || ports.contains(631) || ports.contains(515) {
                devices[i].deviceType = .printer
            }
            return
        }
        if v.contains("philips") || v.contains("ring") || v.contains("wyze") ||
           v.contains("eufy") || v.contains("anker") || v.contains("tuya") ||
           v.contains("espressif") || v.contains("tp-link") ||
           v.contains("belkin") {
            if current == .unknown {
                devices[i].deviceType = .iotDevice
            }
            return
        }
        if v.contains("dell") || v.contains("lenovo") || v.contains("asus") ||
           v.contains("intel") || v.contains("microsoft") ||
           v.contains("raspberry pi") {
            if current == .unknown {
                devices[i].deviceType = .computer
            }
            return
        }
        if v.contains("samsung") || v.contains("huawei") || v.contains("xiaomi") ||
           v.contains("oneplus") {
            // Samsung/Huawei make both phones and TVs. If port 7676
            // (Samsung Smart View) or 8080 is open, lean TV; otherwise phone.
            if current == .unknown {
                devices[i].deviceType = .phone
            }
            return
        }
        if v.contains("sony") {
            if ports.contains(9090) || ports.contains(7000) {
                devices[i].deviceType = .smartTV
            } else if current == .unknown {
                devices[i].deviceType = .gameConsole
            }
            return
        }
        if v.contains("nest") || v.contains("ecobee") {
            devices[i].deviceType = .iotDevice
            return
        }
    }

    func stopScan() {
        scanTask?.cancel()
        stopBonjourBrowsers()
        isScanning = false
        scanStatusMessage = devices.isEmpty ? "Scan stopped" : "Scan stopped — \(devices.count) device\(devices.count == 1 ? "" : "s") found"
    }

    private func sortDevices() {
        devices.sort { lhs, rhs in
            if lhs.isCurrentDevice { return true }
            if rhs.isCurrentDevice { return false }
            if lhs.deviceType == .router { return true }
            if rhs.deviceType == .router { return false }
            if lhs.deviceType != .unknown && rhs.deviceType == .unknown { return true }
            if lhs.deviceType == .unknown && rhs.deviceType != .unknown { return false }
            return lhs.ipAddress < rhs.ipAddress
        }
    }

    // MARK: - Bonjour Discovery (long-lived browsers + NetService resolution)

    private static let bonjourServiceTypes = [
        "_http._tcp", "_airplay._tcp", "_raop._tcp",
        "_smb._tcp", "_afpovertcp._tcp", "_ipp._tcp", "_printer._tcp",
        "_googlecast._tcp", "_spotify-connect._tcp",
        "_homekit._tcp", "_hap._tcp",
        "_device-info._tcp", "_companion-link._tcp",
        "_sleep-proxy._udp", "_rdlink._tcp", "_rfb._tcp",
        "_amzn-wplay._tcp",
        "_apple-mobdev2._tcp",
        "_touch-able._tcp"
    ]

    /// Starts NWBrowsers for every tracked service type and keeps them
    /// running until `stopBonjourBrowsers()` is called. Results are collected
    /// into `bonjourCollector` on a background queue.
    private func startBonjourBrowsers() {
        var browsers: [NWBrowser] = []
        let collector = bonjourCollector
        for serviceType in Self.bonjourServiceTypes {
            let params = NWParameters()
            params.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)

            browser.browseResultsChangedHandler = { browseResults, _ in
                for result in browseResults {
                    if case let .service(name, type, domain, _) = result.endpoint {
                        collector.insertIfMissing(
                            endpoint: result.endpoint,
                            name: name,
                            service: Self.friendlyServiceName(type),
                            type: type,
                            domain: domain
                        )
                    }
                }
            }

            browser.stateUpdateHandler = { _ in }
            browser.start(queue: DispatchQueue.global(qos: .userInitiated))
            browsers.append(browser)
        }
        activeBonjourBrowsers = browsers
    }

    private func stopBonjourBrowsers() {
        for browser in activeBonjourBrowsers {
            browser.cancel()
        }
        activeBonjourBrowsers.removeAll()
    }

    /// Resolves every Bonjour endpoint we've seen so far using Foundation's
    /// `NetService` API, which returns both the Bonjour hostname and one or
    /// more resolved IP addresses in a single delegate callback. This is far
    /// more reliable than the prior `NWConnection` approach, which dropped
    /// results whenever the advertised service port was firewalled.
    private func resolveCollectedBonjourServices() async {
        let snapshot = bonjourCollector.snapshot()

        guard !snapshot.isEmpty else { return }

        scanStatusMessage = "Resolving \(snapshot.count) services..."

        await withTaskGroup(of: (name: String, service: String, ips: [String], hostName: String?)?.self) { group in
            for item in snapshot {
                group.addTask {
                    let resolved = await BonjourResolver.resolve(
                        name: item.name,
                        type: item.type,
                        domain: item.domain.isEmpty ? "local." : item.domain,
                        timeout: 4.0
                    )
                    guard let resolved, !resolved.ips.isEmpty else { return nil }
                    return (name: item.name, service: item.service, ips: resolved.ips, hostName: resolved.hostName)
                }
            }

            for await result in group {
                guard let result else { continue }
                for ip in result.ips {
                    var entries = bonjourByIP[ip] ?? []
                    if !entries.contains(where: { $0.name == result.name && $0.service == result.service }) {
                        entries.append((name: result.name, service: result.service))
                    }
                    bonjourByIP[ip] = entries

                    if let host = result.hostName, !host.isEmpty,
                       bonjourHostByIP[ip] == nil {
                        bonjourHostByIP[ip] = host
                    }
                }
            }
        }
    }

    /// Applies newly-resolved Bonjour metadata (names/hostnames/services) to
    /// devices that were already added to the list via the port scan. Without
    /// this step, the port scan runs ahead of Bonjour resolution and devices
    /// end up with no display name even though Bonjour later identifies them.
    private func applyBonjourMetadataToExistingDevices() {
        for i in devices.indices {
            let ip = devices[i].ipAddress
            if let entries = bonjourByIP[ip], !entries.isEmpty {
                if devices[i].bonjourName == nil {
                    devices[i].bonjourName = entries.map(\.name).first
                }
                let existing = Set(devices[i].services)
                let merged = existing.union(Set(entries.map(\.service)))
                devices[i].services = Array(merged)
            }
            if devices[i].hostname == nil, let host = bonjourHostByIP[ip] {
                devices[i].hostname = host
            }
        }
        sortDevices()
    }

    private nonisolated static func friendlyServiceName(_ raw: String) -> String {
        if raw.contains("airplay") { return "AirPlay" }
        if raw.contains("raop") { return "AirPlay Audio" }
        if raw.contains("smb") { return "File Sharing" }
        if raw.contains("afpovertcp") { return "File Sharing" }
        if raw.contains("rfb") { return "Screen Sharing" }
        if raw.contains("ipp") || raw.contains("printer") { return "Printer" }
        if raw.contains("googlecast") { return "Chromecast" }
        if raw.contains("spotify") { return "Spotify Connect" }
        if raw.contains("homekit") || raw.contains("hap") { return "HomeKit" }
        if raw.contains("companion-link") { return "Apple Companion" }
        if raw.contains("rdlink") { return "Remote Desktop" }
        if raw.contains("device-info") { return "Device Info" }
        if raw.contains("sleep-proxy") { return "Sleep Proxy" }
        if raw.contains("amzn-wplay") { return "Amazon Audio" }
        if raw.contains("apple-mobdev") { return "Apple Device" }
        if raw.contains("touch-able") { return "Remote Control" }
        if raw.contains("http") { return "Web Server" }
        return raw
    }

    // MARK: - Bonjour Fallback (include devices found via Bonjour but missed by port scan)

    private func addBonjourOnlyDevices(localIP: String, gatewayIP: String) {
        for (ip, entries) in bonjourByIP {
            guard !discoveredIPs.contains(ip) else { continue }
            discoveredIPs.insert(ip)

            let isGateway = ip == gatewayIP
            let isSelf = ip == localIP
            let ssdpInfo = ssdpByIP[ip]
            let deviceType = classifyDevice(
                ip: ip,
                isGateway: isGateway,
                isSelf: isSelf,
                bonjourEntries: entries,
                openPorts: [],
                ssdpHeaders: ssdpInfo
            )
            let bonjourNames = entries.map(\.name)
            let ssdpName = upnpDescriptions[ip]?.friendlyName
            var allServices = Array(Set(entries.map(\.service)))
            if let ssdpInfo {
                let hint = ssdpServiceHint(ssdpInfo, ip: ip)
                if !allServices.contains(hint) { allServices.append(hint) }
            }
            // Trust flags and nicknames are applied at scan end.
            let device = DiscoveredDevice(
                id: ip,
                ipAddress: ip,
                hostname: bonjourHostByIP[ip],
                bonjourName: bonjourNames.first ?? ssdpName,
                services: allServices,
                deviceType: deviceType,
                openPorts: [],
                latencyMs: nil,
                macAddress: nil,
                ouiVendor: nil,
                hasRandomizedMAC: false,
                firstSeen: Date(),
                isCurrentDevice: isSelf,
                isTrusted: false,
                customName: nil
            )
            devices.append(device)
        }
        sortDevices()
    }

    // MARK: - SSDP / UPnP Discovery

    private func discoverSSDPDevices() async {
        let results: [String: [String: String]] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
                guard fd >= 0 else {
                    continuation.resume(returning: [:])
                    return
                }

                var reuse: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

                var timeout = timeval(tv_sec: 4, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

                var bindAddr = sockaddr_in()
                bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                bindAddr.sin_family = sa_family_t(AF_INET)
                bindAddr.sin_port = 0
                bindAddr.sin_addr.s_addr = INADDR_ANY
                withUnsafeMutablePointer(to: &bindAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        _ = Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }

                let searchTargets = ["ssdp:all", "upnp:rootdevice", "urn:dial-multiscreen-org:service:dial:1"]

                var destAddr = sockaddr_in()
                destAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                destAddr.sin_family = sa_family_t(AF_INET)
                destAddr.sin_port = UInt16(1900).bigEndian
                inet_pton(AF_INET, "239.255.255.250", &destAddr.sin_addr)

                for st in searchTargets {
                    let mSearch = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: \(st)\r\n\r\n"
                    let mBytes = Array(mSearch.utf8)
                    mBytes.withUnsafeBufferPointer { buf in
                        withUnsafeMutablePointer(to: &destAddr) { addrPtr in
                            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                                _ = sendto(fd, buf.baseAddress!, mBytes.count, 0, sockPtr,
                                           socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                    }
                    usleep(100_000)
                }

                var ssdpResults: [String: [String: String]] = [:]
                var buffer = [UInt8](repeating: 0, count: 4096)

                while true {
                    var fromAddr = sockaddr_in()
                    var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)

                    let n = withUnsafeMutablePointer(to: &fromAddr) { addrPtr in
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                            recvfrom(fd, &buffer, buffer.count, 0, sockPtr, &fromLen)
                        }
                    }
                    if n <= 0 { break }

                    var sinAddr = fromAddr.sin_addr
                    var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    _ = withUnsafePointer(to: &sinAddr) { addrPtr in
                        inet_ntop(AF_INET, addrPtr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
                    }
                    let ip = String(cString: ipBuf)

                    guard let response = String(bytes: buffer[0..<n], encoding: .utf8) else { continue }
                    var headers: [String: String] = ssdpResults[ip] ?? [:]
                    for line in response.components(separatedBy: "\r\n") {
                        guard let colonIdx = line.firstIndex(of: ":") else { continue }
                        let key = String(line[line.startIndex..<colonIdx])
                            .trimmingCharacters(in: .whitespaces).uppercased()
                        let value = String(line[line.index(after: colonIdx)...])
                            .trimmingCharacters(in: .whitespaces)
                        if key.isEmpty { continue }
                        if let existing = headers[key] {
                            if !existing.lowercased().contains(value.lowercased()) {
                                headers[key] = existing + "; " + value
                            }
                        } else {
                            headers[key] = value
                        }
                    }
                    ssdpResults[ip] = headers
                }

                Darwin.close(fd)
                continuation.resume(returning: ssdpResults)
            }
        }
        ssdpByIP = results
    }

    private func addSSDPOnlyDevices(localIP: String, gatewayIP: String) {
        for (ip, headers) in ssdpByIP {
            guard !discoveredIPs.contains(ip) else { continue }
            discoveredIPs.insert(ip)

            let isGateway = ip == gatewayIP
            let isSelf = ip == localIP
            let deviceType = classifyDevice(
                ip: ip,
                isGateway: isGateway,
                isSelf: isSelf,
                bonjourEntries: nil,
                openPorts: [],
                ssdpHeaders: headers
            )
            let serviceHint = ssdpServiceHint(headers, ip: ip)
            let ssdpName = upnpDescriptions[ip]?.friendlyName
            // Trust flags and nicknames are applied at scan end.
            let device = DiscoveredDevice(
                id: ip,
                ipAddress: ip,
                hostname: nil,
                bonjourName: ssdpName,
                services: [serviceHint],
                deviceType: deviceType,
                openPorts: [],
                latencyMs: nil,
                macAddress: nil,
                ouiVendor: nil,
                hasRandomizedMAC: false,
                firstSeen: Date(),
                isCurrentDevice: isSelf,
                isTrusted: false,
                customName: nil
            )
            devices.append(device)
        }
        sortDevices()
    }

    private func ssdpServiceHint(_ headers: [String: String], ip: String) -> String {
        if let upnp = upnpDescriptions[ip] {
            let mfr = (upnp.manufacturer ?? "").lowercased()
            if mfr.contains("amazon") { return "Amazon \(upnp.modelName ?? "Alexa")" }
            if mfr.contains("ring") { return "Ring" }
            if mfr.contains("roku") { return "Roku" }
            if mfr.contains("sonos") { return "Sonos" }
            if mfr.contains("samsung") { return "Samsung" }
            if mfr.contains("google") { return "Google Cast" }
            if mfr.contains("apple") { return "Apple" }
            if let model = upnp.modelName, !model.isEmpty { return model }
        }
        let server = (headers["SERVER"] ?? "").lowercased()
        if server.contains("amazon") || server.contains("alexa") || server.contains("echo") { return "Amazon Alexa" }
        if server.contains("ring") { return "Ring" }
        if server.contains("roku") { return "Roku" }
        if server.contains("sonos") { return "Sonos" }
        if server.contains("samsung") { return "Samsung UPnP" }
        if server.contains("google") { return "Google Cast" }
        return "UPnP"
    }

    // MARK: - UPnP Device Description Fetching

    private func fetchUPnPDescriptions() async {
        var locationsByIP: [String: String] = [:]
        for (ip, headers) in ssdpByIP {
            if let location = headers["LOCATION"], !location.isEmpty,
               location.lowercased().hasPrefix("http") {
                locationsByIP[ip] = location
            }
        }
        guard !locationsByIP.isEmpty else { return }

        await withTaskGroup(of: (String, String, String?, String?)?.self) { group in
            for (ip, location) in locationsByIP {
                group.addTask {
                    guard let result = await Self.fetchDeviceDescription(from: location) else { return nil }
                    return (ip, result.friendlyName, result.manufacturer, result.modelName)
                }
            }
            for await result in group {
                if let (ip, friendlyName, manufacturer, modelName) = result {
                    upnpDescriptions[ip] = (friendlyName: friendlyName, manufacturer: manufacturer, modelName: modelName)
                }
            }
        }
    }

    private nonisolated static func fetchDeviceDescription(from urlString: String) async -> (friendlyName: String, manufacturer: String?, modelName: String?)? {
        guard let url = URL(string: urlString) else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config)

        do {
            let (data, _) = try await session.data(from: url)
            guard let xml = String(data: data, encoding: .utf8) else { return nil }

            guard let friendlyName = extractXMLValue("friendlyName", from: xml), !friendlyName.isEmpty else { return nil }
            let manufacturer = extractXMLValue("manufacturer", from: xml)
            let modelName = extractXMLValue("modelName", from: xml)
            return (friendlyName, manufacturer, modelName)
        } catch {
            return nil
        }
    }

    private nonisolated static func extractXMLValue(_ tag: String, from xml: String) -> String? {
        guard let startRange = xml.range(of: "<\(tag)>", options: .caseInsensitive),
              let endRange = xml.range(of: "</\(tag)>", options: .caseInsensitive),
              startRange.upperBound < endRange.lowerBound else { return nil }
        let value = String(xml[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - Hostname Resolution

    private func resolveHostnames() async {
        await withTaskGroup(of: (Int, String?)?.self) { group in
            for (index, device) in devices.enumerated() {
                if device.bonjourName != nil { continue }
                group.addTask {
                    let name = await self.reverseDNS(ip: device.ipAddress)
                    return (index, name)
                }
            }
            for await result in group {
                guard let (index, name) = result, index < devices.count, let name else { continue }
                devices[index].hostname = name
                let cleaned = DiscoveredDevice.cleanHostname(name).lowercased()
                let currentType = devices[index].deviceType
                if let nameType = classifyByNameString(cleaned) {
                    if currentType == .unknown {
                        devices[index].deviceType = nameType
                    } else if [.iotDevice, .smartTV].contains(currentType),
                              [.gameConsole, .computer, .phone, .printer, .speaker].contains(nameType) {
                        devices[index].deviceType = nameType
                    }
                }
            }
        }

        for i in devices.indices {
            guard devices[i].bonjourName == nil else { continue }
            if let upnp = upnpDescriptions[devices[i].ipAddress] {
                devices[i].bonjourName = upnp.friendlyName
            }
        }
    }

    private func reverseDNS(ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            probeQueue.async {
                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else {
                    continuation.resume(returning: nil)
                    return
                }

                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = withUnsafePointer(to: &addr, { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        getnameinfo(sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size),
                                    &hostname, socklen_t(hostname.count),
                                    nil, 0, 0)
                    }
                })

                if result == 0 {
                    let name = String(cString: hostname)
                    if name != ip {
                        continuation.resume(returning: name)
                        return
                    }
                }
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - TCP Probe (all ports, concurrent) + Liveness Check

    private func probeHost(_ ip: String) async -> (latency: Double, ports: [UInt16])? {
        let portResults = await withTaskGroup(of: (UInt16, Double)?.self) { group -> [(UInt16, Double)] in
            for port in Self.probePorts {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    if let latency = await self.probePort(host: ip, port: port) {
                        return (port, latency)
                    }
                    return nil
                }
            }

            var hits: [(UInt16, Double)] = []
            for await result in group {
                if let r = result { hits.append(r) }
            }
            return hits
        }

        if !portResults.isEmpty {
            let bestLatency = portResults.map(\.1).min()!
            let openPorts = portResults.map(\.0).sorted()
            return (bestLatency, openPorts)
        }

        if let latency = await livenessCheck(ip) {
            return (latency, [])
        }

        return nil
    }

    /// Detects if a host is alive even with all probed ports filtered.
    /// A fast TCP RST (connection refused) means the host is up but the port is closed.
    private func livenessCheck(_ ip: String) async -> Double? {
        let checkPorts: [UInt16] = [443, 80, 7, 1]
        return await withTaskGroup(of: Double?.self) { group in
            for port in checkPorts {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return await self.probeLiveness(host: ip, port: port)
                }
            }

            for await result in group {
                if let latency = result {
                    group.cancelAll()
                    return latency
                }
            }
            return nil
        }
    }

    /// Connects to a port with a longer timeout; counts both "ready" and fast "refused" as alive.
    private func probeLiveness(host: String, port: UInt16) async -> Double? {
        await withCheckedContinuation { continuation in
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: nil)
                return
            }

            let params = NWParameters.tcp
            params.requiredInterfaceType = .wifi
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: params
            )

            let start = DispatchTime.now()
            let hasResumed = AtomicBool()

            // `@Sendable` so the closure (captured by the NWConnection state
            // handler + the probeQueue timeout block, both of which hop
            // threads) satisfies strict-concurrency checking. It only
            // captures `Sendable` state (`DispatchTime`, `NWConnection`,
            // `NSLock` via `AtomicBool`, and the continuation).
            @Sendable func finish(_ value: Double?) {
                guard hasResumed.setIfUnset() else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { state in
                let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                let ms = Double(elapsedNs) / 1_000_000
                switch state {
                case .ready:
                    finish(ms)
                case .failed:
                    if ms < 500 {
                        finish(ms)
                    } else {
                        finish(nil)
                    }
                case .cancelled:
                    finish(nil)
                default:
                    break
                }
            }

            probeQueue.asyncAfter(deadline: .now() + 0.8) {
                finish(nil)
            }

            connection.start(queue: probeQueue)
        }
    }

    private func probePort(host: String, port: UInt16) async -> Double? {
        await withCheckedContinuation { continuation in
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: nil)
                return
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .tcp
            )

            let start = DispatchTime.now()
            let hasResumed = AtomicBool()

            // See probeLivenessRefused() above for why `finish` is @Sendable.
            @Sendable func finish(_ value: Double?) {
                guard hasResumed.setIfUnset() else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                    let ms = Double(elapsedNs) / 1_000_000
                    finish(ms)
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }

            probeQueue.asyncAfter(deadline: .now() + 0.8) {
                finish(nil)
            }

            connection.start(queue: probeQueue)
        }
    }

    // MARK: - Device Classification

    private func classifyDevice(
        ip: String,
        isGateway: Bool,
        isSelf: Bool,
        bonjourEntries: [(name: String, service: String)]?,
        openPorts: [UInt16],
        ssdpHeaders: [String: String]?
    ) -> DiscoveredDevice.DeviceType {
        if isGateway { return .router }
        if isSelf { return .phone }

        if let entries = bonjourEntries, !entries.isEmpty {
            let allNames = entries.map { $0.name.lowercased() }
            let allServices = entries.map { $0.service.lowercased() }
            let nameStr = allNames.joined(separator: " ")

            if allServices.contains(where: { $0.contains("printer") || $0.contains("ipp") }) { return .printer }
            if allServices.contains(where: { $0.contains("chromecast") }) { return .smartTV }
            if allServices.contains(where: { $0.contains("amazon audio") }) { return .speaker }

            if allServices.contains(where: { $0.contains("airplay") }) {
                if nameStr.contains("tv") || nameStr.contains("apple tv") { return .smartTV }
                if nameStr.contains("homepod") || nameStr.contains("sonos") || nameStr.contains("echo") { return .speaker }
                let hasComputerService = allServices.contains(where: {
                    $0.contains("file sharing") || $0.contains("remote desktop") || $0.contains("screen sharing")
                })
                if hasComputerService { return .computer }
                if openPorts.contains(548) || openPorts.contains(445) || openPorts.contains(22) { return .computer }
                if let nameType = classifyByNameString(nameStr), nameType == .computer { return .computer }
                return .smartTV
            }

            if allServices.contains(where: { $0.contains("spotify") || $0.contains("raop") || $0.contains("media") }) { return .speaker }
            if allServices.contains(where: { $0.contains("homekit") || $0.contains("hap") }) { return .iotDevice }
            if allServices.contains(where: { $0.contains("file sharing") || $0.contains("remote desktop") || $0.contains("screen sharing") }) { return .computer }
            if allServices.contains(where: { $0.contains("companion") || $0.contains("apple device") || $0.contains("remote control") }) { return .phone }

            if let nameType = classifyByNameString(nameStr) { return nameType }
        }

        if let headers = ssdpHeaders, let ssdpType = classifyBySSDP(headers, ip: ip) {
            return ssdpType
        }

        return classifyByPorts(openPorts)
    }

    private func classifyByNameString(_ lowered: String) -> DiscoveredDevice.DeviceType? {
        if lowered.contains("iphone") || lowered.contains("ipad") || lowered.contains("android") || lowered.contains("pixel") { return .phone }

        if lowered.contains("macbook") || lowered.contains("imac") || lowered.contains("mac mini") ||
           lowered.contains("macmini") || lowered.contains("mac-mini") || lowered.contains("mac pro") ||
           lowered.contains("macpro") || lowered.contains("mac-pro") || lowered.contains("mac-") ||
           lowered.contains("mac.") || lowered.contains("mbp") || lowered.contains("windows") ||
           lowered.contains("desktop") || lowered.contains("laptop") || lowered.contains("thinkpad") ||
           lowered.contains("surface") || lowered.contains("dell-") || lowered.contains("lenovo") ||
           lowered.contains("hp-pc") || lowered.contains("workstation") { return .computer }

        if lowered.contains("xbox") || lowered.contains("playstation") || lowered.contains("ps5") ||
           lowered.contains("ps4") || lowered.contains("nintendo") { return .gameConsole }
        if lowered.contains("switch") && !lowered.contains("network switch") &&
           !lowered.contains("ethernet switch") { return .gameConsole }

        if lowered.contains("echo") || lowered.contains("alexa") || lowered.contains("homepod") ||
           lowered.contains("sonos") || lowered.contains("home mini") ||
           lowered.contains("nest audio") || lowered.contains("nest mini") { return .speaker }

        if lowered.contains("roku") || lowered.contains("fire tv") || lowered.contains("firetv") ||
           lowered.contains("fire stick") || lowered.contains("chromecast") ||
           lowered.contains("shield") { return .smartTV }
        if lowered.contains("tv") { return .smartTV }

        if lowered.contains("printer") || lowered.contains("epson") || lowered.contains("canon") ||
           lowered.contains("brother") || lowered.contains("hp-") || lowered.contains("laserjet") { return .printer }

        if lowered.contains("ring") || lowered.contains("doorbell") || lowered.contains("cam") ||
           lowered.contains("hue") || lowered.contains("wemo") || lowered.contains("smart") ||
           lowered.contains("plug") || lowered.contains("bulb") || lowered.contains("sensor") ||
           lowered.contains("thermostat") { return .iotDevice }
        if lowered.contains("nest") { return .iotDevice }
        return nil
    }

    private func classifyByPorts(_ ports: [UInt16]) -> DiscoveredDevice.DeviceType {
        if ports.contains(62078) { return .phone }
        if ports.contains(548) { return .computer }
        if ports.contains(22) && (ports.contains(445) || ports.contains(548) || ports.contains(5000)) { return .computer }
        if ports.contains(445) && ports.contains(22) { return .computer }
        if ports.contains(445) && ports.contains(7000) { return .computer }
        if ports.contains(445) && !ports.contains(7000) { return .computer }
        if ports.contains(139) && ports.contains(22) { return .computer }
        if ports.contains(139) && !ports.contains(7000) { return .computer }
        if ports.contains(22) && ports.count <= 3 { return .computer }
        if ports.contains(9100) || ports.contains(631) || ports.contains(515) { return .printer }
        if ports.contains(7000) || ports.contains(8008) { return .smartTV }
        if ports.contains(3689) { return .speaker }
        if ports.contains(554) { return .iotDevice }
        if ports.contains(1883) { return .iotDevice }
        if ports.count == 1 && ports.first == 80 { return .iotDevice }
        let webOnlyPorts: Set<UInt16> = [80, 443, 8080, 8888, 8443, 3000, 5000]
        if !ports.isEmpty && Set(ports).isSubset(of: webOnlyPorts) { return .iotDevice }
        return .unknown
    }

    private func classifyBySSDP(_ headers: [String: String], ip: String) -> DiscoveredDevice.DeviceType? {
        let server = (headers["SERVER"] ?? "").lowercased()
        let st = (headers["ST"] ?? "").lowercased()
        let usn = (headers["USN"] ?? "").lowercased()
        let upnp = upnpDescriptions[ip]
        let mfr = (upnp?.manufacturer ?? "").lowercased()
        let model = (upnp?.modelName ?? "").lowercased()
        let fname = (upnp?.friendlyName ?? "").lowercased()
        let combined = [server, st, usn, mfr, model, fname].joined(separator: " ")

        if mfr.contains("amazon") || combined.contains("alexa") || combined.contains("echo") {
            if combined.contains("fire tv") || combined.contains("firetv") || combined.contains("fire_tv") { return .smartTV }
            if combined.contains("fire tablet") || combined.contains("kindle") { return .phone }
            return .speaker
        }
        if mfr.contains("ring") || combined.contains("ring") { return .iotDevice }
        if combined.contains("xbox") { return .gameConsole }
        if combined.contains("playstation") || combined.contains("ps5") { return .gameConsole }
        if combined.contains("nintendo") { return .gameConsole }
        if mfr.contains("roku") || combined.contains("roku") { return .smartTV }
        if (mfr.contains("samsung") || combined.contains("samsung")) && combined.contains("tv") { return .smartTV }
        if combined.contains("lg webos") || combined.contains("webostv") { return .smartTV }
        if mfr.contains("vizio") || combined.contains("vizio") { return .smartTV }
        if mfr.contains("sonos") || combined.contains("sonos") { return .speaker }
        if combined.contains("homepod") { return .speaker }
        if mfr.contains("google") || combined.contains("google") {
            if combined.contains("home") || combined.contains("nest") || model.contains("speaker") { return .speaker }
            if combined.contains("chromecast") { return .smartTV }
        }
        if mfr.contains("apple") {
            if combined.contains("apple tv") || combined.contains("appletv") { return .smartTV }
            if combined.contains("homepod") { return .speaker }
            if combined.contains("iphone") || combined.contains("ipad") { return .phone }
            if combined.contains("mac") { return .computer }
        }
        if combined.contains("printer") || mfr.contains("epson") || mfr.contains("brother") ||
           mfr.contains("hp") || mfr.contains("canon") { return .printer }
        if mfr.contains("tp-link") || mfr.contains("belkin") || mfr.contains("wemo") { return .iotDevice }
        if st.contains("mediarenderer") { return .smartTV }
        if st.contains("dial") { return .smartTV }
        return nil
    }

    // MARK: - HTTP Fingerprinting (seventh identification layer)

    private struct HTTPFingerprintResult {
        var manufacturer: String?
        var deviceName: String?
        var suggestedType: DiscoveredDevice.DeviceType?
    }

    private func httpFingerprint() async {
        let candidates: [(index: Int, ip: String, port: UInt16)] = devices.enumerated().compactMap { (index, device) in
            guard !device.isCurrentDevice, device.deviceType != .router else { return nil }
            let needsName = device.bonjourName == nil && device.hostname == nil
            let needsType = device.deviceType == .unknown
            guard needsName || needsType || device.manufacturer == nil else { return nil }

            if device.openPorts.contains(80) { return (index, device.ipAddress, 80) }
            if device.openPorts.contains(8080) { return (index, device.ipAddress, 8080) }
            return nil
        }

        guard !candidates.isEmpty else { return }

        await withTaskGroup(of: (Int, HTTPFingerprintResult?)?.self) { group in
            for (index, ip, port) in candidates {
                group.addTask {
                    let result = await Self.performHTTPFingerprint(ip: ip, port: port)
                    return (index, result)
                }
            }

            for await taskResult in group {
                guard let (index, fpResult) = taskResult, let fpResult,
                      index < devices.count else { continue }
                if let mfr = fpResult.manufacturer {
                    devices[index].manufacturer = mfr
                }
                if devices[index].bonjourName == nil,
                   let name = fpResult.deviceName, !name.isEmpty {
                    devices[index].bonjourName = name
                }
                if let suggested = fpResult.suggestedType {
                    let current = devices[index].deviceType
                    if current == .unknown ||
                       (current == .iotDevice && [.speaker, .smartTV, .printer, .computer, .phone, .gameConsole].contains(suggested)) {
                        devices[index].deviceType = suggested
                    }
                }
            }
        }
    }

    private nonisolated static func performHTTPFingerprint(ip: String, port: UInt16) async -> HTTPFingerprintResult? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config)

        if let result = await fetchAndAnalyzeHTTP(session: session, ip: ip, port: port, path: "/") {
            return result
        }

        for path in ["/xml/device_description.xml", "/rootDesc.xml", "/description.xml"] {
            if let result = await fetchAndAnalyzeUPnP(session: session, ip: ip, port: port, path: path) {
                return result
            }
        }

        return nil
    }

    private nonisolated static func fetchAndAnalyzeHTTP(
        session: URLSession, ip: String, port: UInt16, path: String
    ) async -> HTTPFingerprintResult? {
        guard let url = URL(string: "http://\(ip):\(port)\(path)") else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode < 500 else { return nil }

            let serverHeader = (httpResponse.value(forHTTPHeaderField: "Server") ?? "").lowercased()
            let bodyStr = String(data: data.prefix(8192), encoding: .utf8) ?? ""
            let body = bodyStr.lowercased()

            if body.contains("<friendlyname>") || body.contains("<manufacturer>") {
                return analyzeUPnPXML(bodyStr)
            }

            return analyzeHTTPResponse(serverHeader: serverHeader, body: body, rawBody: bodyStr)
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchAndAnalyzeUPnP(
        session: URLSession, ip: String, port: UInt16, path: String
    ) async -> HTTPFingerprintResult? {
        guard let url = URL(string: "http://\(ip):\(port)\(path)") else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let xml = String(data: data, encoding: .utf8),
                  xml.lowercased().contains("<friendlyname>") || xml.lowercased().contains("<manufacturer>")
            else { return nil }

            return analyzeUPnPXML(xml)
        } catch {
            return nil
        }
    }

    private nonisolated static func analyzeUPnPXML(_ xml: String) -> HTTPFingerprintResult? {
        let friendlyName = extractXMLValue("friendlyName", from: xml)
        let manufacturer = extractXMLValue("manufacturer", from: xml)
        let modelName = extractXMLValue("modelName", from: xml)

        guard manufacturer != nil || friendlyName != nil else { return nil }

        let combined = [manufacturer ?? "", modelName ?? "", friendlyName ?? ""]
            .joined(separator: " ").lowercased()

        var result = HTTPFingerprintResult()
        result.manufacturer = manufacturer
        result.deviceName = friendlyName

        if combined.contains("amazon") || combined.contains("echo") || combined.contains("alexa") {
            if combined.contains("fire tv") || combined.contains("firetv") || combined.contains("fire_tv") {
                result.suggestedType = .smartTV
            } else if combined.contains("fire tablet") || combined.contains("kindle") {
                result.suggestedType = .phone
            } else {
                result.suggestedType = .speaker
            }
        } else if combined.contains("google") {
            if combined.contains("chromecast") { result.suggestedType = .smartTV }
            else if combined.contains("home") || combined.contains("nest") || combined.contains("speaker") {
                result.suggestedType = .speaker
            }
        } else if combined.contains("roku") {
            result.suggestedType = .smartTV
        } else if combined.contains("sonos") {
            result.suggestedType = .speaker
        } else if combined.contains("samsung") && combined.contains("tv") {
            result.suggestedType = .smartTV
        } else if combined.contains("printer") || combined.contains("epson") ||
                    combined.contains("brother") || combined.contains("canon") {
            result.suggestedType = .printer
        } else if combined.contains("tp-link") || combined.contains("belkin") || combined.contains("wemo") {
            result.suggestedType = .iotDevice
        }

        return result
    }

    private nonisolated static func analyzeHTTPResponse(
        serverHeader: String, body: String, rawBody: String
    ) -> HTTPFingerprintResult? {
        let title = extractHTMLTitle(from: rawBody)
        let titleLower = (title ?? "").lowercased()
        let combined = [serverHeader, body, titleLower].joined(separator: " ")

        if combined.contains("amazon") || combined.contains("alexa") || combined.contains("echo dot") ||
           combined.contains("echo show") || combined.contains("echo pop") {
            if combined.contains("fire tv") || combined.contains("firetv") {
                return HTTPFingerprintResult(manufacturer: "Amazon", deviceName: title ?? "Fire TV", suggestedType: .smartTV)
            }
            return HTTPFingerprintResult(manufacturer: "Amazon", deviceName: title, suggestedType: .speaker)
        }

        if serverHeader.contains("google") || combined.contains("chromecast") ||
           combined.contains("google home") || combined.contains("google nest") {
            if combined.contains("chromecast") {
                return HTTPFingerprintResult(manufacturer: "Google", deviceName: title ?? "Chromecast", suggestedType: .smartTV)
            }
            return HTTPFingerprintResult(manufacturer: "Google", deviceName: title, suggestedType: .speaker)
        }

        if combined.contains("roku") {
            return HTTPFingerprintResult(manufacturer: "Roku", deviceName: title ?? "Roku", suggestedType: .smartTV)
        }

        if combined.contains("samsung") && combined.contains("tv") {
            return HTTPFingerprintResult(manufacturer: "Samsung", deviceName: title, suggestedType: .smartTV)
        }

        if combined.contains("sonos") {
            return HTTPFingerprintResult(manufacturer: "Sonos", deviceName: title ?? "Sonos", suggestedType: .speaker)
        }

        if combined.contains("homepod") {
            return HTTPFingerprintResult(manufacturer: "Apple", deviceName: title ?? "HomePod", suggestedType: .speaker)
        }

        if combined.contains("epson") {
            return HTTPFingerprintResult(manufacturer: "Epson", deviceName: title, suggestedType: .printer)
        }
        if combined.contains("brother") && (combined.contains("print") || combined.contains("mfc") || combined.contains("hl-")) {
            return HTTPFingerprintResult(manufacturer: "Brother", deviceName: title, suggestedType: .printer)
        }
        if combined.contains("canon") && (combined.contains("print") || combined.contains("pixma") || combined.contains("imagerunner")) {
            return HTTPFingerprintResult(manufacturer: "Canon", deviceName: title, suggestedType: .printer)
        }
        if (combined.contains("hp ") || combined.contains("hewlett")) &&
           (combined.contains("print") || combined.contains("laserjet") || combined.contains("officejet") || combined.contains("envy")) {
            return HTTPFingerprintResult(manufacturer: "HP", deviceName: title, suggestedType: .printer)
        }

        if combined.contains("tp-link") || combined.contains("tplink") {
            return HTTPFingerprintResult(manufacturer: "TP-Link", deviceName: title, suggestedType: .iotDevice)
        }
        if combined.contains("belkin") || combined.contains("wemo") {
            return HTTPFingerprintResult(manufacturer: "Belkin", deviceName: title, suggestedType: .iotDevice)
        }
        if combined.contains("philips") && combined.contains("hue") {
            return HTTPFingerprintResult(manufacturer: "Philips", deviceName: "Hue Bridge", suggestedType: .iotDevice)
        }
        if combined.contains("ring") && (combined.contains("doorbell") || combined.contains("camera") || combined.contains("security")) {
            return HTTPFingerprintResult(manufacturer: "Ring", deviceName: title, suggestedType: .iotDevice)
        }
        if combined.contains("nest") && (combined.contains("thermostat") || combined.contains("camera") || combined.contains("protect")) {
            return HTTPFingerprintResult(manufacturer: "Google", deviceName: title, suggestedType: .iotDevice)
        }
        if combined.contains("xbox") {
            return HTTPFingerprintResult(manufacturer: "Microsoft", deviceName: title ?? "Xbox", suggestedType: .gameConsole)
        }
        if combined.contains("playstation") || combined.contains("ps5") || combined.contains("ps4") {
            return HTTPFingerprintResult(manufacturer: "Sony", deviceName: title ?? "PlayStation", suggestedType: .gameConsole)
        }

        if !serverHeader.isEmpty {
            let cleaned = serverHeader.components(separatedBy: CharacterSet(charactersIn: "/"))
                .first?.trimmingCharacters(in: .whitespaces) ?? ""
            let genericServers = ["httpd", "http", "server", "apache", "nginx", "lighttpd",
                                  "webserver", "micro", "lwip", "boa", "mini", "uhttpd", "embedded"]
            if cleaned.count >= 3 && !genericServers.contains(cleaned) {
                return HTTPFingerprintResult(manufacturer: cleaned.capitalized, deviceName: title, suggestedType: nil)
            }
        }

        return nil
    }

    private nonisolated static func extractHTMLTitle(from html: String) -> String? {
        guard let startRange = html.range(of: "<title>", options: .caseInsensitive),
              let endRange = html.range(of: "</title>", options: .caseInsensitive),
              startRange.upperBound < endRange.lowerBound else { return nil }
        let title = String(html[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    // MARK: - Network Utilities

    private func getLocalIPAndMask() -> (ip: String?, mask: String?) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return (nil, nil) }
        defer { freeifaddrs(ifaddr) }

        var resultIP: String?
        var resultMask: String?

        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    resultIP = String(cString: hostname)

                    if let maskAddr = interface.ifa_netmask {
                        var maskHostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(maskAddr, socklen_t(maskAddr.pointee.sa_len),
                                   &maskHostname, socklen_t(maskHostname.count), nil, 0, NI_NUMERICHOST)
                        resultMask = String(cString: maskHostname)
                    }
                    break
                }
            }

            guard let next = interface.ifa_next else { break }
            ptr = next
        }

        return (resultIP, resultMask)
    }

    private func calculateSubnetRange(ip: String, mask: String) -> [String] {
        let ipParts = ip.split(separator: ".").compactMap { UInt32($0) }
        let maskParts = mask.split(separator: ".").compactMap { UInt32($0) }
        guard ipParts.count == 4, maskParts.count == 4 else { return [] }

        let ipNum = (ipParts[0] << 24) | (ipParts[1] << 16) | (ipParts[2] << 8) | ipParts[3]
        let maskNum = (maskParts[0] << 24) | (maskParts[1] << 16) | (maskParts[2] << 8) | maskParts[3]

        let network = ipNum & maskNum
        let broadcast = network | ~maskNum
        let hostCount = broadcast - network - 1

        guard hostCount > 0, hostCount <= 1024 else {
            let base = network
            return (1...254).map { i in
                let addr = base + UInt32(i)
                return "\(addr >> 24 & 0xFF).\(addr >> 16 & 0xFF).\(addr >> 8 & 0xFF).\(addr & 0xFF)"
            }
        }

        return (1...hostCount).map { i in
            let addr = network + UInt32(i)
            return "\(addr >> 24 & 0xFF).\(addr >> 16 & 0xFF).\(addr >> 8 & 0xFF).\(addr & 0xFF)"
        }
    }

    private func inferGatewayIP(localIP: String) -> String {
        let parts = localIP.split(separator: ".")
        guard parts.count == 4 else { return "192.168.0.1" }
        return "\(parts[0]).\(parts[1]).\(parts[2]).1"
    }
}

// MARK: - BonjourCollector
//
// Thread-safe, nonisolated container for Bonjour browse results. Used to
// bridge NWBrowser's background-queue callbacks into the main-actor-isolated
// NetworkScanner without contaminating the scanner's isolation domain.
final class BonjourCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [NWEndpoint: (name: String, service: String, type: String, domain: String)] = [:]

    func insertIfMissing(
        endpoint: NWEndpoint,
        name: String,
        service: String,
        type: String,
        domain: String
    ) {
        lock.lock()
        defer { lock.unlock() }
        if storage[endpoint] == nil {
            storage[endpoint] = (name: name, service: service, type: type, domain: domain)
        }
    }

    func snapshot() -> [(name: String, service: String, type: String, domain: String)] {
        lock.lock()
        defer { lock.unlock() }
        return Array(storage.values)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}

// MARK: - BonjourResolver
//
// Resolves a single Bonjour service via Foundation's `NetService`. Unlike the
// previous `NWConnection`-based approach, this returns the resolved IPv4
// addresses AND the advertised Bonjour hostname in a single delegate
// callback, regardless of whether the advertised service port is firewalled.
// That makes Bonjour-driven device name discovery reliable on iOS.
final class BonjourResolver: NSObject, NetServiceDelegate {
    /// Resolves a Bonjour service and returns its IPv4 addresses + hostname.
    /// Returns nil on timeout or resolution failure.
    static func resolve(
        name: String,
        type: String,
        domain: String,
        timeout: TimeInterval
    ) async -> (ips: [String], hostName: String?)? {
        await withCheckedContinuation { (continuation: CheckedContinuation<(ips: [String], hostName: String?)?, Never>) in
            let service = NetService(domain: domain, type: type, name: name)
            let resolver = BonjourResolver(service: service, continuation: continuation)
            resolver.start(timeout: timeout)
        }
    }

    private let service: NetService
    private let continuation: CheckedContinuation<(ips: [String], hostName: String?)?, Never>
    private let lock = NSLock()
    private var finished = false
    // Strong self reference retains the delegate until resolution completes.
    // NetService's `delegate` is a weak reference; without this retain cycle
    // the resolver could be deallocated before the callback fires.
    private var selfRetain: BonjourResolver?

    private init(
        service: NetService,
        continuation: CheckedContinuation<(ips: [String], hostName: String?)?, Never>
    ) {
        self.service = service
        self.continuation = continuation
        super.init()
        self.service.delegate = self
    }

    private func start(timeout: TimeInterval) {
        selfRetain = self
        // NetService delivers delegate callbacks on the scheduled run loop.
        // The main run loop is always active on iOS apps, so use it.
        DispatchQueue.main.async { [service] in
            service.schedule(in: RunLoop.main, forMode: .default)
            service.resolve(withTimeout: timeout)
        }
        // Belt-and-suspenders timeout: NetService should call didNotResolve
        // on timeout, but occasionally gets wedged. Force a resolution after
        // timeout + 1s no matter what.
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout + 1.0) { [weak self] in
            self?.finish(nil)
        }
    }

    private func finish(_ result: (ips: [String], hostName: String?)?) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()

        let svc = self.service
        DispatchQueue.main.async {
            svc.stop()
            svc.remove(from: RunLoop.main, forMode: .default)
            svc.delegate = nil
        }
        continuation.resume(returning: result)
        // Release the strong self-reference so the resolver can deallocate.
        selfRetain = nil
    }

    // MARK: NetServiceDelegate

    func netServiceDidResolveAddress(_ sender: NetService) {
        let ips = BonjourResolver.extractIPv4Addresses(from: sender.addresses ?? [])
        var host = sender.hostName
        if var h = host {
            // NetService hostnames typically include a trailing "." — trim it.
            while h.hasSuffix(".") { h.removeLast() }
            host = h.isEmpty ? nil : h
        }
        finish((ips: ips, hostName: host))
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        finish(nil)
    }

    private static func extractIPv4Addresses(from datas: [Data]) -> [String] {
        var result: [String] = []
        for data in datas {
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                let sa = base.assumingMemoryBound(to: sockaddr.self)
                if sa.pointee.sa_family == sa_family_t(AF_INET) {
                    let sin = base.assumingMemoryBound(to: sockaddr_in.self)
                    var addr = sin.pointee.sin_addr
                    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    if inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                        let ipStr = String(cString: buf)
                        if !ipStr.isEmpty && !result.contains(ipStr) {
                            result.append(ipStr)
                        }
                    }
                }
            }
        }
        return result
    }
}
