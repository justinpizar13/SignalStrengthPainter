import SwiftUI
import StoreKit

struct PaywallView: View {
    /// StoreKit 2 manager. Owns product loading, purchase, restore, and the
    /// `isProUser` entitlement check. Injected by `MainTabView` so a single
    /// instance lives for the whole app session.
    @ObservedObject var store: ProStore
    @Binding var isPresented: Bool
    @Environment(\.theme) private var theme
    @State private var currentPage = 0
    @State private var showRestoreError: Bool = false
    /// Drives the bundled legal-document sheet (Privacy Policy / Terms
    /// of Use). Apple's guideline 3.1.2 requires the paywall to expose
    /// both, tappable from the screen that sells the subscription.
    /// Using `Identifiable` binding lets a single `.sheet(item:)`
    /// modifier render whichever doc the user tapped.
    @State private var legalDoc: LegalDocumentView.Kind?

    private let pageCount = 3

    /// The single subscription product ID. Single-plan paywall since
    /// 1.11 — the previous Monthly + Yearly toggle was collapsed into
    /// one annual plan to simplify the funnel.
    private var productID: String { ProStore.annualProductID }

    /// Hard-coded fallback used before StoreKit returns real products,
    /// or if the product fetch fails (e.g. App Store unreachable). Must
    /// stay in sync with the price configured in App Store Connect.
    private static let fallbackAnnualPrice = "$9.99"

    /// Length in days of the introductory free trial declared on the
    /// annual subscription in `Configuration.storekit` and App Store
    /// Connect. Surfaced in CTA copy + the trial timeline + the legal
    /// disclosure block. If you change the trial period in either
    /// store config, change it here in the same commit.
    private static let trialDays = 2

    /// True when the user is still eligible to redeem the free trial.
    /// StoreKit reports this per subscription group, so a returning
    /// subscriber who already burned the trial on a legacy
    /// monthly/yearly SKU will correctly see "no trial available".
    private var trialAvailable: Bool {
        store.isEligibleForIntroOffer(productID: productID)
    }

    /// Live (or fallback) price string for the annual plan.
    private var annualDisplayPrice: String {
        store.product(for: productID)?.displayPrice ?? Self.fallbackAnnualPrice
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            theme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroPager
                        .frame(height: 360)

                    VStack(spacing: 22) {
                        pageDots
                        titleSection
                        featureIcon
                        pricingCard
                        buyButton
                        if trialAvailable {
                            trialTimeline
                        }
                        disclosureLine
                        bottomLinks
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 36)
                }
            }

            closeButton
                .padding(.top, 12)
                .padding(.trailing, 16)
        }
        .sheet(item: $legalDoc) { kind in
            LegalDocumentView(kind: kind)
                .withAppTheme()
        }
    }

    // MARK: - Hero pager

    /// Three-page swipeable pitch for WiFi Buddy Pro. Each page covers
    /// one of the features that is actually gated behind `store.isProUser`
    /// in the app (AR Survey + Insights report + unlimited Klaus chat),
    /// so the copy here stays in sync with what the user will unlock.
    /// Wired to `currentPage` so the existing `pageDots` below reflect
    /// real selection state instead of being decorative.
    private var heroPager: some View {
        TabView(selection: $currentPage) {
            heroPage(
                eyebrow: "AR Wi-Fi Survey",
                headline: "Visualize your Wi-Fi coverage",
                subtitle: "Walk your home and watch signal strength paint itself onto a live floor plan — no extra hardware needed."
            ) {
                surveyArt
            }
            .tag(0)

            heroPage(
                eyebrow: "Smart Insights",
                headline: "Fix dead zones, fast",
                subtitle: "Every survey delivers personalized fixes — where to move your router, add a mesh node, or switch bands."
            ) {
                insightsArt
            }
            .tag(1)

            heroPage(
                eyebrow: "Klaus AI Assistant",
                headline: "Unlimited Wi-Fi help",
                subtitle: "Chat as much as you like with Klaus — your personal Wi-Fi expert, with clear answers tuned to your network."
            ) {
                klausArt
            }
            .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.2), value: currentPage)
    }

    /// Layout for a single pager page: art on top, then eyebrow tag,
    /// headline, and supporting copy. The art's fade-to-background
    /// gradient lives here (instead of on each art view) so every page
    /// blends into `theme.background` identically.
    @ViewBuilder
    private func heroPage<Art: View>(
        eyebrow: String,
        headline: String,
        subtitle: String,
        @ViewBuilder art: () -> Art
    ) -> some View {
        VStack(spacing: 12) {
            art()
                .frame(height: 220)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [.clear, .clear, theme.background.opacity(0.85), theme.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 6) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.blue)

                Text(headline)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Per-page art

    /// Page 1 — the existing floor-plan heatmap preview. Shows what
    /// the user sees after a completed AR survey: rooms, heat blobs,
    /// signal nodes, and the connection mesh between them.
    private var surveyArt: some View {
        Canvas { context, size in
            drawMiniFloorPlan(context: context, size: size)
            drawHeatBlobs(context: context, size: size)
            drawSignalNodes(context: context, size: size)
            drawConnectionLines(context: context, size: size)
        }
    }

    /// Page 2 — same floor plan, but annotated with two callout badges
    /// so the user sees the *interpretation* layer, not just the raw
    /// heatmap. The positions are percentage-based so the layout holds
    /// across device widths.
    private var insightsArt: some View {
        ZStack {
            Canvas { context, size in
                drawMiniFloorPlan(context: context, size: size)
                drawHeatBlobs(context: context, size: size)
            }

            GeometryReader { geo in
                insightCallout(
                    icon: "exclamationmark.triangle.fill",
                    label: "Dead zone",
                    tint: Color(red: 0.95, green: 0.35, blue: 0.3)
                )
                .position(x: geo.size.width * 0.28, y: geo.size.height * 0.78)

                insightCallout(
                    icon: "checkmark.seal.fill",
                    label: "Move router here",
                    tint: Color(red: 0.25, green: 0.8, blue: 0.45)
                )
                .position(x: geo.size.width * 0.68, y: geo.size.height * 0.28)
            }
        }
    }

    private func insightCallout(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(tint)
                .shadow(color: tint.opacity(0.5), radius: 6, x: 0, y: 2)
        )
    }

    /// Page 3 — Klaus mascot plus two sample chat bubbles to communicate
    /// "this is a real conversational feature, not just a help article".
    /// Dark panel matches the other pages' backdrop so the pager reads
    /// as one consistent visual space.
    private var klausArt: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08)

            Canvas { context, size in
                drawGridBackdrop(context: context, size: size)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    KlausMascotView(size: 52, mode: .portrait, isAnimating: false)
                        .frame(width: 52, height: 52)
                        .background(
                            Circle().fill(Color.white.opacity(0.08))
                        )
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 8) {
                        chatBubble(
                            text: "My video calls drop in the office. What can I do?",
                            isUser: true
                        )
                        chatBubble(
                            text: "Your office is 38 ft from the router with two walls. Try moving it to the hallway or add a mesh node near the desk.",
                            isUser: false
                        )
                    }
                }

                HStack {
                    Spacer(minLength: 0)
                    chatBubble(text: "That fixed it — thanks!", isUser: true)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func chatBubble(text: String, isUser: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isUser
                          ? Color.blue.opacity(0.85)
                          : Color.white.opacity(0.12))
            )
            .frame(maxWidth: 220, alignment: isUser ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Subtle grid used as backdrop on the Klaus page so it feels like
    /// the same "network canvas" as the floor-plan pages, just without
    /// rooms drawn on top.
    private func drawGridBackdrop(context: GraphicsContext, size: CGSize) {
        var ctx = context
        ctx.opacity = 0.12
        let gridSpacing: CGFloat = 28
        let cols = Int(size.width / gridSpacing) + 1
        let rows = Int(size.height / gridSpacing) + 1
        for col in 0...cols {
            let x = CGFloat(col) * gridSpacing
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(line, with: .color(.gray), lineWidth: 0.5)
        }
        for row in 0...rows {
            let y = CGFloat(row) * gridSpacing
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(line, with: .color(.gray), lineWidth: 0.5)
        }
    }

    private func drawMiniFloorPlan(context: GraphicsContext, size: CGSize) {
        let bg = Path { p in
            p.addRect(CGRect(origin: .zero, size: size))
        }
        context.fill(bg, with: .color(Color(red: 0.06, green: 0.06, blue: 0.08)))

        var ctx = context
        ctx.opacity = 0.18
        let gridSpacing: CGFloat = 28
        let cols = Int(size.width / gridSpacing) + 1
        let rows = Int(size.height / gridSpacing) + 1
        for col in 0...cols {
            let x = CGFloat(col) * gridSpacing
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(line, with: .color(.gray), lineWidth: 0.5)
        }
        for row in 0...rows {
            let y = CGFloat(row) * gridSpacing
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(line, with: .color(.gray), lineWidth: 0.5)
        }

        var walls = context
        walls.opacity = 0.35
        let wallColor = Color(red: 0.9, green: 0.85, blue: 0.6)
        let rooms: [(CGRect, String)] = [
            (CGRect(x: 20, y: 30, width: 140, height: 110), "KITCHEN"),
            (CGRect(x: 180, y: 30, width: 160, height: 110), "LIVING"),
            (CGRect(x: 20, y: 155, width: 160, height: 100), "BEDROOM"),
            (CGRect(x: 200, y: 155, width: 140, height: 100), "OFFICE"),
        ]
        for (rect, label) in rooms {
            let roomPath = Path(rect)
            walls.stroke(roomPath, with: .color(wallColor), lineWidth: 1.5)

            let labelPoint = CGPoint(x: rect.midX - 20, y: rect.minY + 14)
            walls.draw(
                Text(label).font(.system(size: 8, weight: .medium)).foregroundColor(wallColor),
                at: labelPoint,
                anchor: .topLeading
            )
        }
    }

    private func drawHeatBlobs(context: GraphicsContext, size: CGSize) {
        let blobs: [(CGPoint, CGFloat, Color)] = [
            (CGPoint(x: 90, y: 85), 80, Color(red: 0.2, green: 0.85, blue: 0.4)),
            (CGPoint(x: 260, y: 85), 70, Color(red: 0.3, green: 0.75, blue: 0.95)),
            (CGPoint(x: 100, y: 200), 65, Color(red: 0.95, green: 0.75, blue: 0.2)),
            (CGPoint(x: 270, y: 200), 60, Color(red: 0.95, green: 0.35, blue: 0.3)),
            (CGPoint(x: 180, y: 140), 50, Color(red: 0.5, green: 0.9, blue: 0.5)),
        ]
        for (center, radius, color) in blobs {
            let blobRect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let gradient = Gradient(colors: [color.opacity(0.55), color.opacity(0.12), .clear])
            context.fill(
                Path(ellipseIn: blobRect),
                with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
            )
        }
    }

    private func drawSignalNodes(context: GraphicsContext, size: CGSize) {
        let nodes: [CGPoint] = [
            CGPoint(x: 90, y: 85),
            CGPoint(x: 260, y: 85),
            CGPoint(x: 100, y: 200),
            CGPoint(x: 270, y: 200),
            CGPoint(x: 180, y: 140),
            CGPoint(x: 50, y: 145),
            CGPoint(x: 320, y: 140),
        ]
        for node in nodes {
            let outerR: CGFloat = 8
            let innerR: CGFloat = 4
            context.fill(
                Path(ellipseIn: CGRect(x: node.x - outerR, y: node.y - outerR, width: outerR * 2, height: outerR * 2)),
                with: .color(Color.blue.opacity(0.4))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: node.x - innerR, y: node.y - innerR, width: innerR * 2, height: innerR * 2)),
                with: .color(Color.blue)
            )
        }
    }

    private func drawConnectionLines(context: GraphicsContext, size: CGSize) {
        let connections: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 90, y: 85), CGPoint(x: 180, y: 140)),
            (CGPoint(x: 260, y: 85), CGPoint(x: 180, y: 140)),
            (CGPoint(x: 100, y: 200), CGPoint(x: 180, y: 140)),
            (CGPoint(x: 270, y: 200), CGPoint(x: 180, y: 140)),
            (CGPoint(x: 50, y: 145), CGPoint(x: 100, y: 200)),
            (CGPoint(x: 320, y: 140), CGPoint(x: 270, y: 200)),
            (CGPoint(x: 90, y: 85), CGPoint(x: 50, y: 145)),
            (CGPoint(x: 260, y: 85), CGPoint(x: 320, y: 140)),
        ]
        var ctx = context
        ctx.opacity = 0.35
        for (a, b) in connections {
            var line = Path()
            line.move(to: a)
            line.addLine(to: b)
            ctx.stroke(line, with: .color(.blue), lineWidth: 1.2)
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        HStack(spacing: 0) {
            Text("Unlock WiFi Buddy ")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(theme.primaryText)
            Text("Pro")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.blue)
        }
    }

    // MARK: - Feature icon

    private var featureIcon: some View {
        AppLogoView(size: 100)
            .padding(.vertical, 4)
    }

    // MARK: - Page dots

    /// Selection indicator for `heroPager`. Dots are tappable so users
    /// who spot them before they spot the swipe gesture can still
    /// navigate the feature tour.
    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentPage = index
                    }
                } label: {
                    if index == currentPage {
                        Capsule()
                            .fill(.blue)
                            .frame(width: 20, height: 8)
                    } else {
                        Circle()
                            .fill(theme.tertiaryText)
                            .frame(width: 8, height: 8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Feature page \(index + 1) of \(pageCount)")
            }
        }
    }

    // MARK: - Pricing card

    /// Single, non-interactive pricing tile. Single-plan since 1.11 —
    /// no radio selection, no monthly/yearly toggle, no strikethrough
    /// "was" price. Reads the live `displayPrice` so localized
    /// currencies (€, £, ¥) render correctly when the user is in a
    /// non-USD storefront, and falls back to the hard-coded $9.99 if
    /// the product catalog hasn't loaded yet.
    private var pricingCard: some View {
        let badgeText = trialAvailable ? "\(Self.trialDays) Days Free" : nil
        let subtitle = trialAvailable
            ? "Then \(annualDisplayPrice)/year. Cancel anytime."
            : "Billed once a year. Cancel anytime."

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("WiFi Buddy Pro")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }

                Text(annualDisplayPrice)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(theme.primaryText)

                Text("per year")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.subtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.blue, lineWidth: 2)
        )
        .padding(.top, 8)
    }

    // MARK: - Buy button

    private var buyButton: some View {
        Button {
            Task { await startPurchase() }
        } label: {
            HStack(spacing: 10) {
                if store.purchaseInFlight {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                }
                Text(buyButtonLabel)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.buttonText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(store.purchaseInFlight || store.isRestoring)
        .opacity((store.purchaseInFlight || store.isRestoring) ? 0.7 : 1)
        .padding(.top, 8)
    }

    /// CTA copy flips between "Start N-Day Free Trial" (when the user
    /// is eligible for the intro offer) and the plain "Subscribe"
    /// path. We never show trial copy when StoreKit reports the user
    /// is no longer eligible — doing so would set up a refund because
    /// the purchase goes through at full price. App Review (round 2,
    /// April 2026) specifically rejected the prior build for surfacing
    /// "Subscribe" while StoreKit still ran a free-trial flow; the
    /// inverse is equally bad.
    private var buyButtonLabel: String {
        if store.purchaseInFlight { return "Processing..." }
        if trialAvailable {
            return "Start \(Self.trialDays)-Day Free Trial"
        }
        return "Subscribe"
    }

    /// Three-row trial timeline shown under the CTA whenever the user
    /// is intro-offer eligible. Transparent disclosure of the charge
    /// date lifts trial-start rate AND reduces "I forgot I signed up"
    /// refund requests. The N-day trial parameter mirrors
    /// `Configuration.storekit` so changing the trial length in one
    /// place updates the timeline copy automatically.
    private var trialTimeline: some View {
        let chargeDay = Self.trialDays + 1
        return VStack(alignment: .leading, spacing: 10) {
            trialTimelineRow(
                index: 1,
                title: "Today",
                detail: "Full Pro access — unlimited surveys, insights, Klaus."
            )
            trialTimelineRow(
                index: 2,
                title: "Day \(Self.trialDays)",
                detail: "We'll send a reminder before your trial ends."
            )
            trialTimelineRow(
                index: 3,
                title: "Day \(chargeDay)",
                detail: "Trial ends. You'll be charged \(annualDisplayPrice)/year unless you cancel."
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func trialTimelineRow(
        index: Int,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.18))
                    .frame(width: 22, height: 22)
                Text("\(index)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    /// Full legal disclosure block under the CTA. Apple's App Review
    /// guideline 3.1.2 (and 3.1.2(a) for auto-renewing subs) requires
    /// the paywall to spell out: subscription title, length, price,
    /// that payment is charged to the Apple ID at confirmation, the
    /// auto-renewal rules (24-hour window on both sides), and how to
    /// cancel. We dynamically pull the live price from StoreKit when
    /// available and fall back to the hard-coded values so this block
    /// is never blank during product-load failures.
    private var disclosureLine: some View {
        let trialLine = trialAvailable
            ? "After your \(Self.trialDays)-day free trial, your Apple ID will be charged \(annualDisplayPrice)/year. "
            : ""

        return VStack(spacing: 6) {
            Text("WiFi Buddy Pro — \(annualDisplayPrice)/year. \(trialLine)Payment will be charged to your Apple ID at confirmation of purchase. Subscription auto-renews for the same price and period unless canceled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours before the end of the current period. You can manage or cancel your subscription in Settings → Apple ID → Subscriptions. Any unused portion of a free trial is forfeited when a subscription is purchased.")
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Button("Privacy Policy") {
                    legalDoc = .privacyPolicy
                }
                Text("•")
                    .foregroundStyle(theme.tertiaryText)
                Button("Terms of Use") {
                    legalDoc = .termsOfUse
                }
            }
            .font(.system(size: 11, weight: .medium))
            .tint(.blue)
            .foregroundStyle(.blue)
        }
        .frame(maxWidth: .infinity)
    }

    private func startPurchase() async {
        guard let product = store.product(for: productID) else {
            // Product metadata hasn't loaded (or the ID is wrong) — retry
            // the fetch and surface whatever error `loadProducts()` set.
            // We preserve that error (e.g. "launch from Xcode so
            // Configuration.storekit is attached") instead of overwriting
            // it with a generic "try again" — otherwise the real reason
            // is invisible on device.
            await store.loadProducts()
            if store.product(for: productID) == nil {
                if store.lastError == nil {
                    store.lastError = "Couldn't load that subscription. Please try again."
                }
                showRestoreError = true
            }
            return
        }

        let succeeded = await store.purchase(product)
        if succeeded {
            isPresented = false
        } else if store.lastError != nil {
            showRestoreError = true
        }
    }

    // MARK: - Bottom links

    private var bottomLinks: some View {
        HStack(spacing: 32) {
            Button {
                Task { await startRestore() }
            } label: {
                HStack(spacing: 6) {
                    if store.isRestoring {
                        ProgressView()
                            .tint(.blue)
                            .scaleEffect(0.7)
                    }
                    Text(store.isRestoring ? "Restoring..." : "Restore purchase")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.blue)
            }
            .disabled(store.purchaseInFlight || store.isRestoring)

            Button("Not now") {
                isPresented = false
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(theme.tertiaryText)
        }
        .padding(.top, 4)
        .alert("WiFi Buddy Pro", isPresented: $showRestoreError, presenting: store.lastError) { _ in
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: { text in
            Text(text)
        }
    }

    private func startRestore() async {
        await store.restore()
        if store.isProUser {
            isPresented = false
        } else if store.lastError != nil {
            showRestoreError = true
        }
    }

    // MARK: - Close button

    private var closeButton: some View {
        Button {
            isPresented = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 30, height: 30)
                .background(theme.subtle)
                .clipShape(Circle())
        }
    }
}

#Preview {
    PaywallView(store: ProStore(), isPresented: .constant(true))
        .withAppTheme()
}
