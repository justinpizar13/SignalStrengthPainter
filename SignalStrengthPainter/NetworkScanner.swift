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
    var openPorts: [UInt16]
    var latencyMs: Double?
    var manufacturer: String?
    let firstSeen: Date
    var isCurrentDevice: Bool
    var isTrusted: Bool

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

    /// SSDP/UPnP results keyed by IP → HTTP headers from M-SEARCH response
    private var ssdpByIP: [String: [String: String]] = [:]

    /// UPnP device descriptions fetched from SSDP LOCATION URLs
    private var upnpDescriptions: [String: (friendlyName: String, manufacturer: String?, modelName: String?)] = [:]

    private static let trustedKey = "trustedDeviceIPs"

    private static let probePorts: [UInt16] = [
        80, 443, 62078, 548, 445, 7000, 8080,
        9100, 631, 554, 8008, 8443, 1883, 3689,
        22, 139, 5353, 8888, 5000, 515, 3000
    ]

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
        bonjourByIP = [:]
        ssdpByIP = [:]
        upnpDescriptions = [:]
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

            scanStatusMessage = "Discovering services (Bonjour + UPnP)..."
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.discoverBonjourServices() }
                group.addTask { await self.discoverSSDPDevices() }
            }

            if !ssdpByIP.isEmpty {
                scanStatusMessage = "Fetching device details..."
                await fetchUPnPDescriptions()
            }

            let subnet = calculateSubnetRange(ip: ip, mask: mask)
            let gatewayIP = inferGatewayIP(localIP: ip)
            let totalHosts = subnet.count
            var scannedCount = 0

            scanStatusMessage = "Scanning \(totalHosts) addresses..."

            let batchSize = 20
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
                                let device = DiscoveredDevice(
                                    id: foundIP,
                                    ipAddress: foundIP,
                                    hostname: nil,
                                    bonjourName: bonjourNames?.first ?? ssdpName,
                                    services: allServices,
                                    deviceType: deviceType,
                                    openPorts: ports,
                                    latencyMs: latency,
                                    firstSeen: Date(),
                                    isCurrentDevice: isSelf,
                                    isTrusted: trustedIPs.contains(foundIP)
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

            scanStatusMessage = "Adding discovered-only devices..."
            addBonjourOnlyDevices(localIP: ip, gatewayIP: gatewayIP)
            addSSDPOnlyDevices(localIP: ip, gatewayIP: gatewayIP)

            scanStatusMessage = "Resolving device names..."
            await resolveHostnames()

            scanStatusMessage = "Identifying devices..."
            await httpFingerprint()

            isScanning = false
            scanStatusMessage = "Scan complete — \(devices.count) device\(devices.count == 1 ? "" : "s") found"
        }
    }

    func stopScan() {
        scanTask?.cancel()
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

    // MARK: - Bonjour Discovery (resolves to IPs)

    private func discoverBonjourServices() async {
        let serviceTypes = [
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

        var collectedEndpoints: [(name: String, service: String, endpoint: NWEndpoint)] = []

        await withTaskGroup(of: [(name: String, service: String, endpoint: NWEndpoint)].self) { group in
            for serviceType in serviceTypes {
                group.addTask { [weak self] in
                    guard self != nil else { return [] }
                    return await self?.browseServiceType(serviceType) ?? []
                }
            }

            for await results in group {
                collectedEndpoints.append(contentsOf: results)
            }
        }

        scanStatusMessage = "Resolving \(collectedEndpoints.count) services..."

        await withTaskGroup(of: (String, String, String)?.self) { group in
            for item in collectedEndpoints {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    guard let ip = await self.resolveServiceEndpoint(item.endpoint) else { return nil }
                    return (ip, item.name, item.service)
                }
            }

            for await result in group {
                if let (ip, name, service) = result {
                    var entries = bonjourByIP[ip] ?? []
                    if !entries.contains(where: { $0.name == name && $0.service == service }) {
                        entries.append((name: name, service: service))
                    }
                    bonjourByIP[ip] = entries
                }
            }
        }
    }

    private func browseServiceType(_ serviceType: String) async -> [(name: String, service: String, endpoint: NWEndpoint)] {
        await withCheckedContinuation { continuation in
            var results: [(name: String, service: String, endpoint: NWEndpoint)] = []
            let lock = NSLock()
            var hasResumed = false

            let params = NWParameters()
            params.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)

            browser.browseResultsChangedHandler = { browseResults, _ in
                lock.lock()
                for result in browseResults {
                    if case let .service(name, type, _, _) = result.endpoint {
                        let friendly = Self.friendlyServiceName(type)
                        if !results.contains(where: { $0.endpoint == result.endpoint }) {
                            results.append((name: name, service: friendly, endpoint: result.endpoint))
                        }
                    }
                }
                lock.unlock()
            }

            browser.stateUpdateHandler = { _ in }
            browser.start(queue: DispatchQueue.global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                browser.cancel()
                lock.lock()
                guard !hasResumed else { lock.unlock(); return }
                hasResumed = true
                let snapshot = results
                lock.unlock()
                continuation.resume(returning: snapshot)
            }
        }
    }

    private func resolveServiceEndpoint(_ endpoint: NWEndpoint) async -> String? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(to: endpoint, using: .tcp)
            var hasResumed = false
            let lock = NSLock()

            func extractIPv4() -> String? {
                guard let path = connection.currentPath,
                      let remoteEndpoint = path.remoteEndpoint,
                      case let .hostPort(host, _) = remoteEndpoint else { return nil }
                if case .ipv4(let addr) = host { return "\(addr)" }
                return nil
            }

            func finish(_ value: String?) {
                lock.lock()
                guard !hasResumed else { lock.unlock(); return }
                hasResumed = true
                lock.unlock()
                connection.cancel()
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(extractIPv4())
                case .failed:
                    finish(extractIPv4())
                case .waiting:
                    finish(extractIPv4())
                case .cancelled:
                    break
                default:
                    break
                }
            }

            probeQueue.asyncAfter(deadline: .now() + 2.0) {
                finish(extractIPv4())
            }

            connection.start(queue: probeQueue)
        }
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
            let device = DiscoveredDevice(
                id: ip,
                ipAddress: ip,
                hostname: nil,
                bonjourName: bonjourNames.first ?? ssdpName,
                services: allServices,
                deviceType: deviceType,
                openPorts: [],
                latencyMs: nil,
                firstSeen: Date(),
                isCurrentDevice: isSelf,
                isTrusted: trustedIPs.contains(ip)
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
            let device = DiscoveredDevice(
                id: ip,
                ipAddress: ip,
                hostname: nil,
                bonjourName: ssdpName,
                services: [serviceHint],
                deviceType: deviceType,
                openPorts: [],
                latencyMs: nil,
                firstSeen: Date(),
                isCurrentDevice: isSelf,
                isTrusted: trustedIPs.contains(ip)
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
            var hasResumed = false
            let lock = NSLock()

            func finish(_ value: Double?) {
                lock.lock()
                guard !hasResumed else { lock.unlock(); return }
                hasResumed = true
                lock.unlock()
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
