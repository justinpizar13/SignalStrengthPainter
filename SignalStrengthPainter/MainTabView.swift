import SwiftUI

struct MainTabView: View {
    // Pro entitlement is derived from `Transaction.currentEntitlements`
    // inside `ProStore` — there is no `@AppStorage("isProUser")` flag that
    // a jailbroken user could flip to unlock Pro without paying.
    @StateObject private var store = ProStore()
    @State private var selectedTab: Tab = .speed

    enum Tab: Int {
        case speed, survey, klaus, devices, pro
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
