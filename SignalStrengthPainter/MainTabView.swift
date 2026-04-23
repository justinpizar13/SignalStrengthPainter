import SwiftUI

struct MainTabView: View {
    // Pro entitlement is derived from `Transaction.currentEntitlements`
    // inside `ProStore` — there is no `@AppStorage("isProUser")` flag that
    // a jailbroken user could flip to unlock Pro without paying.
    @StateObject private var store = ProStore()
    @State private var selectedTab: Tab = .speed

    enum Tab: Int {
        case speed, survey, signal, devices, pro
    }

    var body: some View {
        tabContent
            .safeAreaInset(edge: .top, spacing: 0) {
                // A failed renewal doesn't yank Pro immediately — StoreKit
                // keeps the entitlement alive through the billing-retry
                // window, and `ProStore` mirrors that window into
                // `gracePeriodExpiration`. Surface it as a dismissible
                // banner so users can update their payment method before
                // the grace period lapses, without losing features mid-use.
                if let expiry = store.gracePeriodExpiration {
                    GracePeriodBanner(expiresAt: expiry)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: store.gracePeriodExpiration)
    }

    @ViewBuilder
    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            DashboardView(onStartSurvey: { selectedTab = .survey })
                .tabItem {
                    Image(systemName: "speedometer")
                    Text("Speed")
                }
                .tag(Tab.speed)

            SurveyProGate(store: store)
                .tabItem {
                    Image(systemName: "map.fill")
                    Text("Survey")
                }
                .tag(Tab.survey)

            SignalDetailView(store: store)
                .tabItem {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Signal")
                }
                .tag(Tab.signal)

            DeviceDiscoveryView()
                .tabItem {
                    Image(systemName: "laptopcomputer.and.iphone")
                    Text("Devices")
                }
                .tag(Tab.devices)

            // The Pro tab disappears once the user has an active
            // entitlement — they've already paid, so the upsell is noise.
            if showProTab {
                PaywallView(
                    store: store,
                    isPresented: Binding(
                        get: { selectedTab == .pro },
                        set: { newValue in
                            if !newValue { selectedTab = .speed }
                        }
                    )
                )
                .tabItem {
                    Image(systemName: "crown.fill")
                    Text("Pro")
                }
                .tag(Tab.pro)
            }
        }
        .tint(.blue)
        .onChange(of: store.isProUser) { _, newValue in
            if newValue && selectedTab == .pro {
                selectedTab = .speed
            }
        }
    }

    private var showProTab: Bool {
        !store.isProUser
    }

}

// MARK: - Grace Period Banner

/// Shown while StoreKit is in a billing-retry / grace period. Apple's
/// renewal machinery will re-attempt the charge over several days; if
/// we yanked Pro immediately the user would churn over a transient
/// card decline. Instead, we keep `isProUser` true and render this
/// banner so they can fix payment in Settings before the window closes.
struct GracePeriodBanner: View {
    @Environment(\.theme) private var theme
    let expiresAt: Date

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.28))
            VStack(alignment: .leading, spacing: 2) {
                Text("We couldn't process your renewal")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text("Update your payment method by \(Self.formatter.string(from: expiresAt)) to keep Pro features.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            // Deep-link to the system subscription-management sheet
            // rather than rolling our own — iOS already handles payment
            // updates there and keeps the flow trusted.
            Button {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Fix")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.blue))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(red: 0.98, green: 0.78, blue: 0.28).opacity(0.12)
                .overlay(
                    Rectangle()
                        .fill(Color(red: 0.98, green: 0.78, blue: 0.28).opacity(0.3))
                        .frame(height: 0.5),
                    alignment: .bottom
                )
        )
    }
}

// MARK: - Appearance Toggle

struct AppearanceToggle: View {
    @AppStorage("appearanceMode") private var modeRaw: Int = AppearanceMode.system.rawValue
    @Environment(\.theme) private var theme

    private var mode: AppearanceMode {
        AppearanceMode(rawValue: modeRaw) ?? .system
    }

    var body: some View {
        Menu {
            ForEach([AppearanceMode.system, .light, .dark], id: \.rawValue) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        modeRaw = option.rawValue
                    }
                } label: {
                    Label(option.label, systemImage: option.icon)
                }
            }
        } label: {
            Image(systemName: mode.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 32, height: 32)
                .background(theme.cardFill)
                .clipShape(Circle())
                .overlay(Circle().stroke(theme.cardStroke, lineWidth: 1))
        }
    }
}

// MARK: - Signal Detail Tab

struct SignalDetailView: View {
    @ObservedObject var store: ProStore
    @Environment(\.theme) private var theme
    @State private var latestLatencyMs: Double?
    @State private var animateRings = false
    @State private var isMeasuring = false
    @State private var showAssistant = false
    // "Signal Strength" is framed around Wi-Fi — on cellular the latency
    // probe still works, but the Wi-Fi-specific copy ("Current WiFi
    // connection quality", improvement tips, etc.) is misleading. Show a
    // banner so the user understands what's being measured.
    @ObservedObject private var networkMonitor = NetworkInterfaceMonitor.shared

    private let probe = LatencyProbe()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                signalHeader
                    .padding(.top, 20)

                if !networkMonitor.status.isWiFi {
                    signalConnectivityBanner
                        .padding(.top, 16)
                        .padding(.horizontal, 20)
                }

                signalVisualization
                    .padding(.top, 32)

                qualityCard
                    .padding(.top, 28)
                    .padding(.horizontal, 20)

                refreshButton
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                metricsGrid
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                assistantCTA
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                tipsSection
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .sheet(isPresented: $showAssistant) {
            WiFiAssistantView(store: store)
                .withAppTheme()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animateRings = true
            }
            measureSignal()
        }
    }

    private var assistantCTA: some View {
        Button {
            showAssistant = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 46, height: 46)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.30), lineWidth: 1)
                        )
                    KlausMascotView(size: 46, mode: .portrait)
                }
                .frame(width: 46, height: 46)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat with Klaus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Your Wi-Fi sidekick, always on call")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.8))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var signalHeader: some View {
        VStack(spacing: 6) {
            AppLogoView(size: 44)
            Text("Signal Strength")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(theme.primaryText)
            Text(signalHeaderSubtitle)
                .font(.system(size: 15))
                .foregroundStyle(theme.tertiaryText)
        }
    }

    private var signalHeaderSubtitle: String {
        switch networkMonitor.status {
        case .wifi: return "Current Wi-Fi connection quality"
        case .cellular: return "Measuring your cellular connection"
        case .wired: return "Current wired connection quality"
        case .offline: return "No network connection"
        case .unknown: return "Checking your connection"
        }
    }

    /// Matches the banner used in Device Discovery and the Speed tab so
    /// the copy about cellular vs. Wi-Fi reads consistently across the
    /// app. Placed just under the header so it's visible before the user
    /// tries to interpret any of the signal numbers.
    private var signalConnectivityBanner: some View {
        let (icon, title, message, tint) = signalBannerContent
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

    private var signalBannerContent: (String, String, String, Color) {
        switch networkMonitor.status {
        case .cellular:
            return (
                "antenna.radiowaves.left.and.right",
                "On Cellular, Not Wi-Fi",
                "Signal quality below is measured over your cellular connection. The Wi-Fi tips won't apply until you reconnect to Wi-Fi.",
                Color(red: 0.98, green: 0.78, blue: 0.28)
            )
        case .offline:
            return (
                "wifi.slash",
                "No Connection",
                "Connect to Wi-Fi to measure your signal quality.",
                Color(red: 0.98, green: 0.39, blue: 0.34)
            )
        case .wired:
            return (
                "cable.connector",
                "Wired Connection",
                "You're on a wired connection. Wi-Fi signal metrics don't apply.",
                .blue
            )
        case .unknown:
            return (
                "questionmark.circle",
                "Checking Connection",
                "Figuring out which network you're using.",
                .gray
            )
        case .wifi:
            return ("wifi", "", "", .blue)
        }
    }

    private var signalVisualization: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(
                        ringColor.opacity(animateRings ? 0.25 - Double(ring) * 0.07 : 0.1),
                        lineWidth: 2.5
                    )
                    .frame(
                        width: CGFloat(100 + ring * 50),
                        height: CGFloat(100 + ring * 50)
                    )
                    .scaleEffect(animateRings ? 1.05 : 0.95)
            }

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [ringColor.opacity(0.3), ringColor.opacity(0.05)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 45
                        )
                    )
                    .frame(width: 90, height: 90)

                Image(systemName: "wifi")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(ringColor)
            }
        }
        .frame(height: 220)
    }

    private var qualityCard: some View {
        VStack(spacing: 14) {
            if let ms = latestLatencyMs {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(qualityLabel)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(ringColor)
                        Text("Based on network latency")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.tertiaryText)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(ms))")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                        Text("ms latency")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
            } else {
                HStack {
                    ProgressView()
                        .tint(theme.tertiaryText)
                    Text("Measuring signal quality...")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.tertiaryText)
                        .padding(.leading, 8)
                    Spacer()
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(ringColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var metricsGrid: some View {
        HStack(spacing: 12) {
            metricTile(
                icon: "bolt.fill",
                label: "Latency",
                value: latestLatencyMs.map { "\(Int($0)) ms" } ?? "--"
            )
            metricTile(
                icon: "checkmark.shield.fill",
                label: "Status",
                value: latestLatencyMs != nil ? "Connected" : "Testing"
            )
            metricTile(
                icon: "chart.line.uptrend.xyaxis",
                label: "Quality",
                value: qualityLabel
            )
        }
    }

    private func metricTile(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.blue)

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
    }

    private var refreshButton: some View {
        Button {
            measureSignal()
        } label: {
            HStack(spacing: 8) {
                if isMeasuring {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                    Text("Measuring...")
                } else {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh Signal")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(theme.buttonText)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .disabled(isMeasuring)
        .opacity(isMeasuring ? 0.7 : 1)
    }

    private var isExcellent: Bool {
        guard let ms = latestLatencyMs else { return false }
        return ms < 50
    }

    @ViewBuilder
    private var tipsSection: some View {
        if isExcellent {
            excellentSignalCard
        } else {
            improveSignalCard
        }
    }

    private var excellentSignalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(red: 0.25, green: 0.86, blue: 0.43))
                Text("Signal is Great")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.primaryText)
            }

            tipRow(icon: "wifi", text: "Your connection latency is excellent — no action needed")
            tipRow(icon: "play.tv", text: "You're good for 4K streaming, gaming, and video calls")
            tipRow(icon: "map.fill", text: "Use the Survey tab to verify coverage across your whole space")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(red: 0.25, green: 0.86, blue: 0.43).opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var improveSignalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Improve Your Signal")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.primaryText)

            tipRow(icon: "location.fill", text: "Move closer to your router for a stronger connection")
            tipRow(icon: "map.fill", text: "Use the Survey tab to map dead zones in your space")
            tipRow(icon: "arrow.triangle.2.circlepath", text: "Restart your router if latency stays high")
            tipRow(icon: "wifi.router", text: "Position your router centrally for even coverage")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.blue)
                .frame(width: 20)

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var qualityLabel: String {
        guard let ms = latestLatencyMs else { return "--" }
        if ms < 50 { return "Excellent" }
        if ms <= 150 { return "Good" }
        return "Poor"
    }

    private var ringColor: Color {
        guard let ms = latestLatencyMs else { return .blue }
        if ms < 50 { return Color(red: 0.25, green: 0.86, blue: 0.43) }
        if ms <= 150 { return Color(red: 0.98, green: 0.78, blue: 0.28) }
        return Color(red: 0.98, green: 0.39, blue: 0.34)
    }

    private func measureSignal() {
        isMeasuring = true
        probe.measureLatency { value in
            latestLatencyMs = value
            isMeasuring = false
        }
    }
}

#Preview {
    MainTabView()
        .withAppTheme()
}
