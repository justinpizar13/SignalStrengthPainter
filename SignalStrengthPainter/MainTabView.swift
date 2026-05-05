import SwiftUI

struct MainTabView: View {
    // Pro entitlement is derived from `Transaction.currentEntitlements`
    // inside `ProStore` — there is no `@AppStorage("isProUser")` flag that
    // a jailbroken user could flip to unlock Pro without paying.
    @StateObject private var store = ProStore()
    @StateObject private var updateChecker = UpdateChecker()
    @State private var selectedTab: Tab = .speed

    enum Tab: Int {
        case speed, survey, klaus, devices, pro
    }

    var body: some View {
        tabContent
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
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
                    // App Store version-update prompt. UpdateChecker polls
                    // Apple's iTunes Lookup endpoint once a day and surfaces
                    // a per-version-dismissable banner with a snippet of the
                    // "What's New" copy so users on older builds can see
                    // what they're missing without leaving the app.
                    if updateChecker.shouldShowUpdateBanner,
                       let version = updateChecker.availableVersion {
                        UpdateAvailableBanner(
                            version: version,
                            snippet: updateChecker.releaseNotesSnippet,
                            onUpdate: { updateChecker.openAppStore() },
                            onDismiss: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    updateChecker.dismissUpdate()
                                }
                            }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: store.gracePeriodExpiration)
            .animation(.easeInOut(duration: 0.25), value: updateChecker.availableVersion)
            .task {
                await updateChecker.checkForUpdate()
            }
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

            WiFiAssistantView(store: store)
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("Klaus")
                }
                .tag(Tab.klaus)

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

// MARK: - Update Available Banner

/// Shown at the top of the app when `UpdateChecker` finds a newer App
/// Store build than the running binary. Mirrors `GracePeriodBanner`'s
/// shape — slim safe-area inset with a tinted backdrop, primary CTA,
/// and a secondary "Not now" affordance — so users get a consistent
/// "something needs your attention" pattern across both prompts.
///
/// Tinted blue rather than amber: this is informational ("something
/// new is available") not warning ("your Pro features are about to
/// expire"). The dismissal is per-version so the user isn't nagged on
/// every launch between releases.
struct UpdateAvailableBanner: View {
    @Environment(\.theme) private var theme
    let version: String
    let snippet: String?
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.blue)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("WiFi Buddy \(version) is available")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                if let snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                } else {
                    Text("Tap Update to get the latest features and fixes.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            VStack(spacing: 6) {
                Button(action: onUpdate) {
                    Text("Update")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.blue))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open WiFi Buddy in the App Store to update")
                Button(action: onDismiss) {
                    Text("Not now")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss update prompt for this version")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.blue.opacity(0.10)
                .overlay(
                    Rectangle()
                        .fill(Color.blue.opacity(0.28))
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

#Preview {
    MainTabView()
        .withAppTheme()
}
