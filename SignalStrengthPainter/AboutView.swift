import SwiftUI

/// "About & Guide" sheet presented from the hamburger menu on the Speed
/// tab. This is the single place a new user (or a returning one who
/// forgot what a tab does) can read what WiFi Buddy actually is, what
/// each tab is for, and how to run the two flows (Speed Test + Survey)
/// that drive almost everything else in the app.
///
/// Structure is intentionally static — no live network state, no probes,
/// no animated cards. The goal is a readable reference, not another
/// dashboard. Every string lives here so tweaks don't touch other files.
struct AboutView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Titles of the sections the user has tapped open. All sections start
    /// collapsed so the page reads as a short, scannable table of contents
    /// rather than a wall of text. Section titles are unique within this
    /// view, so they double as IDs.
    @State private var expandedSections: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    heroSection
                        .padding(.top, 8)

                    whatIsSection

                    tabsSection

                    howToSpeedTestSection

                    howToSurveySection

                    klausSection

                    proSection

                    privacySection

                    footerSection
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Getting Started")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 30, height: 30)
                            .background(theme.cardFill)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(theme.cardStroke, lineWidth: 1))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 10) {
            AppLogoView(size: 72)
            Text("WiFi Buddy")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(theme.primaryText)
            Text("Your pocket Wi-Fi expert — test, map, and fix your network without calling IT.")
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
    }

    // MARK: - What is WiFi Buddy

    private var whatIsSection: some View {
        section(
            title: "What is WiFi Buddy?",
            icon: "sparkles"
        ) {
            bodyText(
                "WiFi Buddy helps you understand and improve the Wi-Fi you already have. In a few taps you can measure your speed, walk your home to see where signal drops off, check who's on your network, and ask Klaus — our built-in Wi-Fi assistant — for plain-English advice."
            )
            bodyText(
                "Everything runs on-device. We don't send your network data to a server, and Klaus is a local knowledge engine — no cloud, no accounts, no tracking."
            )
        }
    }

    // MARK: - Tabs walkthrough

    private var tabsSection: some View {
        section(
            title: "The Five Tabs",
            icon: "square.grid.2x2.fill"
        ) {
            tabRow(
                icon: "speedometer",
                tint: .blue,
                title: "Speed",
                subtitle: "Run a full speed test, see your live ISP → router → device topology, and read a plain-English report on how well your connection handles streaming, gaming, calls, and work."
            )
            tabRow(
                icon: "map.fill",
                tint: .cyan,
                title: "Survey (Pro)",
                subtitle: "Walk your space with AR tracking and watch a heatmap paint itself onto a floor plan. When you stop, you get an A–F grade, dead-zone detection, and tailored tips."
            )
            tabRow(
                icon: "bubble.left.and.bubble.right.fill",
                tint: .green,
                title: "Klaus",
                subtitle: "Chat with Klaus, your built-in Wi-Fi sidekick. Ask anything from \"Why is my 5 GHz slower than 2.4 GHz?\" to \"Should I buy a mesh system?\" — he reads your live in-app numbers and answers in plain English."
            )
            tabRow(
                icon: "laptopcomputer.and.iphone",
                tint: .purple,
                title: "Devices",
                subtitle: "See every device on your network — phones, TVs, printers, smart plugs — with make-and-model guesses. Mark known devices as trusted so unknowns stand out."
            )
            tabRow(
                icon: "crown.fill",
                tint: .orange,
                title: "Pro",
                subtitle: "Unlock unlimited Survey runs and unlimited Klaus chat. Try it free for 3 days."
            )
        }
    }

    // MARK: - How-to: Speed Test

    private var howToSpeedTestSection: some View {
        section(
            title: "How to Run a Speed Test",
            icon: "bolt.fill"
        ) {
            stepRow(number: 1, title: "Open the Speed tab", body: "That's where you are when you first open WiFi Buddy.")
            stepRow(number: 2, title: "Tap \"Start Speed Test\"", body: "We pick the nearest Cloudflare test server, measure ping and jitter, then download and upload bursts for up to 12 seconds each.")
            stepRow(number: 3, title: "Read your report", body: "When it finishes, scroll down for a per-activity rating — streaming, gaming, video calls, home office, and browsing — based on your actual numbers.")
            tipCallout(
                text: "If the server info strip shows an amber warning, your ISP is routing the test far from you. Real speeds to nearby services are probably higher than the test reports."
            )
        }
    }

    // MARK: - How-to: Survey

    private var howToSurveySection: some View {
        section(
            title: "How to Survey Your Home",
            icon: "map.fill"
        ) {
            bodyText(
                "A survey maps Wi-Fi quality onto a floor plan by watching your device's position in AR while repeatedly measuring latency. It's the best way to find dead zones."
            )
            stepRow(number: 1, title: "Open the Survey tab", body: "Pick a floor plan (Blank, Apartment, or Upstairs) that roughly matches your home.")
            stepRow(number: 2, title: "Tap your starting spot on the map", body: "Stand at that real-world spot, then tap \"Start Survey\".")
            stepRow(number: 3, title: "Walk slowly through every room", body: "Hold your phone naturally. A colored trail appears behind you — green is great, yellow is okay, red is a dead zone.")
            stepRow(number: 4, title: "Re-anchor if you drift", body: "If the on-screen position slides off, tap \"Re-anchor Here\" and then tap your real location on the map to correct it.")
            stepRow(number: 5, title: "Tap \"Stop Survey\" when done", body: "You'll get a grade, dead-zone count, coverage mix, and personalized recommendations.")
            tipCallout(
                text: "Aim for at least 20–30 seconds of walking so we have enough samples to read the signal reliably."
            )
        }
    }

    // MARK: - Klaus

    private var klausSection: some View {
        section(
            title: "Meet Klaus, Your Wi-Fi Sidekick",
            icon: "bubble.left.and.bubble.right.fill"
        ) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 56, height: 56)
                    KlausMascotView(size: 56, mode: .portrait)
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ask anything, no tech jargon")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text("Open the Klaus tab and start typing. He answers common Wi-Fi questions — from \"Why is my 5 GHz slower than 2.4 GHz?\" to \"Should I buy a mesh system?\"")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            bodyText(
                "Free accounts get one question per install. Pro unlocks unlimited chat."
            )
        }
    }

    // MARK: - Pro

    private var proSection: some View {
        section(
            title: "WiFi Buddy Pro",
            icon: "crown.fill",
            accent: .orange
        ) {
            proFeatureRow(icon: "map.fill", text: "Unlimited AR surveys with dead-zone detection and personalized fixes")
            proFeatureRow(icon: "bubble.left.fill", text: "Unlimited Klaus AI chat")
            proFeatureRow(icon: "sparkles", text: "Support indie development so we can keep adding features")
            bodyText(
                "WiFi Buddy Pro is $9.99/year, and every new subscription starts with a 3-day free trial. Cancel anytime in Settings — trials auto-renew if not cancelled."
            )
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        section(
            title: "Your Data Stays Yours",
            icon: "lock.shield.fill",
            accent: .green
        ) {
            bulletRow(text: "Surveys, device lists, and chat history are stored only on this device.")
            bulletRow(text: "Speed tests use Cloudflare's public endpoint — only your IP is visible to them, same as any website.")
            bulletRow(text: "We don't require an account, don't collect analytics, and don't show ads.")
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 4) {
            if let version = appVersion {
                Text("Version \(version)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.quaternaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    // MARK: - Building blocks

    /// Themed collapsible card section with a tappable title row and
    /// caller-supplied body. The whole header is the toggle target, with
    /// a chevron that rotates when expanded. `accent` tints the title icon
    /// only; the card chrome stays neutral so the page reads as one
    /// consistent stack rather than a loud multi-color list.
    @ViewBuilder
    private func section<Content: View>(
        title: String,
        icon: String,
        accent: Color = .blue,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isExpanded = expandedSections.contains(title)

        VStack(alignment: .leading, spacing: isExpanded ? 14 : 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if isExpanded {
                        expandedSections.remove(title)
                    } else {
                        expandedSections.insert(title)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accent.opacity(0.15))
                            .frame(width: 30, height: 30)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")
            .accessibilityAddTraits(.isHeader)

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func stepRow(number: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func proFeatureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func bulletRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Subtle amber-tinted callout used after a how-to flow for the
    /// single "read this" tip that doesn't fit into a numbered step.
    private func tipCallout(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.28))
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.98, green: 0.78, blue: 0.28).opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(red: 0.98, green: 0.78, blue: 0.28).opacity(0.25), lineWidth: 1)
                )
        )
    }
}

#Preview {
    AboutView()
        .withAppTheme()
}
