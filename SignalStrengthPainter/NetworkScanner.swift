import Foundation
import Network
import Darwin

struct DiscoveredDevice: Identifiable {
    let id: String
    let ipAddress: String
    var hostname: String?
    var bonjourName: String?
    var services: [String]
    var deviceType: DeviceType
    var latencyMs: Double?
    var manufacturer: String?
    let firstSeen: Date
    var isCurrentDevice: Bool
    var isTrusted: Bool

    var displayHostname: String? {
        if let name = bonjourName, !name.isEmpty { return name }
        if let h = hostname, !h.isEmpty, h != ipAddress { return h }
        return nil
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

    private var browser: NWBrowser?
    private var scanTask: Task<Void, Never>?
    private let probeQueue = DispatchQueue(label: "network.scanner.probe", attributes: .concurrent)

    private var discoveredIPs: Set<String> = []
    private var bonjourResults: [String: (name: String, service: String)] = [:]

    private static let trustedKey = "trustedDeviceIPs"

    var trustedIPs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.trustedKey) ?? [])
    }

    func setTrusted(_ ip: String, trusted: Bool) {
        var current = trustedIPs
        if trusted { current.insert(ip) } else { current.remove(ip) }
        UserDefaults.standard.set(Array(current), forKey: Self.trustedKey)
        if let idx = devices.firstIndex(where: { $0.ipAddress == ip }) {
            devices[idx].isTrusted = trusted
        }
        objectWillChange.send()
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0
        devices = []
        discoveredIPs = []
        bonjourResults = [:]
        scanStatusMessage = "Discovering local network..."

        let (ip, mask) = getLocalIPAndMask()
        localIP = ip ?? "Unknown"
        subnetMask = mask ?? "Unknown"

        startBonjourBrowsing()

        scanTask = Task {
            guard let ip, let mask else {
                scanStatusMessage = "Could not determine local network"
                isScanning = false
                return
            }

            let subnet = calculateSubnetRange(ip: ip, mask: mask)
            let gatewayIP = inferGatewayIP(localIP: ip)
            let totalHosts = subnet.count
            var scannedCount = 0

            scanStatusMessage = "Scanning \(totalHosts) addresses..."

            let batchSize = 30
            for batchStart in stride(from: 0, to: totalHosts, by: batchSize) {
                if Task.isCancelled { break }

                let batchEnd = min(batchStart + batchSize, totalHosts)
                let batch = Array(subnet[batchStart..<batchEnd])

                await withTaskGroup(of: (String, Double?)?.self) { group in
                    for targetIP in batch {
                        group.addTask { [weak self] in
                            guard let self else { return nil }
                            let latency = await self.probeHost(targetIP)
                            if latency != nil {
                                return (targetIP, latency)
                            }
                            return nil
                        }
                    }

                    for await result in group {
                        if let (foundIP, latency) = result {
                            if !discoveredIPs.contains(foundIP) {
                                discoveredIPs.insert(foundIP)
                                let isGateway = foundIP == gatewayIP
                                let isSelf = foundIP == ip
                                let deviceType = classifyDevice(
                                    ip: foundIP,
                                    isGateway: isGateway,
                                    isSelf: isSelf,
                                    bonjourInfo: bonjourResults[foundIP]
                                )
                                let hostname = bonjourResults[foundIP]?.name
                                let device = DiscoveredDevice(
                                    id: foundIP,
                                    ipAddress: foundIP,
                                    hostname: hostname,
                                    bonjourName: bonjourResults[foundIP]?.name,
                                    services: bonjourResults[foundIP].map { [$0.service] } ?? [],
                                    deviceType: deviceType,
                                    latencyMs: latency,
                                    firstSeen: Date(),
                                    isCurrentDevice: isSelf,
                                    isTrusted: trustedIPs.contains(foundIP)
                                )
                                devices.append(device)
                                devices.sort { lhs, rhs in
                                    if lhs.isCurrentDevice { return true }
                                    if rhs.isCurrentDevice { return false }
                                    if lhs.deviceType == .router { return true }
                                    if rhs.deviceType == .router { return false }
                                    return lhs.ipAddress < rhs.ipAddress
                                }
                            }
                        }
                    }
                }

                scannedCount += batch.count
                scanProgress = Double(scannedCount) / Double(totalHosts)
                scanStatusMessage = "Scanned \(scannedCount)/\(totalHosts) — Found \(devices.count) device\(devices.count == 1 ? "" : "s")"
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            enrichDevicesWithBonjour()

            scanStatusMessage = "Resolving device names..."
            await resolveHostnames()

            isScanning = false
            scanStatusMessage = "Scan complete — \(devices.count) device\(devices.count == 1 ? "" : "s") found"
        }
    }

    func stopScan() {
        scanTask?.cancel()
        browser?.cancel()
        browser = nil
        isScanning = false
        scanStatusMessage = devices.isEmpty ? "Scan stopped" : "Scan stopped — \(devices.count) device\(devices.count == 1 ? "" : "s") found"
    }

    // MARK: - Bonjour Discovery

    private func startBonjourBrowsing() {
        let serviceTypes = ["_http._tcp", "_airplay._tcp", "_raop._tcp",
                           "_smb._tcp", "_ipp._tcp", "_printer._tcp",
                           "_googlecast._tcp", "_spotify-connect._tcp",
                           "_homekit._tcp", "_hap._tcp"]

        for serviceType in serviceTypes {
            let params = NWParameters()
            params.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)

            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for result in results {
                        if case let .service(name, type, _, _) = result.endpoint {
                            let friendlyService = self.friendlyServiceName(type)
                            self.bonjourResults[name] = (name: name, service: friendlyService)
                        }
                    }
                }
            }

            browser.stateUpdateHandler = { _ in }
            browser.start(queue: probeQueue)

            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                browser.cancel()
            }
        }
    }

    private func enrichDevicesWithBonjour() {
        for (name, info) in bonjourResults {
            if let idx = devices.firstIndex(where: {
                $0.bonjourName == name || $0.hostname?.localizedCaseInsensitiveContains(name) == true
            }) {
                if !devices[idx].services.contains(info.service) {
                    devices[idx].services.append(info.service)
                }
                if devices[idx].bonjourName == nil {
                    devices[idx].bonjourName = info.name
                }
            }
        }
    }

    private func resolveHostnames() async {
        await withTaskGroup(of: (Int, String?)?.self) { group in
            for (index, device) in devices.enumerated() {
                if device.hostname != nil { continue }
                group.addTask {
                    let name = await self.reverseDNS(ip: device.ipAddress)
                    return (index, name)
                }
            }
            for await result in group {
                guard let (index, name) = result, index < devices.count, let name else { continue }
                devices[index].hostname = name
                if devices[index].deviceType == .unknown {
                    devices[index].deviceType = classifyDevice(
                        ip: devices[index].ipAddress,
                        isGateway: false,
                        isSelf: devices[index].isCurrentDevice,
                        bonjourInfo: (name: name, service: "")
                    )
                }
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

    private func friendlyServiceName(_ raw: String) -> String {
        if raw.contains("airplay") { return "AirPlay" }
        if raw.contains("raop") { return "AirPlay Audio" }
        if raw.contains("smb") { return "File Sharing" }
        if raw.contains("ipp") || raw.contains("printer") { return "Printer" }
        if raw.contains("googlecast") { return "Chromecast" }
        if raw.contains("spotify") { return "Spotify Connect" }
        if raw.contains("homekit") || raw.contains("hap") { return "HomeKit" }
        if raw.contains("http") { return "Web Server" }
        return raw
    }

    // MARK: - TCP Probe

    private func probeHost(_ ip: String) async -> Double? {
        let ports: [UInt16] = [80, 443, 62078, 548, 445, 7000, 8080]

        for port in ports {
            if let latency = await probePort(host: ip, port: port) {
                return latency
            }
        }
        return nil
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
            var hasResumed = false
            let lock = NSLock()

            func finish(_ value: Double?) {
                lock.lock()
                guard !hasResumed else {
                    lock.unlock()
                    return
                }
                hasResumed = true
                lock.unlock()
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

            probeQueue.asyncAfter(deadline: .now() + 0.3) {
                finish(nil)
            }

            connection.start(queue: probeQueue)
        }
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

    private func classifyDevice(ip: String, isGateway: Bool, isSelf: Bool, bonjourInfo: (name: String, service: String)?) -> DiscoveredDevice.DeviceType {
        if isGateway { return .router }
        if isSelf { return .phone }

        if let info = bonjourInfo {
            let nameLower = info.name.lowercased()
            let serviceLower = info.service.lowercased()

            if serviceLower.contains("printer") || serviceLower.contains("ipp") { return .printer }
            if serviceLower.contains("airplay") && (nameLower.contains("tv") || nameLower.contains("apple tv")) { return .smartTV }
            if serviceLower.contains("chromecast") { return .smartTV }
            if serviceLower.contains("spotify") || serviceLower.contains("raop") { return .speaker }
            if serviceLower.contains("homekit") || serviceLower.contains("hap") { return .iotDevice }

            if nameLower.contains("iphone") || nameLower.contains("ipad") || nameLower.contains("android") { return .phone }
            if nameLower.contains("macbook") || nameLower.contains("imac") || nameLower.contains("mac") { return .computer }
            if nameLower.contains("windows") || nameLower.contains("desktop") || nameLower.contains("laptop") { return .computer }
            if nameLower.contains("tv") || nameLower.contains("roku") || nameLower.contains("fire") { return .smartTV }
            if nameLower.contains("xbox") || nameLower.contains("playstation") || nameLower.contains("nintendo") { return .gameConsole }
            if nameLower.contains("echo") || nameLower.contains("homepod") || nameLower.contains("sonos") { return .speaker }
        }

        return .unknown
    }
}
