import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DashboardView: View {
    var onStartSurvey: (() -> Void)?

    @Environment(\.theme) private var theme
    @StateObject private var speedTest = SpeedTestManager()
    // Used to show a small "Testing over cellular" badge when the user
    // isn't on Wi-Fi. Speed tests still work over cellular but the user
    // needs to know the numbers aren't measuring their Wi-Fi.
    @ObservedObject private var networkMonitor = NetworkInterfaceMonitor.shared
    // Drives the live ISP → Router → Device topology card at the top
    // of the tab. Before this existed, the card was a purely static
    // graphic with hardcoded labels ("Available", "192.168.0.1",
    // "Your iPhone / Connected") that never reflected the actual
    // state of the network.
    @StateObject private var topology = NetworkTopologyMonitor()

    @State private var serviceLatencies: [String: Double] = [:]
    // Drives the hamburger-menu sheet in the top-left of the Wi-Fi
    // header. Kept as a simple boolean because the sheet is a single
    // static "Getting Started" screen — no navigation state to preserve.
    @State private var showAbout = false
    // Persisted first-launch flag so we auto-present "Getting Started"
    // exactly once per install. Stored in `UserDefaults` via
    // `@AppStorage` because it's UX state, not a security-sensitive
    // entitlement — the worst-case failure is a returning user seeing
    // the sheet again, which is harmless.
    @AppStorage("hasSeenGettingStarted") private var hasSeenGettingStarted: Bool = false

    private let probe = LatencyProbe()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                wifiHeader
                    .padding(.top, 8)

                if !networkMonitor.status.isWiFi {
                    connectionStatusBanner
                        .padding(.top, 12)
                        .padding(.horizontal, 20)
                }

                topologyCard
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                sectionHeader("Speed Test")
                    .padding(.top, 28)
                    .padding(.horizontal, 20)

                speedTestCard
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                speedTestButton
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                if speedTest.phase == .complete {
                    speedReport
                        .padding(.top, 20)
                        .padding(.horizontal, 20)
                }

                sectionHeader("Network Latency")
                    .padding(.top, 28)
                    .padding(.horizontal, 20)

                serviceLatencyGrid
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                surveyCard
                    .padding(.top, 28)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .sheet(isPresented: $showAbout) {
            AboutView()
                .withAppTheme()
        }
        .onAppear {
            topology.start()
            // First launch only: auto-present the "Getting Started"
            // sheet so new users always see the guided intro. The
            // `@AppStorage` flag flips as soon as we show it so this
            // never fires again on this install.
            if !hasSeenGettingStarted {
                hasSeenGettingStarted = true
                showAbout = true
            }
        }
        .onDisappear { topology.stop() }
        .onChange(of: speedTest.phase) { _, newPhase in
            if newPhase == .complete {
                testServiceLatencies()
                // After a speed test we also know ping/jitter — trigger
                // a fresh topology read so the card reflects what the
                // user just saw, rather than a ~6s-old sample.
                Task { await topology.refresh() }
            }
        }
    }

    // MARK: - Connection Status Banner

    /// Surfaces the active connection type whenever the user isn't on
    /// Wi-Fi. Speed tests, latency probes, and the topology diagram all
    /// assume Wi-Fi by default; without this banner a cellular result
    /// looks indistinguishable from a Wi-Fi result.
    private var connectionStatusBanner: some View {
        let (icon, title, message, tint) = connectionBannerContent
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var connectionBannerContent: (String, String, String, Color) {
        switch networkMonitor.status {
        case .cellular:
            return (
                "antenna.radiowaves.left.and.right",
                "Testing on Cellular",
                "You're off Wi-Fi — these results reflect your cellular connection, not your home network.",
                Color(red: 0.98, green: 0.78, blue: 0.28)
            )
        case .offline:
            return (
                "wifi.slash",
                "No Network",
                "Connect to Wi-Fi or cellular to run network tests.",
                Color(red: 0.98, green: 0.39, blue: 0.34)
            )
        case .wired:
            return (
                "cable.connector",
                "Wired Connection",
                "Measurements reflect your wired connection rather than Wi-Fi.",
                .blue
            )
        case .unknown:
            return (
                "questionmark.circle",
                "Checking Connection",
                "Still figuring out your current network.",
                .gray
            )
        case .wifi:
            return ("wifi", "", "", .blue)
        }
    }

    // MARK: - WiFi Header

    private var wifiHeader: some View {
        // Three-zone layout: hamburger (menu) on the left, centered
        // logo/title, appearance toggle on the right. The centered
        // brand stays optically centered regardless of what's on the
        // sides because it's drawn in its own ZStack layer rather
        // than inside the HStack.
        ZStack {
            HStack(spacing: 8) {
                AppLogoView(size: 44)
                Text("Wi-Fi Buddy")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.primaryText)
            }

            HStack {
                menuButton
                Spacer()
                AppearanceToggle()
            }
        }
        .padding(.horizontal, 20)
    }

    /// Hamburger-style menu button. Opens the Getting Started sheet so
    /// new users have a single obvious entry point for "what does this
    /// app do / how do I use it?" without us cramming help text onto
    /// every screen.
    private var menuButton: some View {
        Button {
            showAbout = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 32, height: 32)
                .background(theme.cardFill)
                .clipShape(Circle())
                .overlay(Circle().stroke(theme.cardStroke, lineWidth: 1))
        }
        .accessibilityLabel("Getting started")
    }

    // MARK: - Network Topology
    //
    // Live "ISP → Router → Your Device" diagram. Every piece of this
    // card is driven by `NetworkTopologyMonitor`:
    //
    // - ISP node:   status + latency come from a live TCP ping to
    //               8.8.8.8:53 (same probe used throughout the app).
    // - Router node: IP is inferred from the device's actual `en0`
    //               address and the latency badge is a live TCP
    //               ping to the gateway.
    // - Device node: local IPv4 + current interface (Wi-Fi /
    //               Cellular / Offline) come from the OS.
    //
    // The connectors animate when the hop is actually carrying
    // traffic and fall back to a muted static line when it isn't —
    // which is the part that was missing when the card looked like a
    // logo.

    private var topologyCard: some View {
        HStack(spacing: 0) {
            topologyNode(
                icon: "globe",
                iconColor: colorForHealth(topology.wanHealth),
                label: "ISP",
                detail: ispDetailText,
                status: ispStatusBadge
            )

            topologyConnector(health: topology.wanHealth)

            topologyNode(
                icon: "wifi.router",
                iconColor: colorForHealth(topology.lanHealth),
                label: "Router",
                detail: topology.gatewayIP ?? "—",
                status: gatewayStatusBadge
            )

            topologyConnector(health: topology.lanHealth)

            topologyNode(
                icon: deviceIconName,
                iconColor: deviceIconColor,
                label: topology.deviceLabel,
                detail: deviceDetailText,
                status: deviceStatusBadge
            )
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.subtle, lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.25), value: topology.gatewayLatencyMs)
        .animation(.easeInOut(duration: 0.25), value: topology.ispLatencyMs)
    }

    // MARK: - Topology copy helpers

    private var ispDetailText: String {
        switch topology.wanHealth {
        case .good, .fair, .poor:
            if let ms = topology.ispLatencyMs {
                return "\(Int(ms.rounded())) ms"
            }
            return "Internet"
        case .offline:
            return networkMonitor.status.isOnline ? "No route" : "Offline"
        case .unknown:
            return "Checking…"
        }
    }

    private var ispStatusBadge: (String, Color)? {
        switch topology.wanHealth {
        case .good: return ("Online", statusGreen)
        case .fair: return ("Slow", statusAmber)
        case .poor: return ("Degraded", statusRed)
        case .offline: return ("Unreachable", statusRed)
        case .unknown: return nil
        }
    }

    private var gatewayStatusBadge: (String, Color)? {
        switch topology.lanHealth {
        case .good: return (latencyBadge(topology.gatewayLatencyMs), statusGreen)
        case .fair: return (latencyBadge(topology.gatewayLatencyMs), statusAmber)
        case .poor: return (latencyBadge(topology.gatewayLatencyMs), statusRed)
        case .offline: return ("No reply", statusRed)
        case .unknown:
            // On cellular there's no local gateway to ping — show a
            // neutral hint instead of a red "unreachable" badge that
            // would misrepresent the situation.
            if networkMonitor.status == .cellular { return ("N/A", theme.tertiaryText) }
            return nil
        }
    }

    private var deviceDetailText: String {
        topology.localIP ?? "No IP"
    }

    private var deviceStatusBadge: (String, Color)? {
        switch networkMonitor.status {
        case .wifi: return ("Wi-Fi", statusGreen)
        case .wired: return ("Wired", .blue)
        case .cellular: return ("Cellular", statusAmber)
        case .offline: return ("Offline", statusRed)
        case .unknown: return ("Checking…", theme.tertiaryText)
        }
    }

    private var deviceIconName: String {
        #if canImport(UIKit)
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return "ipad"
        case .mac: return "laptopcomputer"
        default: return "iphone"
        }
        #else
        return "iphone"
        #endif
    }

    private var deviceIconColor: Color {
        switch networkMonitor.status {
        case .wifi, .wired: return statusGreen
        case .cellular: return statusAmber
        case .offline: return statusRed
        case .unknown: return theme.secondaryText
        }
    }

    private func latencyBadge(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        return "\(Int(ms.rounded())) ms"
    }

    // Semantic status colors are identical across the app; pulling
    // them from the same constants keeps the topology card in sync
    // with the service-latency tiles and speed report.
    private var statusGreen: Color { Color(red: 0.25, green: 0.86, blue: 0.43) }
    private var statusAmber: Color { Color(red: 0.98, green: 0.78, blue: 0.28) }
    private var statusRed:   Color { Color(red: 0.98, green: 0.39, blue: 0.34) }

    private func colorForHealth(_ health: NetworkTopologyMonitor.LinkHealth) -> Color {
        switch health {
        case .good: return statusGreen
        case .fair: return statusAmber
        case .poor, .offline: return statusRed
        case .unknown: return theme.secondaryText
        }
    }

    private func topologyNode(
        icon: String,
        iconColor: Color,
        label: String,
        detail: String,
        status: (String, Color)? = nil
    ) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(theme.subtle)
                    .frame(width: 50, height: 50)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
            }

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)

            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(1)
                .monospacedDigit()

            if let status {
                Text(status.0)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(status.1)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Connector between two topology nodes. Color and whether it
    /// animates are both driven by the link's measured health, so a
    /// healthy hop shows a subtle flow of packets while a broken hop
    /// sits as a muted static line.
    private func topologyConnector(health: NetworkTopologyMonitor.LinkHealth) -> some View {
        let tint = colorForHealth(health)
        return Rectangle()
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.55), tint.opacity(0.15)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 2)
            .overlay(
                TopologyPacketFlow(color: tint, isActive: health.isCarryingTraffic)
            )
            .frame(width: 36)
            .offset(y: -12)
    }

    // MARK: - Section Headers

    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.primaryText)
            Spacer()
            if let trailing {
                Button(trailing) {}
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Speed Report

    private var speedReport: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(overallGradeColor)
                Text("Your Wi-Fi Report")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text(overallGradeLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(overallGradeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(overallGradeColor.opacity(0.15)))
            }

            Text(overallSummary)
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(activityRatings, id: \.name) { activity in
                    reportActivityRow(activity)
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(overallGradeColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func reportActivityRow(_ activity: ActivityRating) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(activity.color.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: activity.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(activity.color)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(activity.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }

            Spacer()

            Text(activity.verdict)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(activity.color)
        }
    }

    // MARK: - Report Data Model

    private struct ActivityRating: Identifiable {
        var id: String { name }
        let name: String
        let icon: String
        let detail: String
        let verdict: String
        let color: Color
    }

    private var overallGradeLabel: String {
        let dl = speedTest.downloadSpeed
        if dl >= 100 { return "Excellent" }
        if dl >= 50 { return "Great" }
        if dl >= 25 { return "Good" }
        if dl >= 10 { return "Fair" }
        return "Poor"
    }

    private var overallGradeColor: Color {
        let dl = speedTest.downloadSpeed
        if dl >= 100 { return Color(red: 0.25, green: 0.86, blue: 0.43) }
        if dl >= 50 { return Color(red: 0.25, green: 0.86, blue: 0.43) }
        if dl >= 25 { return .cyan }
        if dl >= 10 { return Color(red: 0.98, green: 0.78, blue: 0.28) }
        return Color(red: 0.98, green: 0.39, blue: 0.34)
    }

    private var overallSummary: String {
        let dl = speedTest.downloadSpeed
        let ping = speedTest.pingMs

        if dl >= 100 && ping < 30 {
            return "Your connection is blazing fast. You can do virtually anything — stream 4K on multiple devices, game competitively, and run video calls without a hiccup."
        } else if dl >= 50 {
            return "Solid speeds for most households. 4K streaming, online gaming, and working from home should all run smoothly."
        } else if dl >= 25 {
            return "Decent for everyday use. HD streaming and video calls will work fine, but 4K on multiple devices may buffer."
        } else if dl >= 10 {
            return "Enough for basics like browsing, email, and SD streaming, but you may notice slowdowns with video calls or larger downloads."
        } else if dl >= 3 {
            return "Your connection is on the slower side. Web browsing works, but streaming and video calls may struggle."
        } else {
            return "Very slow connection. You may have trouble with basic tasks. Consider restarting your router or moving closer to it."
        }
    }

    private var activityRatings: [ActivityRating] {
        let dl = speedTest.downloadSpeed
        let ul = speedTest.uploadSpeed
        let ping = speedTest.pingMs

        return [
            ActivityRating(
                name: "Netflix / Streaming",
                icon: "play.tv",
                detail: dl >= 25 ? "4K Ultra HD ready" : dl >= 5 ? "HD streaming OK" : "May buffer often",
                verdict: dl >= 25 ? "Great" : dl >= 5 ? "OK" : "Poor",
                color: dl >= 25 ? Color(red: 0.25, green: 0.86, blue: 0.43) : dl >= 5 ? Color(red: 0.98, green: 0.78, blue: 0.28) : Color(red: 0.98, green: 0.39, blue: 0.34)
            ),
            ActivityRating(
                name: "Online Gaming",
                icon: "gamecontroller.fill",
                detail: ping < 30 ? "Low latency, competitive ready" : ping < 80 ? "Playable, some lag possible" : "High lag, expect delays",
                verdict: ping < 30 ? "Great" : ping < 80 ? "OK" : "Poor",
                color: ping < 30 ? Color(red: 0.25, green: 0.86, blue: 0.43) : ping < 80 ? Color(red: 0.98, green: 0.78, blue: 0.28) : Color(red: 0.98, green: 0.39, blue: 0.34)
            ),
            ActivityRating(
                name: "Video Calls (Zoom/Teams)",
                icon: "video.fill",
                detail: dl >= 10 && ul >= 3 ? "HD calls, no issues" : dl >= 3 && ul >= 1.5 ? "Standard quality" : "Choppy or drops likely",
                verdict: dl >= 10 && ul >= 3 ? "Great" : dl >= 3 && ul >= 1.5 ? "OK" : "Poor",
                color: dl >= 10 && ul >= 3 ? Color(red: 0.25, green: 0.86, blue: 0.43) : dl >= 3 && ul >= 1.5 ? Color(red: 0.98, green: 0.78, blue: 0.28) : Color(red: 0.98, green: 0.39, blue: 0.34)
            ),
            ActivityRating(
                name: "Home Office",
                icon: "laptopcomputer",
                detail: dl >= 25 && ul >= 5 ? "Cloud apps & big files, no sweat" : dl >= 10 ? "Fine for email & docs" : "Slow uploads and syncs",
                verdict: dl >= 25 && ul >= 5 ? "Great" : dl >= 10 ? "OK" : "Poor",
                color: dl >= 25 && ul >= 5 ? Color(red: 0.25, green: 0.86, blue: 0.43) : dl >= 10 ? Color(red: 0.98, green: 0.78, blue: 0.28) : Color(red: 0.98, green: 0.39, blue: 0.34)
            ),
            ActivityRating(
                name: "Social Media & Browsing",
                icon: "safari",
                detail: dl >= 5 ? "Fast page loads & smooth scrolling" : dl >= 1 ? "Usable but images load slowly" : "Frustratingly slow",
                verdict: dl >= 5 ? "Great" : dl >= 1 ? "OK" : "Poor",
                color: dl >= 5 ? Color(red: 0.25, green: 0.86, blue: 0.43) : dl >= 1 ? Color(red: 0.98, green: 0.78, blue: 0.28) : Color(red: 0.98, green: 0.39, blue: 0.34)
            ),
        ]
    }

    // MARK: - Service Latency Grid

    private var serviceLatencyGrid: some View {
        // The Gateway tile uses the *actual* inferred gateway IP from
        // the topology monitor so the reading matches the router row
        // in the topology card. Falling back to 192.168.0.1 only
        // happens when we can't read the local IP at all (simulator,
        // no network).
        let gatewayHost = topology.gatewayIP ?? "192.168.0.1"
        return HStack(spacing: 10) {
            serviceLatencyTile(label: "Google", host: "8.8.8.8", icon: "magnifyingglass", iconBg: .blue)
            serviceLatencyTile(label: "Cloudflare", host: "1.1.1.1", icon: "shield.fill", iconBg: .orange)
            serviceLatencyTile(label: "OpenDNS", host: "208.67.222.222", icon: "server.rack", iconBg: .purple)
            serviceLatencyTile(label: "Gateway", host: gatewayHost, icon: "wifi.router", iconBg: .green)
        }
    }

    private func serviceLatencyTile(label: String, host: String, icon: String, iconBg: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(iconBg.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(iconBg)
            }

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(1)

            if let ms = serviceLatencies[host] {
                Text("\(Int(ms))")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
            } else {
                Text("--")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.quaternaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
    }

    // MARK: - Survey Card

    private var surveyCard: some View {
        Button {
            onStartSurvey?()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "map.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Map Your WiFi Coverage")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text("Walk your space to paint signal quality onto a floor plan using AR")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.quaternaryText)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(theme.subtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Speed Test Card

    private var speedTestCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if speedTest.isTesting {
                activeSpeedTestContent
            } else if speedTest.phase == .complete {
                completedSpeedTestContent
            } else {
                emptySpeedTestContent
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.subtle, lineWidth: 1)
                )
        )
    }

    private var emptySpeedTestContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 36))
                .foregroundStyle(theme.quaternaryText)
            Text("No speed test results yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
            Text("Tap the button below to measure\nyour download and upload speeds")
                .font(.system(size: 13))
                .foregroundStyle(theme.quaternaryText)
                .multilineTextAlignment(.center)

            if let info = speedTest.serverInfo {
                serverInfoRow(info)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var activeSpeedTestContent: some View {
        VStack(spacing: 16) {
            HStack {
                speedTestPhaseIcon
                Text(speedTestPhaseLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(speedTestPhaseColor)
                Spacer()
            }

            if speedTest.phase == .selectingServer {
                serverSelectingView
            } else if speedTest.phase == .latency {
                VStack(spacing: 8) {
                    if speedTest.pingMs > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(speedTest.pingMs))")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.primaryText)
                            Text("ms")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(theme.tertiaryText)
                        }
                    } else {
                        ProgressView()
                            .tint(theme.primaryText)
                            .scaleEffect(1.2)
                            .padding(.vertical, 12)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatSpeed(speedTest.currentSpeed))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.2), value: formatSpeed(speedTest.currentSpeed))
                        Text("Mbps")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)

                    if speedTest.speedSamples.count > 1 {
                        speedSparkline
                            .frame(height: 60)
                    }
                }
            }

            speedTestPhaseIndicator

            ProgressView(value: speedTest.progress)
                .tint(speedTestPhaseColor)

            if let info = speedTest.serverInfo, speedTest.phase != .selectingServer {
                serverInfoRow(info)
            }
        }
    }

    private var completedSpeedTestContent: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Internet \u{2192} Your iPhone")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                if let date = speedTest.testDate {
                    Text(formattedTime(date))
                        .font(.system(size: 13))
                        .foregroundStyle(theme.tertiaryText)
                }
            }

            HStack(spacing: 12) {
                speedResultTile(
                    direction: "Download",
                    icon: "arrow.down",
                    speed: speedTest.downloadSpeed,
                    color: .cyan
                )
                speedResultTile(
                    direction: "Upload",
                    icon: "arrow.up",
                    speed: speedTest.uploadSpeed,
                    color: Color(red: 0.25, green: 0.86, blue: 0.43)
                )
            }

            HStack(spacing: 24) {
                speedStatBadge(label: "Ping", value: "\(Int(speedTest.pingMs)) ms")
                speedStatBadge(label: "Jitter", value: "\(Int(speedTest.jitterMs)) ms")
                Spacer()
            }

            if let info = speedTest.serverInfo {
                serverInfoRow(info)
            }
        }
    }

    // MARK: - Server Info UI

    /// Placeholder content shown during the short server-selection phase
    /// at the top of each run. Once /meta resolves, the row swaps in under
    /// the progress bar below.
    private var serverSelectingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(theme.primaryText)
                .scaleEffect(1.1)
            Text("Finding the nearest test server…")
                .font(.system(size: 13))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    /// Small info strip shown above and after a speed test run so the
    /// user can verify that Cloudflare's Anycast routed their traffic to
    /// a reasonable POP. If the detected distance is > 500 mi we surface a
    /// subtle amber warning — that's the usual fingerprint of an ISP
    /// routing problem (e.g. AZ traffic landing in DFW).
    private func serverInfoRow(_ info: SpeedTestServerInfo) -> some View {
        let suboptimal = info.isLikelySuboptimal
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(suboptimal ? Color(red: 0.98, green: 0.78, blue: 0.28) : theme.tertiaryText)
                Text(info.displayLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let distance = info.distanceText {
                    Text(distance)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                }
            }

            if suboptimal {
                Text("Your ISP is routing this test far from you — real speeds to nearby services may be higher.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.28))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let isp = info.clientISP {
                Text("Your ISP: \(isp)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.quaternaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    (suboptimal ? Color(red: 0.98, green: 0.78, blue: 0.28) : Color.blue)
                        .opacity(0.08)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            (suboptimal ? Color(red: 0.98, green: 0.78, blue: 0.28) : Color.blue)
                                .opacity(0.18),
                            lineWidth: 1
                        )
                )
        )
    }

    private func speedResultTile(direction: String, icon: String, speed: Double, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                Text(direction)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formatSpeed(speed))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                Text("Mbps")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(color.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func speedStatBadge(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(theme.tertiaryText)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
        }
    }

    // MARK: - Speed Test Sparkline

    private var speedSparkline: some View {
        Canvas { context, size in
            let samples = speedTest.speedSamples
            guard samples.count > 1 else { return }

            let maxVal = (samples.max() ?? 1) * 1.1
            guard maxVal > 0 else { return }
            let stepX = size.width / CGFloat(samples.count - 1)

            var linePath = Path()
            var fillPath = Path()

            for (i, val) in samples.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height - (val / maxVal) * size.height

                if i == 0 {
                    linePath.move(to: CGPoint(x: x, y: y))
                    fillPath.move(to: CGPoint(x: 0, y: size.height))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                } else {
                    let prevX = CGFloat(i - 1) * stepX
                    let prevVal = samples[i - 1]
                    let prevY = size.height - (prevVal / maxVal) * size.height
                    let midX = (prevX + x) / 2
                    linePath.addCurve(
                        to: CGPoint(x: x, y: y),
                        control1: CGPoint(x: midX, y: prevY),
                        control2: CGPoint(x: midX, y: y)
                    )
                    fillPath.addCurve(
                        to: CGPoint(x: x, y: y),
                        control1: CGPoint(x: midX, y: prevY),
                        control2: CGPoint(x: midX, y: y)
                    )
                }
            }

            let lastX = CGFloat(samples.count - 1) * stepX
            fillPath.addLine(to: CGPoint(x: lastX, y: size.height))
            fillPath.closeSubpath()

            let isDownload = speedTest.phase == .download
            let baseColor: Color = isDownload ? .cyan : Color(red: 0.25, green: 0.86, blue: 0.43)

            context.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [
                        baseColor.opacity(0.3),
                        baseColor.opacity(0.08),
                        .clear,
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            context.stroke(
                linePath,
                with: .linearGradient(
                    Gradient(colors: [baseColor, baseColor.opacity(0.6)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                lineWidth: 2.5
            )

            if let lastVal = samples.last {
                let lastY = size.height - (lastVal / maxVal) * size.height
                let center = CGPoint(x: lastX, y: lastY)
                let outer = Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
                let inner = Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
                context.fill(outer, with: .color(baseColor.opacity(0.4)))
                context.fill(inner, with: .color(.white))
            }
        }
    }

    // MARK: - Speed Test Phase UI

    private var speedTestPhaseIndicator: some View {
        HStack(spacing: 16) {
            speedTestPhaseStep(
                "Server",
                isActive: speedTest.phase == .selectingServer,
                isDone: speedTest.phase == .latency || speedTest.phase == .download || speedTest.phase == .upload || speedTest.phase == .complete
            )
            speedTestPhaseStep(
                "Ping",
                isActive: speedTest.phase == .latency,
                isDone: speedTest.phase == .download || speedTest.phase == .upload || speedTest.phase == .complete
            )
            speedTestPhaseStep(
                "Download",
                isActive: speedTest.phase == .download,
                isDone: speedTest.phase == .upload || speedTest.phase == .complete
            )
            speedTestPhaseStep(
                "Upload",
                isActive: speedTest.phase == .upload,
                isDone: speedTest.phase == .complete
            )
        }
    }

    private func speedTestPhaseStep(_ label: String, isActive: Bool, isDone: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? speedTestPhaseColor : isDone ? Color(red: 0.25, green: 0.86, blue: 0.43) : theme.quaternaryText)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? theme.primaryText : theme.tertiaryText)
        }
    }

    @ViewBuilder
    private var speedTestPhaseIcon: some View {
        switch speedTest.phase {
        case .selectingServer:
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 14))
                .foregroundStyle(speedTestPhaseColor)
        case .latency:
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 14))
                .foregroundStyle(speedTestPhaseColor)
        case .download:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(speedTestPhaseColor)
        case .upload:
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(speedTestPhaseColor)
        default:
            Image(systemName: "bolt.fill")
                .font(.system(size: 14))
                .foregroundStyle(speedTestPhaseColor)
        }
    }

    private var speedTestPhaseLabel: String {
        switch speedTest.phase {
        case .idle: return ""
        case .selectingServer: return "Finding best server..."
        case .latency: return "Measuring Ping..."
        case .download: return "Downloading..."
        case .upload: return "Uploading..."
        case .complete: return "Complete"
        }
    }

    private var speedTestPhaseColor: Color {
        switch speedTest.phase {
        case .selectingServer: return .blue
        case .latency: return .yellow
        case .download: return .cyan
        case .upload: return Color(red: 0.25, green: 0.86, blue: 0.43)
        case .complete: return Color(red: 0.25, green: 0.86, blue: 0.43)
        default: return .blue
        }
    }

    // MARK: - Speed Test Button

    private var speedTestButton: some View {
        Button {
            if speedTest.isTesting {
                speedTest.cancelTest()
            } else {
                speedTest.startTest()
            }
        } label: {
            HStack(spacing: 8) {
                if speedTest.isTesting {
                    Image(systemName: "stop.fill")
                    Text("Stop Test")
                } else if speedTest.phase == .complete {
                    Image(systemName: "arrow.clockwise")
                    Text("Test Again")
                } else {
                    Image(systemName: "bolt.fill")
                    Text("Start Speed Test")
                }
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(theme.buttonText)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: speedTest.isTesting
                                ? [.red.opacity(0.7), .red.opacity(0.5)]
                                : [.blue, .blue.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
    }

    // MARK: - Speed Formatting

    private func formatSpeed(_ mbps: Double) -> String {
        if mbps >= 100 { return "\(Int(mbps))" }
        if mbps >= 10 { return String(format: "%.1f", mbps) }
        if mbps > 0 { return String(format: "%.2f", mbps) }
        return "0"
    }

    // MARK: - Helpers

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yy, h:mm a"
        return formatter.string(from: date)
    }

    // MARK: - Test Logic

    private func testServiceLatencies() {
        // Public DNS resolvers are fixed; the gateway target tracks
        // whichever IP the topology monitor resolved this session so
        // a user on 10.0.0.x or 192.168.1.x still gets a real reading
        // in the grid instead of a probe fired at 192.168.0.1.
        let gatewayHost = topology.gatewayIP ?? "192.168.0.1"
        let targets: [(String, UInt16)] = [
            ("8.8.8.8", 53),
            ("1.1.1.1", 53),
            ("208.67.222.222", 53),
            (gatewayHost, 80),
        ]

        for (host, port) in targets {
            probe.measureLatency(host: host, port: port) { value in
                if let value {
                    serviceLatencies[host] = value
                }
            }
        }
    }
}

// MARK: - TopologyPacketFlow
//
// Small animated overlay drawn on top of each connector in the
// topology card. When the link is healthy (`isActive == true`) three
// tiny dots slide left-to-right to visualise packets in flight; when
// the link is down they sit still at a muted opacity so the card
// still *looks* connected but clearly isn't communicating.
//
// Using `TimelineView` rather than an SF Symbol `phase` animation
// keeps the flow running smoothly without requiring explicit
// `.animation(...)` on every ancestor, and pauses automatically when
// the view goes off-screen.
private struct TopologyPacketFlow: View {
    let color: Color
    let isActive: Bool

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { context in
                let width = geo.size.width
                // One full sweep every 1.4s; offsetting each dot by a
                // third of the period creates the "train of packets"
                // effect without needing per-dot state.
                let period: TimeInterval = 1.4
                let t = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period

                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        let offset = (t + Double(i) / 3.0).truncatingRemainder(dividingBy: 1.0)
                        Circle()
                            .fill(color.opacity(isActive ? 0.9 : 0.35))
                            .frame(width: 3, height: 3)
                            .position(
                                x: width * offset,
                                y: geo.size.height / 2
                            )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    DashboardView()
        .withAppTheme()
}
