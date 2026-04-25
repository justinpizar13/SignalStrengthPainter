# SignalStrengthPainter — session memory (reference for future chats)

This document summarizes what was built and changed across the conversation so you can paste or `@`-reference it in a new chat.

## Product goal

An iOS SwiftUI app that feels closer to tools like **NetSpot**: walk a space, see a **person/marker** on a **floor plan**, and **paint signal quality** (here: **TCP connect latency** to `8.8.8.8:53`) onto the map as a **heatmap-style** overlay plus a **breadcrumb path**.

## Branding

The app is called **WiFi Buddy** (project/repo name remains `SignalStrengthPainter`). The premium tier is **WiFi Buddy Pro**. `CFBundleDisplayName` in `Info.plist` is set to "WiFi Buddy" so that name appears under the icon on the iOS home screen.

**Naming history (April 2026):** the brand was originally written **"Wi-Fi Buddy"** (with the hyphen, matching the Wi-Fi Alliance trademark style), but that exact name was already taken on the App Store. We dropped the hyphen and the rename to **"WiFi Buddy"** was applied across every user-facing string, the StoreKit configuration (`Configuration.storekit` subscription group + product display/reference names), `CFBundleDisplayName`, all docs (`README.md`, `Support.md`, `PrivacyPolicy.md`, `TermsOfUse.md`), and code comments. The bundle ID `com.wifibuddy.app` was already hyphen-free so it didn't need to change. Klaus's greeting still uses "Wi-Fi" (with the hyphen) when referring to the *technology* — only the product name lost the hyphen.

### App Icon

Custom app icon stored in `Assets.xcassets/AppIcon.appiconset/` — a single 1024x1024 PNG (iOS 17+ universal format). Generated programmatically via `scripts/generate_app_icon.py` (Pillow) to exactly match `AppLogoView`.

**Current design (traffic-light Wi-Fi on dark gray, April 2026):**
- **Dark gray background** `(40, 40, 44)` — full-bleed (iOS applies its own squircle mask at runtime). Neutral near-black with a hint of warmth; picked over pure black so the glyph still reads with a subtle surface and over the earlier light cream so the saturated traffic-light palette pops.
- **Wi-Fi glyph** — three concentric 90°-fan arcs (225°→315°) + a center dot, **each element its own flat solid color** (no gradient, no sheen). Classic "signal strength" traffic-light palette:
  - Outer arc: green `(77, 217, 102)` — `Color(0.30, 0.85, 0.40)`
  - Middle arc: yellow `(250, 209, 56)` — `Color(0.98, 0.82, 0.22)`
  - Inner arc: orange `(250, 133, 56)` — `Color(0.98, 0.52, 0.22)`
  - Center dot: red `(250, 82, 82)` — `Color(0.98, 0.32, 0.32)`
- **Evenly spaced waves.** Stroke width is `0.080` of the canvas; each successive arc is inset by `stroke + 0.050`, yielding a **consistent `0.050` gap** between neighboring strokes and between the inner arc and the dot. Outer/middle/inner bbox radii `0.445 / 0.315 / 0.185`, dot radius `0.055`. This even cadence is what makes the icon read as a proper Wi-Fi signal fan rather than a densely packed mark (earlier iterations had ~0.025 gaps, so strokes dominated over whitespace).
- **Vertically centered.** `cy = 0.695` places the glyph bounding box at `y ∈ [0.250, 0.750]` — top of outer arc is exactly as far from the top edge as the bottom of the dot is from the bottom edge, so the mark sits dead-center in the square canvas.
- **No sparkles, no sheen, no iridescent gradient.** The earlier earthy-palette iteration layered a diagonal iridescent shader, a warm off-white specular band, and three upper-right sparkle stars; all three were removed in favor of the simpler flat-color design.
- **Rendering** — drawn at 4× supersampling (`4096×4096`) and downsampled with LANCZOS to 1024×1024 for crisp anti-aliased edges. The glyph alpha is slightly Gaussian-blurred (`radius = SCALE * 0.3`) before compositing to smooth aliasing on the curved strokes. Final PNG is flattened to opaque RGB on the dark-gray background (App Store requires no alpha channel).

**Design history:**
- v1 (Apple-glass, pale): silver-white dominated with barely-visible pastel hints, glyph at `cy = 0.575` with `r_outer = 0.355`. User feedback: too pale, rainbow colors gone, not centered/sized to fill the icon.
- v2 (Apple-TV-glass): grew radii, shifted `cy` down to visually center, bumped tint saturation + strength via bilinear 4-corner tint (pink TL / mint TR / lavender BR / peach BL), added vertical 3D depth shading (+14% top / −22% bottom), tightened the sheen band.
- v3 (black + pastel glass): rewrote the PNG to exactly mirror the in-app `AppLogoView` dark palette — pure black background with pastel pink/silver/peach/mint/lavender gradient stops. Sparkles RGB-dimmed by 0.9.
- v4 (unified earthy palette): user preferred the muted earthy tones the light-mode `AppLogoView` was rendering (burgundy/olive/forest/plum). Consolidated the two scheme-specific palettes into a single `IridescentPalette.earthy` used by both the in-app view (regardless of color scheme) and the home-screen icon. Icon background swapped from black to a light cream `(242, 241, 246)` since the darker earthy glyph would disappear on black. Sheen color/alpha swapped from `white @ 0.70` to `warm off-white @ 0.40` to match the earthy surface.
- v5 (current — traffic-light on dark gray, April 2026): user asked to return to the original traffic-light Wi-Fi concept they first sketched (the v0 blue-cyan gradient icon with green/yellow/orange arcs + red dot + three upper-right sparkles), with three explicit fixes: **remove sparkles**, **correctly space out the waves**, and **swap the blue gradient for a dark gray background**. `IridescentPalette`, the earthy gradient stops, the diagonal sheen, `drawSparkles`, and `Color.dimmed(by:)` were all deleted from `AppLogoView.swift`. Geometry was re-tuned from the dense `0.425/0.302/0.180` + `0.096` stroke (gaps ≈ 0.025) to `0.445/0.315/0.185` + `0.080` stroke (gaps = 0.050) so whitespace and strokes are balanced. `cy` moved from `0.635` to `0.695` to vertically center the now-smaller-dot bounding box.

The asset catalog is registered in `project.pbxproj` with `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.

**Prior designs (archived):**
- v0 sketch: blue-to-cyan vertical gradient background with traffic-light colored arcs (green/yellow/orange) + red dot + white sparkles, `cy = 0.68`. The v5 design above is a refinement of this concept.
- Black background with pastel Apple-glass pink/silver/peach/mint/lavender gradient.
- Light cream background with earthy iridescent gradient (burgundy/slate/brown/forest/plum/slate) + diagonal sheen + upper-right sparkles.

### In-App Branding (`AppLogoView.swift`)

Reusable `AppLogoView` SwiftUI view that draws the branded logo programmatically using `Canvas`. **Renders on a transparent background** (no tile) so it composites cleanly over themed cards and headers — the dark-gray squircle is reserved for the home-screen app icon PNG. Single layer:

- **Wi-Fi glyph** — three arcs + dot, each stroked/filled with its own flat solid color from the traffic-light palette (outer green, middle yellow, inner orange, dot red). Round caps via `StrokeStyle(lineCap: .round)`. **Geometry matches the 1024×1024 PNG** (`cy = 0.695`, arc bbox radii `0.445 / 0.315 / 0.185`, stroke thickness `0.080`, dot radius `0.055`) — stored as static constants so the in-app logo and home-screen icon stay visually identical at any scale. The `225° → 315°` arc sweep draws the upper fan shape in SwiftUI's y-down coordinate system (matches PIL's convention in the PNG generator).

**No palette type.** The four colors are plain `Color` constants on `AppLogoView` itself — `outerArcColor`, `middleArcColor`, `innerArcColor`, `dotColor`. The earlier `IridescentPalette` struct (with its `pink/silverWarm/peach/mint/lavender/silverCool/sheenColor/sheenAlpha` fields, `gradientStops(dim:)` method, `resolved(for:)` factory, and `Color.dimmed(by:)` extension) was deleted entirely along with the sheen/sparkle layers. There is no longer a `colorScheme` dependency — the glyph reads identically in both modes because it's the same flat primary colors on a transparent background.

Accepts a `size` parameter; every element scales proportionally so the logo holds up from 26pt (compact survey header) to 100pt (paywall hero).

The logo+sparkle is used consistently across all tabs:
- **`DashboardView.swift`** — Speed tab header shows `AppLogoView(size: 44)` + "WiFi Buddy" title.
- **`PaywallView.swift`** — Feature icon section shows `AppLogoView(size: 100)`.
- **`MainTabView.swift` (`SignalDetailView`)** — Signal tab header shows `AppLogoView(size: 44)` above the "Signal Strength" heading.
- **`DeviceDiscoveryView.swift`** — Devices tab header shows `AppLogoView(size: 44)` above the "Device Discovery" heading.
- **`ContentView.swift`** — Survey tab calibration header shows `AppLogoView(size: 34)`; compact/expanded survey header shows `AppLogoView(size: 26)`. Replaces the previous SF Symbol `map.fill` icon in both layouts.

## Current architecture (high level)

| Layer | Role |
|--------|------|
| **`SignalStrengthPainterApp.swift`** | App entry point. Shows **`MainTabView`** as the root view. Applies `.withAppTheme()` for centralized theming. |
| **`AppLogoView.swift`** | Reusable branded logo drawn with `Canvas` — signal-strength colored Wi-Fi arcs (green outer / yellow middle / orange inner) + red center dot, evenly spaced (stroke `0.080` with `0.050` gaps) and vertically centered at `cy = 0.695`. Flat solid colors, no sparkles, no sheen, no gradient, transparent background. Geometry/colors shared with `scripts/generate_app_icon.py`. Accepts `size` parameter for flexible rendering. Used across all tab headers: DashboardView, SignalDetailView, DeviceDiscoveryView, ContentView (Survey), PaywallView, and WiFiAssistantView. |
| **`AppTheme.swift`** | Centralized theming: `AppearanceMode` enum (system/light/dark), `AppTheme` struct with semantic colors for both modes, `EnvironmentKey` injection, `ThemedRootModifier`. User preference persisted via `@AppStorage("appearanceMode")`. |
| **`MainTabView.swift`** | **Tab-based UI** with 5 tabs: **Speed** (dashboard), **Survey** (AR walk), **Signal** (connection quality), **Devices** (network device discovery), **Pro** (paywall — hidden for pro users). Uses `@AppStorage("isProUser")` to gate Pro tab visibility. Also contains `AppearanceToggle`, `SignalDetailView` (Signal tab), and `GracePeriodBanner` — a slim amber-tinted safe-area inset shown above the TabView whenever `store.gracePeriodExpiration != nil` ("Payment issue — update your payment method to keep Pro active. Grace period ends <date>"). The banner lets a failed renewal retry without ripping Pro away from the user mid-session, matching Apple's own grace-period UX. |
| **`DashboardView.swift`** | **Speed tab**: WiFiman/Speedtest-inspired dashboard with **live network topology** visualization (ISP → Router → Device, driven by `NetworkTopologyMonitor` — real gateway IP, live TCP pings, animated packet-flow connectors, per-hop health classification), **speed test** (download + upload via Cloudflare with live sparkline, ping/jitter), **speed report** (post-test contextual report rating connection for Netflix/streaming, gaming, video calls, home office, and browsing), **service latency grid** (Google DNS, Cloudflare, OpenDNS, Gateway — Gateway tile now pings the device's actual gateway IP), **survey quick-action card**, and **appearance toggle** (light/dark/system) in the Wi-Fi header. The header also hosts a **hamburger menu button** (top-left `line.3.horizontal` circular icon) that opens `AboutView` (the "Getting Started" sheet) so first-time users have one obvious place to learn what the app does and how each tab works — the header is drawn as a ZStack with the centered brand on its own layer, so adding the menu button on the left doesn't shove the logo off-center. **First-launch auto-present (April 2026):** on the very first app launch, `DashboardView.onAppear` also opens the Getting Started sheet automatically, guarded by an `@AppStorage("hasSeenGettingStarted")` bool that flips to `true` the instant the sheet is shown so returning users are never interrupted again. The flag is stored in `UserDefaults` (not anywhere security-sensitive) because it's purely UX state — the worst-case failure is a user seeing the intro sheet twice, which is harmless. |
| **`NetworkTopologyMonitor.swift`** | **Live topology state** powering the Speed-tab topology card. Publishes `localIP` (via `getifaddrs`, preferring `en0`), `gatewayIP` (inferred from the local IP — same convention as `NetworkScanner`), `gatewayLatencyMs` (TCP ping to the gateway on 80, falling back to 443), `ispLatencyMs` (TCP ping to `8.8.8.8:53`), and derived `LinkHealth` (`.good/.fair/.poor/.offline/.unknown`) for both the WAN hop and the LAN hop. Refreshes on a 6-second `Task` loop plus an immediate refresh on any `NetworkInterfaceMonitor` status change, so flipping Wi-Fi → cellular → offline updates the diagram within a tick. On cellular the LAN hop resolves to `.unknown` (not `.offline`) to avoid misrepresenting that there simply isn't a local router to ping. `deviceLabel` resolves to "Your iPhone" / "Your iPad" / "Your Mac" via `UIDevice.current.localizedModel`. |
| **`SpeedTestManager.swift`** | Multi-phase speed test engine: **latency** (10 HTTP pings, trimmed mean + jitter), **download** (8 concurrent async streams fetching 4 MB chunks via `URLSession.data(for:)` in a `TaskGroup`), **upload** (8 concurrent async streams uploading 4 MB chunks via `URLSession.upload(for:from:)`). Both transfer phases use `TransferCounter` for byte tracking, a shared `sampleTransferPhase()` loop (250 ms sampling, rolling 4-sample window for live display), and compute final speed as total bytes / total time. Each phase runs up to 12 s. |
| **`PaywallView.swift`** | NetSpot-inspired Pro upsell screen. **Swipeable 3-page feature tour at the top (April 2026)**: a `TabView` in `.page(indexDisplayMode: .never)` style bound to `@State private var currentPage` paging through the three features that are *actually* gated behind `store.isProUser` — **(1) AR Wi-Fi Survey** ("Visualize your Wi-Fi coverage") with the existing floor-plan heatmap canvas as art, **(2) Smart Insights** ("Fix dead zones, fast") reusing the floor-plan canvas with two SwiftUI callout badges overlaid via `GeometryReader` + `.position()` at normalized `(0.28, 0.78)` red "Dead zone" and `(0.68, 0.28)` green "Move router here" so positioning holds across device widths, and **(3) Klaus AI Assistant** ("Unlimited Wi-Fi help") with a static `KlausMascotView(mode: .portrait, isAnimating: false)` avatar + three sample chat bubbles over a subtle grid backdrop. Each page is composed by the private generic `heroPage(eyebrow:headline:subtitle:art:)` helper so every page gets identical typographic rhythm (11pt tracked blue eyebrow → 22pt bold headline → 14pt 2-3-line subtitle) and the fade-to-background gradient is applied once inside the helper instead of per-art. `pageDots` below the pager is no longer decorative — it's bound to `currentPage` and each dot is a real `Button` with `withAnimation(.easeInOut(duration: 0.25))` so users who notice the dots before they discover the swipe gesture can still jump directly to page 2 or 3; also carries per-dot `accessibilityLabel`. The old standalone `tagline` view was removed because each page now carries its own per-feature copy. Sections reordered accordingly: `heroPager` (360pt) → `pageDots` → `titleSection` ("Unlock WiFi Buddy Pro") → `featureIcon` (`AppLogoView`) → `pricingCards` → `buyButton`, so the feature pitch lands above the fold and the branding line sits directly above the pricing cards where the purchase decision is made. Pricing cards (**Monthly $3.99**, **Yearly ~~$39.99~~ $34.99** with "Best Deal" badge), Buy Now CTA, Restore / Not Now links, X close. **Default selection is Yearly** (was Monthly) so trial users land on the annual plan. **Trial-aware copy:** when the currently-selected product is intro-offer eligible, the CTA flips from "Buy Now" to **"Start 3-Day Free Trial"**, the Yearly card subtitle becomes "3 days free, then $34.99/year", a **trial timeline** block ("Today: Full access → Day 2: Charge reminder → Day 3: Trial ends") is rendered under the CTA, and a `disclosureLine` ("Cancel anytime in Settings — trials auto-renew if not cancelled") is shown. Accepts optional `onPurchase` closure for tab-mode integration. Backed by `ProStore` (StoreKit 2) — Buy Now calls `ProStore.purchase(_:)`, Restore calls `AppStore.sync()`, and `isProUser` flips only when `Transaction.currentEntitlements` contains a verified, non-revoked entry. |
| **`ProStore.swift`** | StoreKit 2 manager (`@MainActor` `ObservableObject`). Owns product loading (`Product.products(for:)`), purchase flow (`product.purchase()` + `VerificationResult` check), restore (`AppStore.sync()`), and a detached `Transaction.updates` listener that runs for the app's lifetime so deferred / Ask-to-Buy / refund transactions still update `isProUser`. Entitlement is re-derived from `Transaction.currentEntitlements` — never persisted — so a jailbroken `@AppStorage("isProUser")` flip cannot grant Pro access. Product IDs are two `static let`s at the top of the file; change there and in `Configuration.storekit` in sync. **Trial + grace period state (April 2026):** publishes `hasActiveTrial: Bool`, `trialExpiration: Date?`, `gracePeriodExpiration: Date?`, and `introOfferEligibleProductIDs: Set<String>`. `isEligibleForIntroOffer(productID:)` checks `Product.SubscriptionInfo.isEligibleForIntroOffer(for:)` so returning subscribers don't see "3-day free trial" copy they can't use. `refreshGracePeriodStatus(hasActiveEntitlement:)` observes `Product.SubscriptionInfo.RenewalInfo.gracePeriodExpirationDate` and keeps `isProUser = true` during the billing-retry window — Apple doesn't revoke features immediately on a failed renewal and neither do we. `refreshIntroOfferEligibility()` populates the eligibility set whenever entitlements refresh. `scheduleTrialDayTwoReminderIfNeeded(transactionID:trialExpiration:)` schedules a single T+48h `UNUserNotificationCenter` local notification on trial start reminding the user of the charge date + cancel path; `clearTrialReminder()` fires on transition out of a trial. Trial detection uses `transaction.offerType == .introductory` (the newer `transaction.offer` struct isn't available on our iOS 17.0 deployment target) cross-checked against `productHasFreeTrialOffer(productID:)`, which consults the loaded `Product.subscription?.introductoryOffer?.paymentMode == .freeTrial`. **`loadProducts()` also detects the "no error, zero products returned" case** — most commonly caused by running on a physical device that isn't attached to Xcode (so `Configuration.storekit` isn't active) or by product IDs not being provisioned in App Store Connect yet — and sets a descriptive `lastError` so the paywall alert explains the real reason instead of showing a generic "try again". Debug builds get the full diagnostic (which product IDs were missing, hint to launch from Xcode); release builds get a user-friendly "not available right now" message. **Shipping build note (removed for v1.0):** earlier revisions carried a `#if DEBUG` force-Pro override (`debug.forceProEntitlement` UserDefaults key + `debugSetForcePro`/`debugIsForcingPro` helpers) and a matching toggle in the paywall's dev panel, so engineers could simulate a Pro user without a real StoreKit transaction. It has been stripped from the codebase prior to App Store submission — entitlement is now *only* derived from verified `Transaction.currentEntitlements` (plus the billing-retry grace window). If a similar hook is ever re-added for testing, keep it behind `#if DEBUG` and document its removal before re-cutting a release build. |
| **`ARTrackingManager.swift`** | Runs `ARWorldTrackingConfiguration`, publishes **world-space camera displacement** from a session anchor, floor-projected **heading**, and tracking status/reliability. |
| **`SignalMapViewModel.swift`** | Combines AR position → **map coordinates**, **latency** sampling, **trail** of `TrailPoint`s, **calibration stages**, **landmark re-anchor**, **map rotation** (slider + optional first landmark segment). |
| **`SignalCanvasView.swift`** | Draws placeholder floor plan, heat blobs, blue path, surveyor symbol. Supports **pinch-to-zoom, drag-to-pan**, and an overlay of zoom +/−/recenter buttons. **Tap a trail point** to see a floating info bubble with that point's latency, quality, and capture time; taps on empty space during calibration stages still forward to `onMapTap` for start-point / reanchor selection. Transforms the canvas by `translate(center + pan) * scale(baseContentScale * userZoom) * translate(-center)`; tap coordinates are inverse-transformed so hit-testing stays accurate at any zoom/pan. |
| **`LatencyProbe.swift`** | Measures RTT-ish time via `NWConnection` TCP to `8.8.8.8:53`. |
| **`SignalTrailModels.swift`** | `TrailPoint` (now includes `timestamp: Date` so the survey-review info bubble can show when each sample was captured), `LatencyQuality`, **heat color** derived from latency bands. |
| **`SurveyInsightsEngine.swift`** | **Post-survey insights engine** (April 2026). Pure-Swift analytics over `[TrailPoint]` that runs when the user stops a survey. Produces a `SurveyInsightsReport` with an overall **A-F grade** (weighted 60% coverage mix + 40% median latency, with a p95 spike penalty), latency stats (median, p95, mean, min, max, mean-absolute-delta jitter), coverage percentages (excellent / fair / poor), best + worst spot positions, walked distance in meters, survey duration, a **dead-zone clustering pass** (single-link with a 1.8 m merge threshold, minimum 2 points per zone), and a **router-proximity correlation** (Pearson between distance-from-start and latency) used to guess which end of the walk the router is nearest. Emits a ranked `[SurveyInsight]` list — each a (icon, title, body, severity) card — synthesized from those metrics: coverage breakdown, dead-zone count + worst-zone stats, latency profile (catches the p95-spike-with-healthy-median case separately from a uniformly-slow walk), stability warning (only fires when jitter/median ≥ 0.5 AND jitter ≥ 20 ms so we don't scold a 3 ms wobble on a 25 ms baseline), router-direction hint (requires ≥ 3 m walked and |r| ≥ 0.35), and a tailored "What to do next" recommendation (mesh vs. reposition vs. channel change vs. 5 GHz switch, keyed off dead-zone count, jitter, and median). Returns `nil` when fewer than 8 rated samples exist so short walks don't lie about coverage. |
| **`SurveyInsightsView.swift`** | SwiftUI renderer for `SurveyInsightsReport`. Stacks: (1) a **grade header** (big colored letter-grade circle + headline + score/100 + plain-English summary, stroke color matches grade), (2) a **2×2 stat grid** (excellent %, dead zones, meters walked, sample count), (3) a **coverage mix stacked bar** (green/amber/red ratio with legend showing each bucket's percentage), (4) a **latency range strip** (Best / Median / Worst 5% / Worst tiles colored by severity, with jitter badge in the header), and (5) the **ranked insight cards** from the engine. Themed via `@Environment(\.theme)` so light/dark cards match the rest of the app. Ships with a sibling `SurveyInsightsPlaceholder` view for the "fewer than 8 samples" case telling the user to walk longer. |
| **`MACAddressResolver.swift`** | **MAC address resolver** — reads the iOS kernel ARP table via `sysctl(NET_RT_FLAGS)` and returns a `[IP: MAC]` map. Parses the packed `rt_msghdr` / `sockaddr_in` / `sockaddr_dl` stream with raw byte offsets (the C types aren't bridged to Swift). Also exposes `isLocallyAdministered(_:)` for detecting iOS/Android randomized privacy MACs and `oui(from:)` for extracting the 3-byte OUI. |
| **`WiFiAssistantView.swift`** | **Klaus — WiFi Buddy Assistant** — pseudo-AI chat sheet presented from the Signal tab. Fronted by the Klaus mascot (`KlausMascotView`) in both the sheet header and every assistant bubble avatar. Contains the `AssistantQA` knowledge base (24 curated Q&A entries across Coverage / Reliability / Setup / Streaming / Security / Speed / Gaming), the `WiFiAssistantEngine` keyword matcher (sanitize → tokenize → stopword-strip → score → highest-wins), the `ThinkingBubble` view that plays a 1.4–2.2s "Crunching the bytes…" style animation before each reply, and the SwiftUI chat UI (header, bubble list, suggested-question chips, input bar). Greeting + fallback + thinking phrases are written in Klaus's voice; the 24 answers themselves are unchanged. No LLM, no network, no tokens. Free-tier message counter is persisted via `@AppStorage("klaus.freeMessagesSent")` so closing and reopening the sheet can't bypass the paywall — see the "Chat with Klaus" bullet in the tab-navigation section for the full story. |
| **`KlausMascotView.swift`** | Animated pixel-art mascot used across the Klaus chat experience. Loads one of two transparent animated GIFs from `Assets.xcassets` depending on the view's `DisplayMode` — `.full` (full-body bouncing mascot, `KlausMascot` asset, 336×446) or `.portrait` (face-aligned head-and-shoulders crop, `KlausMascotHead` asset, 336×220). Decodes frames + per-frame delays with `ImageIO` and renders them through a `UIImageView`-backed `UIViewRepresentable` with nearest-neighbor `magnificationFilter`/`minificationFilter` so pixel-art detail stays crisp at any size. Frame lists are cached per-asset-name once per process behind an `NSLock`. The `size` parameter is now always the **bounding-box side length** — for `.full` the mascot aspect-fits into a `size × size` square (so his tall aspect ratio is preserved and he never overflows); for `.portrait` he aspect-fills so the head covers the full square cleanly when the caller clips it to a circle. Critically, `KlausAnimatedImage` now implements `sizeThatFits(_:uiView:context:)` and drops the wrapped `UIImageView`'s content hugging / compression priorities to `.defaultLow - 1`, and sets `clipsToBounds = true`. Without these, SwiftUI would consult the image's intrinsic content size (the 336-point-native-pixel GIF) and Klaus would render at hundreds of points tall inside a 44-pt frame, overflowing avatar circles and dominating the assistant header — the exact bug that made the header mascot appear giant. An `invertColors: Bool = false` parameter applies SwiftUI `.colorInvert()` to the rendered frames, wrapped in a private `KlausColorModifier` `ViewModifier` so the `UIImageView` identity is preserved across toggles and the animation state isn't reset. The flag defaults to `false` now that the GIF asset itself ships with the final white + forest-green palette baked in (previous versions used the artist's original cream/blue/red source and inverted at runtime, which produced muddy orange/brown tones). Used in the assistant header (44 pt, `.portrait`, circle-clipped), each assistant chat bubble avatar (34 pt `.portrait` in a 34-pt circle), and the blue-gradient CTA card on the Signal tab (46 pt `.portrait` in a 46-pt circle). |
| **`OUIDatabase.swift`** | **OUI vendor database** — curated `[OUI: Manufacturer]` lookup covering ~300 common consumer-electronics manufacturers (Apple, Amazon, Google, Samsung, Sonos, Roku, Philips Hue, Ring, Nintendo, Raspberry Pi, Espressif, Tuya, etc.). `manufacturer(forMAC:)` powers the eighth identification layer so devices that evade Bonjour/SSDP/HTTP still get a trustworthy "Made by …" label. |
| **`SurveyReminderScheduler.swift`** | **Re-survey local notification scheduler (April 2026).** `final class` backed by `UNUserNotificationCenter`. `scheduleResurveyReminders(from:)` requests notification authorization lazily — only the first time a real survey completes, never at launch — then schedules three local notifications at **30 / 90 / 180 days** past the reference date ("Has your Wi-Fi changed? Re-survey to see if your dead zones moved."). `replacePendingReminders(referenceDate:)` cancels any previously-scheduled reminders first so the schedule always reflects the *most recent* completed survey. `cancelPendingReminders()` wipes them for e.g. trial expiry or sign-out. Identifier prefix `wifibuddy.resurvey.` keeps our notifications distinct from the trial-day-two and new-device notifiers. Offsets are a single `[Int]` constant — tweak in one place. Fired from `ContentView`'s `.onChange(of: viewModel.calibrationStage)` when the stage transitions to `.finished`. |
| **`NewDeviceAlertNotifier.swift`** | **New-device local notifier (April 2026).** `final class`, companion to the new-device detection in `NetworkScanner`. `postNewDeviceAlerts(_:)` takes the `[DiscoveredDevice]` slice that *just* appeared on a trusted network and posts `UNUserNotificationCenter` notifications. When 3+ new devices show up at once we coalesce into a single "N new devices on your Wi-Fi" notification (avoids spam when the user connects to a network they haven't surveyed in a while); 1–2 new devices get individual alerts with friendly names ("New device on Wi-Fi: <name>"). Does **not** prompt for authorization — it only posts when status is `.authorized / .provisional / .ephemeral`. `SurveyReminderScheduler` is the canonical permission requester, so by the time a user is trusting networks they've already had the permission sheet shown in a context that makes sense. Identifier prefix `wifibuddy.newdevice.`. |
| **`NetworkScanner.swift`** | **Device discovery engine** using four identification layers: **(1) Bonjour service discovery** — browses 14 service types (`_airplay._tcp`, `_smb._tcp`, `_homekit._tcp`, `_companion-link._tcp`, etc.), then **resolves each endpoint to an IP** via `NWConnection` so Bonjour names reliably attach to scanned devices. Bonjour-discovered devices are **always included** even if no TCP ports respond. **(2) TCP port fingerprinting** — probes 21 ports per host **concurrently** (80, 443, 62078, 548, 445, 7000, 8080, 9100, 631, 554, 8008, 8443, 1883, 3689, **22/SSH**, **139/NetBIOS**, **5353/mDNS**, 8888, 5000, 515, 3000); open ports stored on each device and used for **port-based classification** (e.g., 62078 = Apple phone, 548 = Mac/AFP, 22 = SSH/computer, 139 = NetBIOS/Windows, 9100 = printer, 7000 = AirPlay/TV). **(3) TCP liveness check** — for hosts with no open probed ports, a secondary check tries ports 443/80/7/1 and treats **fast connection refusal (TCP RST < 500 ms)** as proof the host is alive; discovers firewalled devices that drop all specific port probes. **(4) Reverse DNS** (`getnameinfo`) resolves hostnames; resolved names also feed into name-based classification. Classification cascade: gateway/self → Bonjour services + names → port fingerprint → hostname keywords → unknown. Supports **trusted device** marking persisted in `UserDefaults`. Uses `getifaddrs` for local IP/mask. Scans in batches of 20 with **800 ms** timeout per probe (increased from 300 ms to avoid dropping slower-responding devices). |
| **`DeviceDiscoveryView.swift`** | **Devices tab**: "Who's on my Wi-Fi?" experience. Shows network info card, scan button, live progress. Device list shows type icons, **Bonjour/DNS names as primary label**, latency badges, **port-hint subtitles** (e.g., "Apple Sync", "AirPlay", "SMB") for devices without Bonjour services, and **"TRUSTED" badge**. Detail sheet shows resolved hostname, **open ports list**, services, trust status, and **Trust / Remove Trust** button. Security assessment counts only **untrusted unknown** devices. Identified devices sorted above unknowns. |
| **`ContentView.swift`** | **Survey tab**: Two layouts: **calibration** (scrollable, full chrome) vs **expanded survey/review** (map-first). Custom gradient/card-styled buttons (no system `.borderedProminent`). Footer shows latency + point count in card tiles. **Reset** uses **confirmation dialog**. Styled to match the dark-card design language of the other tabs. Calibration screen also hosts the **Floor Plan picker** (three-chip row: Blank / Apartment / Upstairs) wired to `@AppStorage("floorPlanTemplate")` and passed into `SignalCanvasView`. **Hard paywall on Start Survey (April 2026):** free users see the full calibration chrome (map, picker, instructions) so they know what they're buying, but `handlePrimaryAction()` intercepts every tap of the primary CTA when `calibrationStage` is `.idle` or `.finished` and presents `PaywallView` as a sheet. No free first survey — a single survey is often all anyone runs, so giving one away would cannibalize trial starts. Mid-flow CTAs (tap start point, re-anchor, stop) are not gated. Owns `@ObservedObject var store: ProStore` passed in by `MainTabView`. Also hosts `LockedInsightsCard` as a safety net in case a trial expires mid-session after a completed walk — in practice free users never see it because they can't finish a survey. `@AppStorage("survey.completedCount")` is still incremented on real completions to drive `SurveyReminderScheduler`. |
| **`FloorPlanTemplate.swift`** | **Sample floor-plan backdrops** (April 2026). `FloorPlanTemplate` enum — `.blank`, `.apartmentMain`, `.upstairs` — each exposing `displayName`, `summary`, `iconName` (for the picker chip), and a `[FloorPlanRoom]` list describing rooms in **normalized** `[0,1]²` coordinates. `FloorPlanRoom` carries `(name, normalizedRect, tint)`; `FloorPlanRoomTint` is a semantic color palette (`living`, `bedroom`, `kitchen`, `bath`, `dining`, `hallway`, `storage`) mapped to the existing earthy canvas colors plus a blue-slate for bathrooms. The **Apartment** template models a 1–2 bedroom main floor (Living Room, Kitchen, Dining, 2 Bedrooms, Bath); the **Upstairs** template models Master + 2 bedrooms + 2 bathrooms + hallway + closet; **Blank** returns an empty room list so the canvas falls back to the plain shell. `SignalCanvasView.drawFloorPlan` dispatches on `floorPlan.rooms`: if non-empty, each room is denormalized into the draw rect, filled with its tint, stroked, given two faint "furniture" rectangles (only when the room is > 24 pt on each axis), and labeled with its name at center (only when the room is ≥ 48×28 pt so labels don't overflow small rooms like Bath 2). Also hosts `FloorPlanCustomRoomNames` — an encode/decode helper for the per-template room-nickname override map (see "Editable room names" below). |
| **`AboutView.swift`** | **Getting Started sheet (April 2026).** Static, read-only reference screen reached from a hamburger button in the top-left of the Speed-tab Wi-Fi header, and auto-presented on first launch via `DashboardView`'s `@AppStorage("hasSeenGettingStarted")` guard. Stacks themed cards: hero (logo + tagline), "What is WiFi Buddy?", a five-tab walkthrough (Speed / Survey / Signal / Devices / Pro — same icon + copy vocabulary as the real tab bar so users can match what they read to what they see), step-by-step how-tos for **Run a Speed Test** and **Survey Your Home**, a Klaus introduction with the mascot avatar, a Pro feature summary, a privacy card ("your data stays on this device"), and a minimal version footer reading only `CFBundleShortVersionString` (e.g. "Version 1.0" — the build-number suffix and the old "Made with care…" tagline were both removed). Navigation title reads **"Getting Started"** (was "About & Guide"); the hamburger accessibility label is "Getting started" to match. Presented via `.sheet(isPresented:)` with `NavigationStack` + inline title and a circular X close button in the top-trailing toolbar slot so the dismiss affordance matches the rest of the app's sheets. All copy is in-file so wording tweaks don't touch other views. Completely static — no network probes, no state beyond the dismiss action — so this sheet is cheap to push and never blocks the rest of the UI. |
| **`Info.plist`** | `NSMotionUsageDescription`, `NSLocalNetworkUsageDescription`, **`NSCameraUsageDescription`** (AR). |

## Tracking & positioning (important details)

### Why AR (not only pedometer + heading)

Indoor **pedometer + compass/yaw** drifts and batches poorly for “real” floor alignment. The app moved to **ARKit world tracking** for smoother, more 2D-faithful motion.

### Critical fix: world-space delta (not matrix translation alone)

**Bug:** Using only the translation column of `inverse(origin) * current` could **collapse motion** so the path looked like a **single diagonal / line**.

**Fix:** In `ARTrackingManager`, position is **`currentWorldPosition - originWorldPosition`** from `camera.transform.columns.3`, with `originWorldPosition` reset on **`reanchorCurrentPose()`**.

### Map projection (`projectToMap` in `SignalMapViewModel`)

- Horizontal plane uses AR **`x`** and **`z`** (meters → points via `pointsPerMeter`, currently **38**).
- **`localX = position.x * pointsPerMeter`** (sign was tuned so **strafe** matched expectation; earlier negation caused mirrored left/right).
- **`localY = position.z * pointsPerMeter`**
- Then rotate by **`storedMapRotationDegrees`** (2D rotation in map space).
- **Anchor:** `mapAnchorOffset` so `currentPosition = mapAnchorOffset + projectToMap(relativeAR)`.

### Alignment without a mandatory “which way is forward” step

Earlier experiments used tap-based forward direction; that was **removed** in favor of:

1. **Start:** tap **start location** on the map → **Start Survey** (locks AR origin at survey start).
2. **Drift correction:** **Re-anchor Here** → user taps **known map location**; anchor updates.
3. **Optional rotation refinement:** On the **first** landmark re-anchor, if both map segment and AR segment are long enough, **`storedMapRotationDegrees`** is set from the angle between **map delta** and **AR horizontal delta** (`dAR` uses the same x/z convention as `projectToMap`).

Thresholds (tunable in code): `minimumLandmarkSegmentPoints`, `minimumLandmarkARPixels`.

## UI / UX flows

### Calibration stages (`CalibrationStage`)

- **`idle`** → **Start Calibration**
- **`selectingStartPoint`** → tap start on map
- **`readyToStart`** → **Start Survey**
- **`surveying`** → live tracking
- **`selectingReanchorPoint`** → after **Re-anchor Here**, tap true location on map
- **`finished`** → after **Stop Survey**; trail/heatmap kept for review

### Post-survey insights (finished stage)

**Problem:** Stopping a survey left the user staring at a heatmap with no explanation — the data was collected, but the *meaning* of the walk wasn't surfaced. A user who just walked their house needs answers like "How's my coverage?", "Where are my dead zones?", "Do I need a mesh system?" — not raw dots on a plan.

**Fix (April 2026):** When `calibrationStage == .finished`, `ContentView` switches to a third layout (`finishedLayout`) — a scrollable review screen with the map pinned at a fixed 300-pt height followed by the full insights panel. `SurveyInsightsEngine.generate(trail:pointsPerMeter:)` runs over the completed trail and returns a `SurveyInsightsReport` that `SurveyInsightsView` renders as a themed card stack. If the walk produced fewer than 8 rated samples, a `SurveyInsightsPlaceholder` is shown instead ("Insights need a longer walk — try walking the space for at least 20–30 seconds so we can read the signal at multiple spots").

**Report contents (visible to user):**

1. **Grade card** — A-F letter grade in a colored circle, plus a one-sentence headline ("Excellent coverage" / "Mixed coverage — room to improve" / etc.) and a plain-English summary paragraph tailored to the grade bucket. Score shown as `N / 100`.
2. **Stat grid (2×2)** — Excellent %, dead-zone count, distance walked (meters), sample count.
3. **Coverage mix bar** — Stacked green/amber/red proportion bar with legend percentages, so a user sees at a glance "78% excellent / 15% fair / 7% poor".
4. **Latency range strip** — Four tiles: Best (min) / Median / Worst 5% (p95) / Worst (max), each colored by severity. Jitter is surfaced in the header as `jitter ±N ms`.
5. **Ranked insight cards** — The engine's `[SurveyInsight]` output. Each is an `(icon, title, body, severity)` tuple drawn as a themed card with the severity tint on the stroke.

**Insights the engine synthesizes:**

- **Coverage breakdown** (always present) — Framed by dominant bucket ("85%+ excellent → great for streaming", "40%+ poor → most of this area is struggling").
- **Dead zones detected** — Fired when ≥ 1 cluster of 2+ poor points within 1.8 m of each other exists. Calls out the worst zone by sample count and latency. 1 zone → warning severity, 2+ → critical.
- **Latency profile** — Has two interesting branches: (a) **"Occasional spikes hurt the experience"** when median ≤ 80 ms *but* p95 > 200 ms (catches the one-bad-room case that a plain average would miss); (b) bucket-based copy for healthy / usable / high median. Always mentions median, average, and p95 so users can separate "feels fine most of the time" from "feels fine on average but drops calls".
- **Stability warning** — Only fires when jitter/median ≥ 0.5 AND jitter ≥ 20 ms. Copy blames interference (microwaves, Bluetooth, neighbor channel overlap, crowded 2.4 GHz) when jitter/median ≥ 1.0, drops to a softer "small movements change your signal noticeably" when it's between 0.5 and 1.0.
- **Router direction hint** — Computes Pearson correlation between distance-from-start-point and latency. Only surfaced when |r| ≥ 0.35 *and* user walked ≥ 3 m (short walks don't have enough leverage to claim a direction). Strong positive = router near start; strong negative = user walked toward router.
- **What to do next** (always present) — A tailored bullet list. Mesh-or-reposition when dead zones ≥ 2 or poor ≥ 30%; "try moving router a few feet / raise it up" for a single dead zone; "switch to a less-crowded 5 GHz channel" when jitter is high; "switch this device to 5 GHz" when median > 150 ms; positive confirmation + suggestion to survey other rooms when grade is A with 0 dead zones.

**Why this shape and not something fancier (e.g., LLM on device):** Everything in the report is derived deterministically from the same sample set the user just saw, so the insights are debuggable and consistent — the same walk always produces the same report. No cloud calls, no API keys, no rate limits, no privacy surface. The knobs (the dead-zone cluster threshold, the jitter ratio cutoff, the grade score weights, the p95-vs-median branch) are all in one file and tunable in one place. When we want smarter reasoning later, the engine is a clean seam to swap or wrap.

### Stop vs reset

- **Stop Survey** (`stopSurvey()`): stops AR + ping loop, sets **`finished`**, **keeps** trail and samples for review.
- **Reset**: clears everything; gated by **`confirmationDialog`** (“Clear map and all samples”) so accidental taps are harder.

### Expanded map layout

When **`usesExpandedMapLayout`** is true (`surveying`, `selectingReanchorPoint`, **`finished`**):

- **Map-first** layout: large vertical space for `SignalCanvasView`, compact header/instructions/footer.
- **`mapContentScale`** (currently **0.72**): baseline uniform **zoom-out** around canvas center so longer walks stay on-screen by default. The user's pinch / zoom-button input in `SignalCanvasView` multiplies on top of this baseline, so "Recenter" returns to this value rather than 1.0.
- Previous default was `0.48`, which users reported made the map feel cramped. Bumping it to `0.72` gives a noticeably roomier default view; users who walk further can pinch out or tap the `–` button to zoom out from there.

Tunable: `mapContentScale` in `SignalMapViewModel`, `minUserScale` / `maxUserScale` / `zoomStep` in `SignalCanvasView`.

### Map interaction (zoom, pan, data-point inspection)

April 2026 rework of `SignalCanvasView` after user feedback that during a survey the map got very small, it was easy to "walk off" the visible region, and there was no way to revisit what was recorded at a specific point on the trail.

Three things are now true of every rendered instance of the canvas (calibration layout and expanded survey layout both):

- **Pinch to zoom** — `MagnificationGesture` tracks the in-progress magnification via `@GestureState pinchDelta` (so pinching feels live without committing), and on gesture end the baseline `userScale` is multiplied by the final magnification and clamped to `[minUserScale: 0.4, maxUserScale: 5.0]`. Effective canvas scale is `contentScale * userScale * pinchDelta`, zoomed about the canvas center.
- **Drag to pan** — `DragGesture(minimumDistance: 0)` does double duty: drags with total translation ≤ `tapSlop (6 pt)` are treated as **taps**; drags beyond that update `@GestureState dragDelta` live and commit to `panOffset` on release. The pinch and drag are composed via `SimultaneousGesture` so two-finger pinch and one-finger drag don't fight each other.
- **Zoom controls overlay (top-trailing)** — three small card-styled buttons stacked vertically: `plus` (zoom in by factor 1.4), `minus` (zoom out by 1/1.4), `scope` (recenter — animated reset of `panOffset = .zero`, `userScale = 1.0`, and clears any selected point). The plus/minus buttons disable when they hit the scale clamp.

**Tap-to-inspect data points.** When a tap (drag distance ≤ `tapSlop`) lands within `pointHitRadius / effectiveScale` of a `TrailPoint.position` (in map-space — the tap is inverse-transformed back through the pan + scale before hit-testing), the canvas shows a `PointInfoCard` overlay:

- Header: colored dot + `LatencyQuality.description` ("Excellent for Gaming/Video" / "Web Browsing Only" / "Dead Zone") and an X dismiss button.
- Two info columns: **Latency** (ms, or `—` if the sample was captured before the first probe landed) and **Captured** (wall-clock time via `DateFormatter.timeStyle = .medium`).
- The card is positioned via `.position(x:y:)` at the point's on-screen location plus a 60-pt vertical offset (flipped to below the point when the point is within 80 pt of the canvas top so the bubble doesn't clip). X is clamped to keep the bubble 100 pt from either edge.

While a point is selected, the canvas highlights it with a larger **yellow waypoint + yellow outer ring** in `drawPath` so the user can see which sample the bubble is describing. Selecting a different point swaps the highlight; the recenter button clears both the bubble and the highlight.

**Tap routing rules.** Taps on empty space still forward to the existing `onMapTap` callback used by `ContentView` → `SignalMapViewModel.handleMapTap` for the calibration stages. The tap coordinate passed through is the **pan-adjusted map coordinate** (`(screen - center - panOffset) / effectiveScale`), so calibration start-point selection and re-anchor selection remain correct when the user has panned or zoomed.

**Why not UIScrollView / MapKit-style?** `SignalCanvasView` is a `Canvas`-based rendering path so it can draw the heatmap radial gradients efficiently; dropping it into `UIScrollView` would lose the per-point rendering and symbol integration. Implementing pan/zoom on top of the existing `CGAffineTransform` applied to the canvas keeps all draw code unchanged (`drawFloorPlan`, `drawHeatMap`, `drawPath`, `drawCalibration`, `drawSurveyor` all still run in the pre-transform coordinate space) and keeps hit-testing a pure-math inverse transform.

### Visual style (canvas)

- **Floor plan backdrop** (drawn in `drawFloorPlan`) — user-selectable via the Floor Plan picker on the calibration screen. `.blank` draws only the plain shell (previous default behavior); `.apartmentMain` and `.upstairs` draw a sample room layout (rooms denormalized from `FloorPlanTemplate.rooms`, filled by `FloorPlanRoomTint.color`, stroked, labeled). Selection is persisted via `@AppStorage("floorPlanTemplate")`. Still a schematic hint, not a real architectural drawing — the goal is to give the heatmap recognizable regions (Living Room / Kitchen / Bedroom 1 / etc.) so the user can tell which room a dead zone is in. **Room labels honor user-supplied nicknames** — see "Editable room names" below.
- **Heatmap:** radial gradients per `TrailPoint` using **`heatColor`** from `SignalTrailModels`.
- **Path:** blue segments + waypoints; **surveyor** uses SF Symbol via Canvas **symbols** when tracking.

## Xcode project

- **`ARTrackingManager.swift`** was added to **`project.pbxproj`** (target **Sources**).
- **`ProStore.swift`** is in the Sources build phase; `Configuration.storekit` is a file reference at the top-level project group (no target membership — per Apple's StoreKit testing rules).
- **`SurveyReminderScheduler.swift`** and **`NewDeviceAlertNotifier.swift`** (added April 2026) are both in the Sources build phase. `UserNotifications` is a system framework so no additional linker entry was required — just the `PBXBuildFile` + `PBXFileReference` + group + Sources-phase quartet.
- The shared scheme (`SignalStrengthPainter.xcscheme`) references `../Configuration.storekit` under `LaunchAction` via `StoreKitConfigurationFileReference`, so **every** debug run in the simulator goes against the local store automatically — no per-developer scheme edit required. To override (e.g. to test against real App Store Sandbox once products are live in App Store Connect), edit the scheme → Run → Options → StoreKit Configuration and set it to "None".
- Build verified with **`xcodebuild`** (generic iOS device; local `DerivedData` in workspace).

## Privacy strings (`Info.plist`)

- Motion, local network, **camera** (AR).
- **`NSBonjourServices`** — declares every mDNS/Bonjour service type the app browses (must stay in sync with `NetworkScanner.bonjourServiceTypes`, currently 19 entries: `_http._tcp`, `_airplay._tcp`, `_raop._tcp`, `_smb._tcp`, `_afpovertcp._tcp`, `_ipp._tcp`, `_printer._tcp`, `_googlecast._tcp`, `_spotify-connect._tcp`, `_homekit._tcp`, `_hap._tcp`, `_device-info._tcp`, `_companion-link._tcp`, `_sleep-proxy._udp`, `_rdlink._tcp`, `_rfb._tcp`, `_amzn-wplay._tcp`, `_apple-mobdev2._tcp`, `_touch-able._tcp`). **Required on iOS 14+** — without it, `DNSServiceBrowse` returns `NoAuth(-65555)` for every browser, Bonjour discovery silently does nothing, and almost every device falls through to the TCP/MAC layers (showing up as generic "Device" entries or — when the MAC is randomized — the old "Private <Type>" label). Symptom in Xcode logs was 19 repeated `nw_browser_fail_on_dns_error_locked [B1..B19] DNSServiceBrowse failed: NoAuth(-65555)` lines per scan. Any time a new Bonjour type is added to the scanner, it **must** also be added to this key or the browser for that type will be dropped.

## README note

The repo **`README.md`** may still describe older **pedometer-only** behavior; the **running app** matches this **MEMORY** / current code, not necessarily the README line-for-line.

## Tab-based UI

- **`MainTabView`** is the root view, replacing the old fullscreen-cover flow.
- **Tabs:** Speed (dashboard), Survey (AR walk), Signal (connection quality), Devices (network discovery), Pro (paywall).
- **Pro tab** is **conditionally shown** based on `@AppStorage("isProUser")`. When `isProUser == true`, the Pro tab is hidden.
- **Pro-gated features (April 2026):** Two features are now behind `ProStore.isProUser`:
  - **Survey tab** — `SurveyProGate` (in `ContentView.swift`) now passes through to `ContentView(store:)` unconditionally; the actual gate has moved **inside** `ContentView.handlePrimaryAction()`. Free users see the full calibration screen (map, floor-plan picker, instructions) so they understand what they're buying, but any tap on "Start Survey" / "Start Calibration" / "New Survey" while `calibrationStage` is `.idle` or `.finished` presents `PaywallView` as a sheet. **No free first survey** — the previous "let them complete one walk, then paywall the insights" approach leaked value because a single survey is often all a user intends to run. Moving the paywall *to the action* rather than *to the tab* keeps the Survey tab browsable (so the user can read chips, see the floor plan picker, admire the Klaus CTA on Signal) without giving away the feature. Mid-flow CTAs (tap start point, re-anchor, stop) are never gated. Surface chrome (Stop / Reset / Re-anchor buttons) is also visible to free users so the UI doesn't feel broken.
  - **Chat with Klaus** (`WiFiAssistantView`) — free users can submit exactly **one** question *per install* (`WiFiAssistantView.freeMessageLimit = 1`). The greeting + starter chips + first reply work normally; after that `isLockedForFreeUser` becomes `true`, the input bar is replaced with a `proUpsellBar` ("You've used your free question" + "Unlock Unlimited Chat" CTA that opens `PaywallView` as a sheet). The cap is enforced inside `submit(_:)` — not the text field — so tapping a suggested chip also counts/blocks, and empty/whitespace sanitization does **not** consume the free message. The counter is only incremented when `!store.isProUser`, so Pro users are never locked. If the user buys Pro mid-chat, the next render swaps the upsell bar back out for the input bar automatically (no sheet dismiss/reopen needed). **Persistence (April 2026 fix):** `userMessagesSent` is stored via `@AppStorage("klaus.freeMessagesSent")`, not `@State`. Previously the counter was `@State` and lived only for the lifetime of the assistant sheet — dismissing and re-opening Klaus constructed a fresh `WiFiAssistantView` with `userMessagesSent = 0`, which let a free user bypass the paywall entirely by just closing and reopening the chat. The persisted counter survives sheet dismissals and app relaunches so the paywall actually gates. For QA, the paywall's DEBUG dev panel gained a "Reset Klaus free-question counter" button that clears the `UserDefaults` key so the free-to-paywall flow can be retested on the same install without reinstalling.
- **DashboardView (Speed tab):** **Live** network topology visualization (every node + both connectors driven by `NetworkTopologyMonitor` — real IPs, live TCP pings, traffic-light coloring, and animated packet-flow dots that run only while each hop is actually carrying traffic), speed test with download/upload/ping/jitter, **post-test Wi-Fi report** (rates connection for streaming, gaming, video calls, home office, and browsing with contextual verdicts), service latency grid (Google, Cloudflare, OpenDNS, Gateway — Gateway tile now pings the actual inferred gateway IP rather than the hardcoded `192.168.0.1`), and a survey quick-action card. The standalone latency test section was removed in favor of the integrated speed test.
- **SignalDetailView (Signal tab):** Animated WiFi signal rings, latency-based quality indicator, metrics grid, **manual refresh button** (re-measures latency on demand), and **context-aware tips** (positive "Signal is Great" card when latency is excellent; actionable "Improve Your Signal" tips when good/poor).
- **DeviceDiscoveryView (Devices tab):** Four-layer identification: **(1) Bonjour** (14 service types, resolved to IPs — always included even if port scan misses them), **(2) TCP port fingerprinting** (21 ports probed concurrently — 62078 = Apple phone, 548 = Mac, 22 = SSH, 139 = NetBIOS/Windows, 9100/631 = printer, 7000 = AirPlay/TV, etc.), **(3) TCP liveness check** (detects firewalled hosts via fast RST), **(4) reverse DNS**. Shows device list with **Bonjour/DNS names**, type classification, port-hint subtitles, response times, **trusted badges**, security assessment (rates safety based on **untrusted** unknowns only), and security tips. Detail sheet shows hostname, **open ports**, services, timestamps, and **Trust / Remove Trust** button. Trusted devices persist in `UserDefaults`. `NetworkScanner` manages all discovery state.
- **PaywallView** is backed by `ProStore` (StoreKit 2). Tapping a plan calls `ProStore.purchase(_:)`; on a verified transaction the `isProUser` `@Published` flips to `true`, `onPurchase` fires, and the tab bar switches back to Speed.

## Paywall / monetization

- **`PaywallView`** is shown as the **Pro tab** for free users (no longer a fullscreen cover on launch).
- **Swipeable feature tour (April 2026):** the top of the paywall is a 3-page `TabView` pager that walks the user through exactly what Pro unlocks — **AR Wi-Fi Survey** (page 1), **Smart Insights** (page 2, the survey report with "Dead zone" / "Move router here" callouts), and **unlimited Klaus AI chat** (page 3). The three pages map 1:1 to the three features that are actually gated behind `store.isProUser` in the app (see "Pro-gated features" list above), so the pitch and the entitlement can't drift apart as features are added — if a new feature is gated, add a fourth page (bump `pageCount` and add another `heroPage(...)` call in `heroPager`). This replaces the previous static hero + single "Visualize your Wi-Fi coverage & optimize your network setup" tagline + three decorative dots that implied a swipe but didn't work. The three dots below the pager are now real — they're tappable (so desktop-minded users or anyone who doesn't discover the swipe gesture can still navigate the tour) and animated (`withAnimation(.easeInOut(duration: 0.25))` on tap, driven by the TabView's own animation on swipe). Per-page copy is intentionally specific ("Walk your home and watch signal strength paint itself onto a live floor plan — no extra hardware needed", "Every survey delivers personalized fixes — where to move your router, add a mesh node, or switch bands", "Chat as much as you like with Klaus — your personal Wi-Fi expert, with clear answers tuned to your network") rather than generic marketing speak, because utility-app benchmarks consistently show that concrete "here's what you get" copy beats abstract benefit language on paywall conversion. The pager is bound to `@State private var currentPage` at the top of `PaywallView`, which was already wired into `pageDots` from an earlier iteration — the new work was the TabView and per-page art, not the state plumbing.
- **Pricing:** Monthly **$3.99** (bumped from $2.99 in April 2026), Yearly **$34.99** (raised from $24.99 alongside the trial rollout — trial-led utility-app benchmarks converge around $34.99–$39.99 with a 3-day trial), shown with ~~$39.99~~ strikethrough + red "Best Deal" badge. The visible prices in the pricing cards are fallbacks — when `Product` metadata loads from the App Store / local `Configuration.storekit`, localized `displayPrice` replaces the hard-coded live-price strings (but not the crossed-out anchor price, which is purely marketing copy and not a real SKU). Two categories of knobs to keep in sync when changing the price:
  - **Live prices** (Monthly + Yearly) — duplicated across three places: `PaywallView.fallbackMonthlyPrice` / `fallbackYearlyPrice`, the `"$X.XX / $Y.YY"` example in `ProStore.loadProducts()`'s doc comment, and `"displayPrice"` on the respective subscription in `Configuration.storekit`. App Store Connect is the fourth source of truth for production users — update it there too before shipping.
  - **Strikethrough / anchor price** (Yearly only) — lives **only** in `PaywallView.fallbackYearlyCrossOut`. It's rendered with a strikethrough as the "was" price to make the live Yearly price feel like a deal; it never hits StoreKit and must not be configured in `Configuration.storekit` or App Store Connect.
- **3-day free trial (April 2026):** both Monthly and Yearly ship with an `introductoryOffer` of type `freeTrial`, `paymentMode = "free"`, `subscriptionPeriod = "P3D"`, `numberOfPeriods = 1` configured in `Configuration.storekit`. Eligibility per product is derived live via `Product.SubscriptionInfo.isEligibleForIntroOffer(for:)` in `ProStore.refreshIntroOfferEligibility()`, so returning subscribers don't see trial copy they can't actually claim. `PaywallView` defaults to Yearly (was Monthly), swaps the CTA to **"Start 3-Day Free Trial"** when the selected product is eligible, shows a trial-timeline disclosure below the CTA ("Today: Full access → Day 2: Charge reminder → Day 3: Trial ends"), and appends a "Cancel anytime in Settings — trials auto-renew if not cancelled" line. The three-card disclosure pattern is Apple's required introductory-offer transparency writ small; it's also the pattern NetSpot / Opal / AllTrails use and it consistently lifts trial-start rate while reducing refund requests.
- **Trial day-2 reminder:** `ProStore.scheduleTrialDayTwoReminderIfNeeded(transactionID:trialExpiration:)` fires a one-shot `UNUserNotificationCenter` notification at `trialExpiration - 24h` when a fresh `.introductory` transaction is detected, reminding the user when they'll be charged and that they can cancel in Settings. Identifier prefix `wifibuddy.trial.day2.`, keyed by transaction ID in `UserDefaults` so we schedule at most once per trial. `clearTrialReminder()` is called when the user either upgrades off the trial or cancels — cheap idempotency so stale reminders never fire against a cancelled trial.
- **Grace period UI:** `ProStore.refreshGracePeriodStatus(hasActiveEntitlement:)` checks `Product.SubscriptionInfo.RenewalInfo.gracePeriodExpirationDate` on every entitlement refresh. If a subscriber is in Apple's billing-retry window, `gracePeriodExpiration` is populated, `isProUser` **stays true** (we do not rip features away mid-renewal), and `MainTabView` renders a `GracePeriodBanner` as a safe-area inset above the TabView prompting the user to update their payment method before the grace period expires. This matches Apple's own UX and avoids the "my subscription didn't auto-renew and suddenly the app locked me out" failure mode that drives refund requests and 1-star reviews.
- **Tab behavior:** "Buy Now" kicks off a StoreKit 2 purchase; on success `isPresented = false` flips back to Speed. "Not now" and X also switch away without charging.
- **StoreKit 2 integration is live** via `ProStore.swift` (April 2026):
  - Product IDs: `com.wifibuddy.pro.monthly`, `com.wifibuddy.pro.yearly` (constants at the top of `ProStore.swift`). Change in one place if you rename.
  - Entitlement source of truth is `Transaction.currentEntitlements` — we never persist `isProUser` in `UserDefaults`. A jailbroken user can flip `@AppStorage("isProUser")` but cannot forge a `VerificationResult.verified` transaction (JWS-signed by Apple, validated on-device). Refunds populate `revocationDate` and `isProUser` drops to `false` on the next refresh.
  - A detached `Transaction.updates` listener runs for the lifetime of the app so Ask-to-Buy / family-sharing / refund transactions that arrive outside a direct purchase flow still update `isProUser`.
  - `restore()` calls `AppStore.sync()` and re-derives entitlements — used by the "Restore Purchase" link.
- **Local StoreKit testing:** `Configuration.storekit` at the repo root defines both subscriptions in a single subscription group ("WiFi Buddy Pro"), and `SignalStrengthPainter.xcscheme` references it via `<StoreKitConfigurationFileReference identifier = "../Configuration.storekit">` under `LaunchAction`. Path is relative to the `.xcworkspace` inside the `.xcodeproj`, which resolves to the repo root. This means Buy + Restore work end-to-end in the simulator without going through App Store sandbox — no Apple ID required. The file is **not** a member of the app target (storekit files never are); it's attached to the top-level project group so it shows up in the Xcode navigator. When the App Store Connect products are configured, the same product IDs in the .storekit file keep local testing consistent with production.
- **Physical-device testing gotcha:** `Configuration.storekit` is a scheme-level debug setting, not an app resource — it's only attached when the app is launched from Xcode with the debugger active. If you build to an iPhone, unplug, and relaunch the app from the home screen, iOS re-runs the binary *without* the storekit config and `Product.products(for:)` returns an empty array (no throw, no network error). That used to surface as "Couldn't load that subscription. Please try again." in the paywall alert; as of April 2026 `ProStore.loadProducts()` detects the empty-result case and `PaywallView.startPurchase()` no longer overwrites that more specific error, so the alert now explains what's actually wrong in debug builds (product IDs missing, hint to launch from Xcode) — see `ProStore.swift` row in the file table. To test buys on a physical device you must either (a) keep the device connected and launch via ⌘R, (b) use the Simulator, or (c) configure the product IDs in App Store Connect and sign in with a Sandbox tester under Settings → App Store.
- **Testing Pro-gated features without StoreKit — removed prior to v1.0 ship:** earlier revisions carried a developer-only toggle in `PaywallView`'s "DEBUG — Developer only" dev panel that flipped `isProUser` directly (via a `debug.forceProEntitlement` UserDefaults key read from a `#if DEBUG` branch in `ProStore.refreshEntitlements()`), plus `MainTabView` kept the Pro tab visible unconditionally in DEBUG and skipped the Pro→Speed auto-switch in DEBUG so the toggle stayed reachable. All of that was removed before App Store submission — entitlement is now exclusively derived from verified `Transaction.currentEntitlements`, the Pro tab always hides once entitled, and the tab auto-switches to Speed on entitlement acquisition in every build configuration. To test Pro-gated features going forward, use `Configuration.storekit` in the Simulator or a Sandbox tester on device.

## Speed Test (download / upload)

- **`SpeedTestManager`** drives a four-phase test: **Server Selection → Ping → Download → Upload**.
- **Server selection phase** (added April 2026 after a user in Arizona reported far-lower WiFi Buddy scores than their ISP app). Runs at the top of every test:
  - Fetches `https://speed.cloudflare.com/meta` (3s timeout, `JSONSerialization`-parsed so missing fields degrade gracefully) to get the **colo code** handling the request (e.g. `PHX`), the **client's geolocated city/region/country/lat-lng**, and the **client ISP (AS organization + ASN)**.
  - Runs a warmup latency probe against `speed.cloudflare.com/__down?bytes=0` (3s timeout) in parallel with the `/meta` fetch; stored as `warmupLatencyMs`.
  - Maps the colo code to a friendly city + lat-lng via `CloudflareColoDirectory` — a static ~80-entry table covering all North-American Cloudflare POPs (US, Canada, Mexico, Panama) plus the busiest global POPs (LHR/AMS/FRA/CDG/MAD/MXP/DUB/ARN, NRT/HND/ICN/SIN/HKG/SYD/AKL/BOM/DEL). Unknown codes fall back to showing the bare 3-letter code.
  - Computes client→colo great-circle distance via a `haversineMiles` helper and stores it in `distanceMiles`. Distance is surfaced to the user as "~N mi away".
  - `SpeedTestServerInfo.isLikelySuboptimal` flags runs where distance > **500 mi** — tuned to flag cross-region hops (e.g. AZ → DFW ≈ 890 mi, a known ISP routing failure mode) without flagging reasonable same-region jumps (AZ → LAX ≈ 370 mi).
  - The selection phase reserves the first **0 → 1/4** of the overall progress bar; latency covers 1/4 → 1/2, download 1/2 → 3/4, upload 3/4 → 1.
  - **Why we do this:** Cloudflare's `speed.cloudflare.com` is Anycast, so it's *supposed* to route to the nearest POP automatically. But BGP/peering quirks at some ISPs send traffic to a distant POP (the AZ→DFW pattern). Without surfacing the chosen colo the user has no way to tell whether a low score is bad Wi-Fi, a congested POP, or an ISP routing failure. ISP speed-test apps always show "Testing to: Verizon — Phoenix, AZ" for this exact reason.
  - **Why not multi-provider server benchmarking?** Cloudflare is the only free public speed-test API with a permissive CORS/HTTP endpoint. Netflix's Fast.com requires a private token flow; Ookla requires a commercial agreement; LibreSpeed is community-hosted and per-server. Surfacing Cloudflare's chosen colo (+ warning when it's far) gets the user 95% of the diagnostic benefit without the integration cost.
- **Latency phase:** 10 HTTP round-trips to `speed.cloudflare.com/__down?bytes=0`; trimmed mean for ping, consecutive-difference mean for jitter.
- **Download phase:** Uses `URLSession.data(for:)` in **8 concurrent streams** inside a `Task.detached` + `withTaskGroup`. Each stream fetches **4 MB chunks** in a loop for the full phase duration. A `TransferCounter` (thread-safe `NSLock`-guarded `Int64`) accumulates completed bytes. Cache-busting query param + `Accept-Encoding: identity` header prevent compressed/cached responses. Only HTTP 200 responses count toward the total.
  - **Why not delegate-based:** An earlier implementation used `URLSessionDataDelegate` / `URLSessionDownloadDelegate` to track bytes, but delegate callbacks never fired for Cloudflare's `__down` endpoint on iOS. The async `data(for:)` approach works reliably.
- **Upload phase:** Same streaming pattern as download — **8 concurrent streams** each POSTing **4 MB chunks** (`application/octet-stream`) to `speed.cloudflare.com/__up` via `URLSession.upload(for:from:)`. Each chunk is only counted after the server responds (HTTP 200), measuring true upload throughput rather than kernel-buffer speed.
  - **Why not delegate-based:** An earlier implementation used 4 fixed 25 MB `uploadTask`s with `didSendBodyData` delegate tracking. The delegate reported bytes buffered by the kernel almost instantly, causing the phase to appear complete in ~1 second. The async streaming approach runs for the full duration.
- **Shared sampling loop** (`sampleTransferPhase()`): Both download and upload use the same sampling method — reads `TransferCounter` every ~250 ms, computes instantaneous Mbps per sample, publishes a **rolling 4-sample window average** as `currentSpeed` for smooth live display.
- **Final speed:** Computed as **total bytes / total elapsed time** (true average throughput). Falls back to sample average if byte count is zero.
- **Duration cap:** Each phase runs up to **12 seconds** then cancels remaining streams.
- **Helper class:** `TransferCounter` (shared byte accumulator for both phases).
- **UI integration in `DashboardView`:** "Speed Test" section appears between the topology card and the Network Latency grid. Three states: empty (no results yet), active (phase indicator with live Mbps gauge + sparkline + progress bar), complete (side-by-side Download/Upload tiles + Ping/Jitter badges). Start/Stop/Test Again button. On completion, a **Wi-Fi Report** card appears below the button rating the connection for streaming, gaming, video calls, home office, and browsing.
- **Server info strip (`serverInfoRow(_:)`):** Shown in all three states once a server has been resolved — `mappin.and.ellipse` icon + provider + colo + city ("Cloudflare PHX · Phoenix, AZ") on the left, distance ("~12 mi away") on the right, and either the client ISP (`Your ISP: Cox Communications`) or an amber warning line (`Your ISP is routing this test far from you — real speeds to nearby services may be higher.`) on a second line. Background and stroke switch from blue-tinted to amber-tinted when `isLikelySuboptimal == true`. During the server-selection phase itself (`.selectingServer`) the body of the card shows a `ProgressView` with "Finding the nearest test server…" instead of the info strip.
- **Phase indicator** now has four steps ("Server", "Ping", "Download", "Upload") with the same active/done/pending styling as before.
- **Standalone Latency Test removed:** The separate 10-ping latency test section (header, sparkline card, button) was removed from the Speed tab. Ping/jitter are now measured as part of the speed test. Service latency probes are triggered automatically when the speed test completes (via `.onChange`).

## Theming & appearance

The app supports **light mode, dark mode, and system default** via a centralized theming system.

### Architecture

| File | Role |
|------|------|
| **`AppTheme.swift`** | Defines `AppearanceMode` enum (system/light/dark), `AppTheme` struct with semantic color properties, `EnvironmentKey` for injecting theme, and `ThemedRootModifier` view modifier. |
| **`SignalStrengthPainterApp.swift`** | Applies `.withAppTheme()` on `MainTabView` to inject the theme and set `preferredColorScheme`. |
| **`MainTabView.swift`** | Defines `AppearanceToggle` struct — a `Menu`-based picker for switching between System/Light/Dark. |
|| **`DashboardView.swift`** | Hosts the `AppearanceToggle` in the Wi-Fi header (top-right of the Speed tab only). |

### How it works

- User preference is persisted via `@AppStorage("appearanceMode")` as an `Int` (0 = system, 1 = light, 2 = dark).
- `ThemedRootModifier` reads the stored preference and the system `colorScheme`, resolves the effective scheme, then injects the correct `AppTheme` into the environment and applies `.preferredColorScheme()` (passing `nil` for system to let iOS decide).
- All views read `@Environment(\.theme)` to access semantic colors like `theme.background`, `theme.cardFill`, `theme.primaryText`, etc.
- **Default behavior:** follows the user's iOS system appearance setting (light or dark).

### Theme color properties

`AppTheme` exposes these semantic colors (each has a dark and light variant):

- `background` — main screen background
- `cardFill` — card/tile background
- `cardStroke` — card border
- `primaryText` — headings / main text
- `secondaryText` — secondary labels
- `tertiaryText` — dimmed labels
- `quaternaryText` — very dim / placeholder text
- `canvasBackground` — survey canvas panel
- `canvasStroke` — canvas border
- `divider` — separator lines
- `buttonText` — text on filled buttons
- `subtle` — subtle background accents

### Appearance toggle

- Located as a small circular button in the **top-right** of the **Speed tab Wi-Fi header** (only visible on the Speed/Dashboard tab).
- Uses a `Menu` that presents three options: System (circle.lefthalf.filled), Light (sun.max.fill), Dark (moon.fill).
- Persisted across launches via `@AppStorage`.
- Previously was an overlay on the entire `TabView` (visible on all tabs); moved to Speed tab only for a cleaner UX on other tabs.

### What stays fixed across themes

- Status indicator colors: green `(0.25, 0.86, 0.43)`, amber `(0.98, 0.78, 0.28)`, red `(0.98, 0.39, 0.34)`.
- Accent color: `.blue` throughout.
- Floor plan canvas interior colors (room fills, wall strokes) — these are illustrative and don't change with theme.
- Paywall hero canvas background (always dark for visual impact).

### Files changed for theming

All 8 view files were updated to replace hardcoded `Color(red: 0.06, ...)`, `.foregroundStyle(.white)`, `Color.white.opacity(...)`, etc. with `theme.*` properties:
- `MainTabView.swift` (tab view + `SignalDetailView`)
- `DashboardView.swift`
- `ContentView.swift`
- `DeviceDiscoveryView.swift` (main view + `DeviceDetailSheet`)
- `PaywallView.swift`
- `SignalCanvasView.swift`

Removed: `.preferredColorScheme(.dark)` from `MainTabView`, `PaywallView`, and preview blocks (theming is now controlled centrally).

## Visual design language (unified across all tabs)

- **Fonts:** Explicit `.system(size:weight:design:)` sizing throughout (no semantic styles like `.headline`/`.caption`).
- **Buttons:** Full-width gradient primary buttons (`blue → blue.opacity(0.85)`), secondary buttons with subtle card-style backgrounds — no system `ButtonStyle` (`.borderedProminent`/`.bordered`).
- **Colors:** Green `(0.25, 0.86, 0.43)`, amber `(0.98, 0.78, 0.28)`, red `(0.98, 0.39, 0.34)` used consistently for status indicators across all tabs.
- **Icons:** SF Symbols in blue icon boxes (`blue.opacity(0.12–0.15)` background) for metric tiles and section accents.
- **Cards:** Rounded rectangles with `theme.cardFill` + `theme.cardStroke`, `cornerRadius: 14–16`.

The Survey tab was restyled to match this language (previously used system button styles and semantic fonts) without changing any core functionality.

## Signal tab improvements

### Manual refresh
- `SignalDetailView` now has a **"Refresh Signal"** button below the quality card.
- Tracks `isMeasuring` state: button shows a spinner and "Measuring..." while a probe is in progress; disabled to prevent double-taps.
- Latency still auto-measures on first `.onAppear`, but the user can re-measure at any time without switching tabs.

### Context-aware insights
- The tips section is now **conditional on latency quality**:
  - **Excellent** (< 50 ms): shows a green **"Signal is Great"** card with positive feedback (no action needed, good for 4K/gaming/calls, suggest Survey tab for full-space verification). Green accent border.
  - **Good / Poor** (>= 50 ms): shows the original **"Improve Your Signal"** card with actionable tips (move closer, map dead zones, restart router, reposition router).
- Computed via `isExcellent` bool derived from `latestLatencyMs`.

### Klaus — the WiFi Buddy mascot

**Klaus** is the pixel-art astronaut-robot mascot that fronts the WiFi Buddy assistant. He lives in `KlausMascotView.swift` and replaces the generic "Ask WiFi Buddy" assistant branding so users feel like they're chatting with a *character* rather than a form. Visual identity is a chunky pixel-art robot with a TV-screen face and a stubby antenna (the source asset the user provided is an animated GIF — 38 frames covering an idle + occasional jump/hop animation).

**Palette (source colors — temporary).** Klaus currently ships with his **original artist-supplied source palette preserved** — cream body `(223, 237, 237)`, light-blue TV-screen face `(153, 194, 219)`, dark-blue eye rectangles `(64, 85, 120)`, pink cheeks `(230, 163, 163)`, red belly-accent square `(245, 79, 79)`, peach/orange antenna tip `(255, 211, 163)`, and near-black outlines `(32, 27, 35)`. The only processing `recolor_frame` (`scripts/generate_klaus_frames.py`) performs now is knocking the brown `(153, 125, 118)` backdrop to `alpha=0` via `BG_TOLERANCE = 18`; every non-backdrop pixel is passed through unchanged.

**Recolor-attempt history (reverted).** An earlier iteration remapped every non-backdrop pixel to a two-tone white + forest-green palette at asset-generation time to match a "WiFi Buddy" brand direction. It went through three tuning rounds — luminance threshold 130, 195, then a combined luminance + chroma split — but none could simultaneously:
  - keep the face-screen background (cool light blue, luminance 185) white, and
  - keep the face detail pixels (pink cheeks at luminance 183, dark-blue eyes at luminance 83, red accent square, orange antenna tip) visible as forest green against that white screen,
  
  without also dragging body shading into the wrong bucket. The combined rule came closest but the resulting face still read as a flat green blob in the app because the face-screen background and the warm face details don't separate cleanly on this specific pixel-art source. The recolor was dropped entirely for now and the source palette restored.

`WHITE` / `FOREST_GREEN` constants, the `LUMINANCE_THRESHOLD` / `DARK_THRESHOLD` / `WARM_CHROMA` tunables, and the luminance/chroma classification branch in `recolor_frame` are **removed** from the script. When a brand palette is revisited later, the intent is to redo the recolor in the *source art* (hand-painting the desired two-tone palette into the original PNG) rather than trying to derive it from the current multi-tone pixel values at generation time. No runtime color inversion is used — `invertColors` defaults to `false` in `KlausMascotView` and the baked-in source palette is what you see.

**Asset pipeline:** `scripts/generate_klaus_frames.py` (Pillow) takes the source GIF at `/Users/jupizarr/.cursor/projects/Users-jupizarr-SignalStrengthPainter/assets/polifolli-robot-*.png` and produces two shipped GIFs in one pass:

1. **`KlausMascot.dataset/klaus.gif`** (full body, 336 × 446, ~113 KB) — every frame knocked out, recolored to white + forest green, then cropped to a union bounding box of the robot across all frames. Bounding box is computed **post-recolor on alpha (not RGB tolerance)**, so dither noise near the backdrop is swallowed by the recolor step and can't inflate the bbox. The tall 336 × 446 aspect accommodates Klaus's jump animation — on resting frames his face sits at `y ≈ 128`, on jump frames (29–33) it rises to `y ≈ 8`.
2. **`KlausMascotHead.dataset/klaus_head.gif`** (head + shoulders, 336 × 220, ~83 KB) — **per-frame face-aligned**. Each recolored+cropped frame has its own top-most opaque `y` found (`_top_y_of_opaque_pixels`) and is then cropped starting from that y downward by `HEAD_HEIGHT_PX = 220`. The result: Klaus's face stays in roughly the same spot inside the portrait frame whether he's resting or jumping, so when this asset is shown inside a circular avatar the face no longer bounces out of the circle. In-place animations (eye/mouth movements, subtle idle breathing) are preserved.

The backdrop color is sampled from pixel `(0, 0)` of the first frame and matched with `BG_TOLERANCE = 18`; bbox padding is `PADDING = 8`.

**Data asset vs imageset:** Both Klaus GIFs ship as `NSDataAsset`s (not imagesets) because SwiftUI's `Image` does not play animated GIFs. Each `.dataset/Contents.json` declares the universal-type-identifier `com.compuserve.gif` so the asset catalog ships the raw GIF bytes verbatim, letting runtime code decode frames via `ImageIO`. `Assets.xcassets` is referenced in `project.pbxproj` as `folder.assetcatalog`, so adding a new `.dataset` subfolder requires no `project.pbxproj` edits.

**`KlausMascotView.swift`** — three pieces:

1. **`KlausMascotView.DisplayMode`** (`.full` / `.portrait`) — selects which data asset is loaded and which `UIView.ContentMode` is used: `.full` → `KlausMascot` + `.scaleAspectFit` (so his tall aspect ratio is preserved inside a `size × size` bounding box); `.portrait` → `KlausMascotHead` + `.scaleAspectFill` (so the ~1.53 : 1 head crop fills a square avatar with minimal empty space, and any minor overhang on the wider axis is hidden by the caller's `.clipShape(Circle())`). Default is `.full` to preserve existing call sites.
2. **`KlausMascotAssets`** — singleton loader that decodes each GIF once per process via `CGImageSourceCreateWithData`, extracts every frame as a `UIImage`, reads the per-frame delay from `kCGImagePropertyGIFDictionary` (`kCGImagePropertyGIFUnclampedDelayTime` preferred, clamped to a `0.02` s minimum so malformed 0-delay frames don't burn CPU), and caches the result in a `[String: AnimationPayload]` keyed by asset name, guarded by an `NSLock`. `assetName(for:)` maps a `DisplayMode` to either `"KlausMascot"` or `"KlausMascotHead"`.
3. **`KlausAnimatedImage`** (`UIViewRepresentable`) — wraps `UIImageView` so the frames can actually animate (`animationImages`, `animationDuration`, `animationRepeatCount = 0`). The image view's layer has `magnificationFilter = .nearest` and `minificationFilter = .nearest` so the chunky pixels stay crisp when scaled up/down — no interpolation blur. Critically it implements `sizeThatFits(_:uiView:context:)` (returning the proposed size), sets `clipsToBounds = true`, and drops the `UIImageView`'s `contentHuggingPriority` and `contentCompressionResistancePriority` to `.defaultLow - 1` on both axes. **Without these**, SwiftUI consults the `UIImageView`'s intrinsic content size — which for a 336 × 446-pixel source image at `scale = 1` is 336 × 446 **points** — and the mascot renders at hundreds of points tall inside what's nominally a 44 × 44-pt frame. That bug is what made Klaus appear as a giant robot overflowing the assistant sheet header (and why the 46-pt "Chat with Klaus" avatar circle showed only his chest, with his face clipped off the top). Forcing the proposed size via `sizeThatFits` and clipping to bounds hard-locks him inside the caller's frame.

**Where Klaus appears:**
- **`WiFiAssistantView`** header — `KlausMascotView(size: 44, mode: .portrait).clipShape(Circle())`, with title "Klaus" and subtitle "Your WiFi Buddy sidekick". Portrait mode guarantees the face is front-and-center in the header instead of showing a full-body mascot.
- **`WiFiAssistantView`** chat bubbles — assistant avatar is `KlausMascotView(size: 34, mode: .portrait)` inside a 34-pt circle with a soft blue `0.12` fill behind him (replacing the previous SF Symbol `wifi` glyph). No more vertical offset nudging — portrait mode + aspect-fill + the head-aligned asset means the face naturally lands in the circle.
- **`MainTabView` → `SignalDetailView` assistantCTA** — the blue-gradient entry point card on the Signal tab reads "Chat with Klaus" + "Your Wi-Fi sidekick, always on call" with `KlausMascotView(size: 46, mode: .portrait)` in a 46-pt white-tinted circle. The face is visible where the old full-body mascot was showing only the torso because the circle was clipping the head off the top.
- Input placeholder reads "Ask Klaus about your Wi-Fi..." so the input bar reinforces the character framing.

**Personality & voice (copy changes only — knowledge base answers unchanged):**
- **Greeting**: "Beep boop — hi there! I'm Klaus, your WiFi Buddy. I live in your router's packets and I know *way* too much about Wi-Fi. Tap a question below or ask me anything."
- **Fallback**: "Hmm, my little antenna didn't quite pick that one up. Here's what I *definitely* know about — tap a question to pick my brain."
- **Thinking phrases** expanded from 10 to 14 entries with four new Klaus-flavored lines: "Booting up my brain", "Recalibrating my dish", "Listening to the SSIDs", "Squinting at the waveform". The pre-existing phrase "Tuning the antenna" was personalised to "Tuning **my** antenna". All phrases still feed through `WiFiAssistantEngine.randomThinkingPhrase()` → `ThinkingBubble` unchanged.
- The 24 curated Q&A answers themselves are left intact — only the framing text (greeting / fallback / thinking / header / CTA) carries the Klaus voice. This keeps answer accuracy stable and the mascot-ification purely UX.

**Not wired** — Klaus is the same deterministic keyword-scored assistant underneath (no LLM, no network, no tokens). There is no state where Klaus reacts to scan results, speed tests, or signal readings yet; he is currently a mascot-plus-FAQ combo, not a situational sidekick.

### WiFi Buddy Assistant (pseudo-AI chat)

A full-screen chat sheet presented from the **"Chat with Klaus"** CTA card inserted between the metrics grid and the tips section on the Signal tab. Entirely offline — no LLM, no network, no tokens — just a curated knowledge base matched by a deterministic keyword scorer. The "AI" framing is purely UX; answers are pre-written and selected by keyword match.

**Lives in `WiFiAssistantView.swift`** with four pieces:

1. **Knowledge base (`WiFiAssistantKnowledge.entries`)** — 24 `AssistantQA` structs covering the most common home Wi-Fi questions (originally 12; expanded to 24 for broader coverage):
   - Original 12: "How can I make my Wi-Fi signal better?" (Coverage), "Why is my gaming slow at certain times of day?" (Gaming — 7–11 PM ISP peak-hour pattern), "Why does my Wi-Fi keep disconnecting?" (Reliability), "Where should I place my router?" (Coverage), "Should I use 2.4 GHz or 5 GHz?" (Setup), "Why is my streaming buffering?" (Streaming), "Is my network secure?" (Security), "What's a good ping for gaming?" (Gaming), "Why is my upload so slow?" (Speed), "Do I need a Wi-Fi extender or a mesh system?" (Coverage), "What's a guest network and should I use one?" (Security), "How often should I restart my router?" (Reliability).
   - Added 12: "Why is my Wi-Fi slower than what I pay for?" (Speed), "Is Wi-Fi 6 or Wi-Fi 7 worth upgrading to?" (Setup), "Why won't my device connect to Wi-Fi?" (Reliability), "Can my neighbors use my Wi-Fi?" (Security), "What's the difference between a modem and a router?" (Setup), "How do I make video calls less choppy?" (Streaming), "Should I change my DNS to Google or Cloudflare?" (Setup), "How do I set up parental controls?" (Security), "Do smart home devices make my Wi-Fi slow?" (Security), "Why is my Wi-Fi fine in some rooms but not others?" (Coverage), "Should I use a VPN on my home Wi-Fi?" (Security), "Should I hide my Wi-Fi network name?" (Security), "How do I port forward for a game or server?" (Setup), "What do download and upload speeds actually mean?" (Speed).
   - Each answer cross-references the relevant app tab where applicable (e.g. "Use the Survey tab to walk your space and see exactly where the dead zones are", "Head over to the Devices tab to see every device on your network").

2. **Matching engine (`WiFiAssistantEngine`)** — deterministic keyword scorer:
   - `sanitize(_:)` — trims, strips control characters via `CharacterSet.controlCharacters`, caps at 300 chars (input hygiene).
   - `tokenize(_:)` — lowercases, splits on `CharacterSet.alphanumerics.inverted`, drops a small English stopword set (`the`, `is`, `my`, `to`, `do`, `have`, `can`, etc. — ~40 entries). Returns a `Set<String>`.
   - `findBestAnswer(for:in:)` — for each `AssistantQA`, counts how many of its `keywords` appear in the token set; returns the highest-scoring entry if `score >= 1`, else `nil`.
   - `relatedQuestions(for:count:)` — picks 3 follow-up questions, same-category first then other categories, attached to every successful reply so users always see "what else to ask".
   - `fallbackSuggestions(count:)` — randomly picks 4 starter questions for the "I'm not sure I caught that" response.
   - `starterQuestions` — fixed list of 4 questions shown under the initial greeting so first-time users can tap instead of typing.

3. **Chat UI (`WiFiAssistantView`)** — presented as a `.sheet` from `SignalDetailView`:
   - **Header**: `AppLogoView(size: 34)` + "WiFi Buddy Assistant" title + "Answers for common Wi-Fi questions" subtitle + circular close (X) button. Themed via `@Environment(\.theme)`. (Previously said "Canned answers…"; the word "Canned" was removed so the assistant reads less like a pre-written FAQ and more like a helpful tool.)
   - **Messages list**: `ScrollViewReader` + `ScrollView` auto-scrolls to the latest message. User bubbles are right-aligned with the same `blue → blue.opacity(0.85)` gradient used by the refresh button. Assistant bubbles are left-aligned with `theme.cardFill` + `theme.cardStroke`, preceded by a small Wi-Fi-glyph avatar circle.
   - **Suggested-question chips**: horizontal scrolling capsule buttons appended under each assistant message (drawn from that message's `relatedQuestions`). Blue text on `Color.blue.opacity(0.12)` fill with a matching stroke.
   - **Input bar** (pinned to bottom): multi-line `TextField` ("Ask about your Wi-Fi…") with `.lineLimit(1...4)` + blue circular send button. Submitting via keyboard return or tapping the send button both call `sendCurrentInput()` → `submit(_:)`, which appends the user message, shows a thinking bubble, and — after a 1.4–2.2s delay — replaces it with the real assistant reply. Tapping a suggested-question chip calls `submit(_:)` directly.
   - **Greeting**: on first appear, seeds one assistant message ("Hi! I'm your WiFi Buddy assistant. Tap a question below or type your own — I've got tips for common home Wi-Fi issues.") with the four `starterQuestions` as chips.

4. **Thinking indicator (`ThinkingBubble` + `WiFiAssistantEngine.thinkingPhrases`)** — every reply is preceded by a transient "thinking" bubble so the assistant doesn't feel instantaneously canned. When `submit(_:)` runs it:
   - Appends the user message, then immediately appends an assistant message with `isThinking = true` whose `text` is a randomly-picked phrase from `WiFiAssistantEngine.thinkingPhrases`: "Crunching the bytes", "Sniffing the packets", "Tuning the antenna", "Scanning the spectrum", "Decoding the signal", "Checking the airwaves", "Measuring the throughput", "Consulting the router", "Polling the access points", "Diagnosing the network".
   - Awaits `Task.sleep` for a `Double.random(in: 1.4...2.2)` delay (on the `@MainActor`), then looks up the thinking message by its `id` and **replaces it in place** with the real `AssistantMessage` (match or fallback). Replacing by `id` rather than appending keeps the list order correct if the user submits another question before the first reply lands.
   - `ThinkingBubble` renders the phrase + an animated `.` / `..` / `...` sequence driven by a `Timer.publish(every: 0.45)` cycling `dotPhase` through `0...3`. It uses `theme.secondaryText` and the same card background as a normal assistant bubble so the transition into the final answer is visually seamless.

**Signal tab wiring** — `SignalDetailView` (in `MainTabView.swift`) gains `@State private var showAssistant` and a blue-gradient `assistantCTA` button card inserted between `metricsGrid` and `tipsSection`. The sheet is presented with `.sheet(isPresented:) { WiFiAssistantView().withAppTheme() }` so the assistant inherits the app's light/dark theme.

**Not wired** — no analytics on which questions are asked, no persistence of chat history across sheet dismissals (each open starts fresh), no localization.

## Device discovery & classification improvements

### Classification fixes (AirPlay + computer co-detection)
- **Problem:** Mac Mini and MacBook Pro were classified as "Smart TV / Media" because AirPlay service was checked before File Sharing / port evidence, and the AirPlay branch defaulted to `.smartTV` without checking for co-existing computer indicators.
- **Fix:** When AirPlay Bonjour service is detected, the classifier now checks for co-existing computer services (File Sharing, Remote Desktop), computer-indicating open ports (548/AFP, 445/SMB, 22/SSH), and computer keywords in Bonjour names before falling back to `.smartTV`.

### Classification fixes (port-based SMB + AirPlay)
- **Problem:** `classifyByPorts` excluded `.computer` when port 7000 (AirPlay) was present alongside port 445 (SMB), because the rule `ports.contains(445) && !ports.contains(7000)` explicitly excluded this combo. Macs commonly have both.
- **Fix:** SMB (445) now implies `.computer` regardless of AirPlay (7000) presence, since Apple TVs do not serve SMB.

### Classification fixes (Nintendo Switch → Game Console)
- **Problem:** Nintendo Switch was classified as "IoT Device" because it only had port 80 open (→ `.iotDevice` by port rules), and hostname-based reclassification only overrode `.unknown`, not `.iotDevice`.
- **Fix:** `resolveHostnames` now allows strong name-based matches (gameConsole, computer, phone, printer, speaker) to override weaker port-based classifications (`.iotDevice`, `.smartTV`).

### Expanded name-based classification keywords
- **Computer:** Added `mac mini`, `macmini`, `mac-mini`, `mac pro`, `macpro`, `mac-pro`, `dell-`, `lenovo`, `hp-pc`, `workstation`.
- **Game Console:** Separated `switch` from `nintendo` to avoid matching "network switch" / "ethernet switch".
- **Speaker:** Added `alexa`, `nest audio`, `nest mini`; removed generic `nest` from speaker (now → IoT unless qualified).
- **Smart TV:** Replaced generic `fire` with specific `fire tv`, `firetv`, `fire stick` to avoid false positives.
- **IoT:** Added `ring`, `doorbell`, `thermostat`; `nest` without audio/mini qualifier now maps to IoT (thermostats, cameras).

### SSDP / UPnP discovery layer (fifth identification layer)
- **Purpose:** Discovers devices that respond to UPnP but not to TCP port scans or Bonjour — particularly Amazon Echo (sleep mode), Ring doorbells/cameras, and other smart home devices.
- **Mechanism:** Sends an M-SEARCH UDP multicast to `239.255.255.250:1900` (standard SSDP), collects unicast responses over ~4 seconds using BSD sockets, parses HTTP-style response headers (SERVER, ST, USN, LOCATION).
- **Integration:** Runs in parallel with Bonjour discovery during scan start. SSDP data stored in `ssdpByIP: [String: [String: String]]`. Passed to `classifyDevice` as a new `ssdpHeaders` parameter. Devices found only via SSDP (not by port scan or Bonjour) are added via `addSSDPOnlyDevices`.
- **Classification:** `classifyBySSDP` matches SERVER/ST header keywords: Amazon/Alexa/Echo → speaker (Fire TV → smartTV), Ring → IoT, Xbox/PlayStation/Nintendo → gameConsole, Roku/Samsung TV/LG/Vizio → smartTV, Sonos/HomePod → speaker, etc.
- **Service hints:** SSDP-discovered devices show service labels like "Amazon Alexa", "Ring", "Roku", "Sonos", "Samsung UPnP", "Google Cast", or generic "UPnP" in the device list and detail sheet.

### Additional Bonjour service type
- Added `_amzn-wplay._tcp` (Amazon Whole-Home Audio) to the 15 browsed service types, with friendly name "Amazon Audio".

### UPnP device description fetching (sixth identification layer)
- **Purpose:** After SSDP discovery, fetches the UPnP device description XML from each device's LOCATION URL to extract `<friendlyName>`, `<manufacturer>`, and `<modelName>`. This is critical for devices like Amazon Echo whose SSDP M-SEARCH responses use generic SERVER headers (e.g., "Linux/4.4, UPnP/1.0, Portable SDK...") that contain no brand-identifying keywords.
- **Mechanism:** Parallel async fetches using `URLSession` with 3-second timeout per device. Simple tag extraction (not full XML parsing) pulls friendlyName, manufacturer, and modelName.
- **Impact on classification:** `classifyBySSDP` now uses manufacturer/model/friendlyName in addition to SERVER/ST/USN headers. Amazon Echo → speaker (via manufacturer "Amazon.com"), Fire TV → smartTV, Ring → IoT, Google Home → speaker, Apple devices → correct type, printers by manufacturer (Epson, Brother, HP, Canon), TP-Link/Belkin/Wemo → IoT.
- **Impact on naming:** UPnP friendlyName is used as the device display name when no Bonjour name is available. E.g., "Justin's Echo Dot" instead of "Unknown Device", "Living Room Roku" instead of "Smart TV / Media".

### Improved SSDP reliability
- M-SEARCH now sends three packets with different ST values (`ssdp:all`, `upnp:rootdevice`, `urn:dial-multiscreen-org:service:dial:1`) with 100ms spacing between them. Catches devices that only respond to specific search targets.

### Additional Bonjour service types for phones
- Added `_apple-mobdev2._tcp` (Apple Mobile Device Protocol v2) and `_touch-able._tcp` (iOS Remote Control) to the 17 browsed service types. These services are advertised by iPhones/iPads even when other services aren't active, improving phone detection.
- Classification maps `_apple-mobdev2._tcp` ("Apple Device") and `_touch-able._tcp` ("Remote Control") to `.phone`.

### Hostname display cleanup
- `DiscoveredDevice.cleanHostname()` strips common domain suffixes (`.local`, `.home`, `.lan`, `.internal`, `.localdomain`, `.fritz.box`, `.gateway`, `.attlocal.net`) from reverse DNS hostnames for cleaner display.
- Applied in both the device list (`deviceDisplayName`) and the detail sheet (`displayName`).
- E.g., "Justins-MacBook-Pro.local" → "Justins-MacBook-Pro" in the device list.

### Bonjour endpoint resolution fix (computer name discovery)
- **Problem:** Devices discovered via Bonjour (e.g., Mac Mini advertising `_companion-link._tcp`, `_airplay._tcp`) were losing their Bonjour names because `resolveServiceEndpoint` only extracted the resolved IP when a TCP connection reached `.ready` state. If the Bonjour service port was firewalled or unresponsive, the connection went to `.failed` and the IP (and thus the Bonjour name) was discarded.
- **Fix (v1):** `resolveServiceEndpoint` now extracts the IPv4 address from `connection.currentPath` in `.failed` and `.waiting` states (not just `.ready`), and also attempts extraction in the timeout handler before giving up. DNS resolution completes before the TCP handshake, so the resolved IP is available in the path even when the connection ultimately fails.
- **Impact:** Computers like Mac Mini that advertise Bonjour services but have firewalled service ports now get their Bonjour sharing name (e.g., "Justin's Mac Mini") attached correctly.

### Bonjour resolution rewrite — NetService-based (device names + consistent counts)
- **Problems (observed by user, April 2026):**
  - Host/device names were still missing for many devices even after the v1 fix above — `NWConnection.currentPath.remoteEndpoint` proved unreliable on iOS, often not exposing the resolved IPv4 form before the connection failed or timed out against firewalled hosts.
  - Device counts varied wildly between back-to-back scans: a scan would find 2 devices, then 5–10 seconds later another scan would find 8–9. Root cause: Bonjour browsers ran for only **3 seconds at the start of the scan**, so on the first scan of a session (where iOS shows the Local Network permission prompt) the 3 s window often elapsed before any Bonjour service was discovered. Subsequent scans then benefited from granted permission + cached mDNS state.
- **Fixes:**
  - **`BonjourResolver` (Foundation `NetService`)** — replaces `NWConnection`-based IP resolution. `NetService.resolve(withTimeout:)` returns the advertised hostname **and** all resolved IPv4 addresses via `netServiceDidResolveAddress(_:)` — no TCP handshake required. Delivers both pieces of identity data (hostname + IP) in a single, reliable callback regardless of whether the device's service port is firewalled. Class retains itself via `selfRetain` until the delegate callback fires (NetService's `delegate` is weak), with a belt-and-suspenders timeout in case NetService hangs.
  - **`BonjourCollector`** — thread-safe `@unchecked Sendable` reference type holding the deduped set of `NWBrowser` results. Bridges `NWBrowser`'s background-queue callbacks into the `@MainActor`-isolated scanner without contaminating the actor's isolation domain.
  - **Long-lived Bonjour browsers** — browsers are now started at the beginning of `startScan()` and left running for the **entire scan duration** (typically 10+ seconds), instead of being cancelled after 3 s. This covers the iOS Local Network permission prompt delay and catches services that announce themselves after an initial delay. Browsers are cancelled in `stopBonjourBrowsers()` just before `resolveCollectedBonjourServices()` runs near the end of the scan.
  - **`applyBonjourMetadataToExistingDevices()`** — after Bonjour resolution, newly-resolved names/hostnames/services are backfilled onto devices that the port scan had already added to the list. Previously, because the port scan ran ahead of Bonjour resolution, a device discovered first by port scan would permanently miss its Bonjour name.
  - **Bonjour hostname surfaces as `device.hostname`** — `bonjourHostByIP` captures the NetService-returned hostname (e.g., `Justins-Mac-mini.local`) and is used as the `hostname` field on every device (port-scan, Bonjour-only, or SSDP-only path), so hostnames display even when reverse DNS fails entirely.
  - **Reduced port-probe batch concurrency** — `batchSize` lowered from 20 to 10 hosts per batch. With 21 probed ports per host, this drops simultaneous `NWConnection` count per batch from 420 to 210, well under iOS's silent connection cap, reducing the number of probes that fail due to overload rather than actually-closed ports.
- **Impact:** Device names now appear reliably for Bonjour-advertising devices (Macs, iPhones, Apple TVs, HomePods, printers, etc.) even when their advertised service ports are firewalled. Device counts are consistent between consecutive scans because Bonjour discovery spans the full scan window.

### Additional Bonjour service types for computers
- Added `_afpovertcp._tcp` (AFP file sharing) and `_rfb._tcp` (Screen Sharing/VNC) to the 19 browsed service types (now 19 total), with friendly names "File Sharing" and "Screen Sharing" respectively.
- Screen Sharing (`_rfb._tcp`) is now recognized as a computer-indicating service in the AirPlay co-detection branch and the general Bonjour classification, alongside File Sharing and Remote Desktop.

### Updated `NetworkScanner` identification layers (now eight)
1. **Bonjour** (19 service types including `_afpovertcp._tcp`, `_rfb._tcp`, `_apple-mobdev2._tcp`, `_touch-able._tcp`)
2. **SSDP / UPnP** (UDP multicast M-SEARCH with 3 ST values, parallel with Bonjour)
3. **UPnP device descriptions** (fetches LOCATION URLs for friendlyName/manufacturer/model)
4. **TCP port fingerprinting** (21 ports)
5. **TCP liveness** (fast RST detection for firewalled hosts)
6. **Reverse DNS** (with improved reclassification logic, hostname cleanup)
7. **HTTP fingerprinting** (fetches HTTP responses + UPnP XML from port 80/8080 for devices still needing identification)
8. **MAC address + OUI vendor lookup** (reads the kernel ARP table via `sysctl(NET_RT_FLAGS)` and maps each MAC's first three bytes to a manufacturer using a curated 300-entry OUI database)

### HTTP fingerprinting (seventh identification layer)
- **Purpose:** Identifies devices that evade Bonjour, SSDP, and hostname-based detection — particularly Amazon Echo speakers in sleep mode, smart home devices with only web ports open, and any device serving HTTP on port 80/8080.
- **Mechanism:** For devices missing a name (`bonjourName == nil && hostname == nil`), still classified as `.unknown`, or lacking manufacturer info, performs parallel async HTTP GET requests to port 80 (or 8080). Analyzes:
  - **HTTP Server header** for manufacturer keywords (Amazon, Google, Roku, Samsung, Sonos, etc.)
  - **HTML `<title>` tag** for device/brand names
  - **HTML body content** for brand-identifying keywords
  - **UPnP XML fallback:** If root path doesn't yield results, tries known UPnP device description paths (`/xml/device_description.xml`, `/rootDesc.xml`, `/description.xml`) and parses `<friendlyName>`, `<manufacturer>`, `<modelName>` using the existing XML tag extractor.
- **Classification:** Maps HTTP-discovered manufacturer/model keywords to device types: Amazon/Alexa/Echo → speaker (Fire TV → smartTV), Google → speaker/smartTV, Roku → smartTV, Samsung TV → smartTV, Sonos → speaker, printer brands → printer, TP-Link/Belkin/Wemo → IoT, Ring/Nest → IoT, Xbox/PlayStation → gameConsole.
- **Naming:** HTTP-derived `friendlyName` (from UPnP XML) or HTML `<title>` is stored as `bonjourName` for display. Manufacturer is stored in `device.manufacturer`.
- **Integration:** Runs after hostname resolution as the final identification pass. Only targets devices that still need identification (3-second timeout per request).

### Port classification fix (web-only ports)
- **Problem:** Devices with only web ports open (e.g., ports 80 + 443) were classified as `.unknown` because the port classifier only handled the single-port-80 case (`ports.count == 1 && ports.first == 80 → .iotDevice`) but not multi-web-port combos.
- **Fix:** Added a catch-all rule: if all open ports are web-only ports (80, 443, 8080, 8888, 8443, 3000, 5000), classify as `.iotDevice` instead of `.unknown`. This correctly identifies devices like Amazon Echo speakers that only expose HTTP/HTTPS ports.

### Manufacturer-based display names
- **Problem:** Devices correctly classified by type but lacking Bonjour names, UPnP names, or useful hostnames showed only generic type names ("Computer", "Phone / Tablet", "Smart TV / Media", "Unknown Device").
- **Fix:** Added `shortName` property to `DeviceType` enum (e.g., "Speaker", "Printer", "Computer", "Media Player", "Device"). When a device has no Bonjour name or hostname but has a manufacturer (from HTTP fingerprinting or UPnP), the display name becomes `"Manufacturer ShortName"` — e.g., "Amazon Speaker", "HP Printer", "Google Media Player", "TP-Link Device". Falls back to the full `deviceType.rawValue` only when manufacturer is also unknown.

### MAC address & OUI vendor identification (eighth layer — eliminates "Unknown Device" entries)
- **Problem:** Even with seven identification layers, a subset of devices — firewalled IoT gadgets, smart plugs, privacy-minded Android phones, generic no-name hardware — still produced generic "Unknown Device" or "Smart TV / Media" labels. This is a *security* issue: users cannot trust or verify what is on their Wi-Fi and may suspect a device is malicious when it is in fact their own unlabeled gear.
- **Solution:** Added an eighth identification layer that reads the kernel's IPv4 ARP table (which we already populated during port probing) and maps each device's MAC OUI (first three bytes) to its manufacturer.
- **New files:**
  - **`MACAddressResolver.swift`** — uses `sysctl(CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO)` to dump the ARP cache. Walks the packed stream of `rt_msghdr` + `sockaddr_in` + `sockaddr_dl` messages with raw byte offsets (the C types aren't bridged to Swift, so the parser uses the stable 92-byte header size and documented sockaddr layouts). Exposes `readARPTable() -> [String: String]`, `isLocallyAdministered(_:)` (detects privacy-randomized MACs via the second-least-significant bit of the first octet), and `oui(from:)`.
  - **`OUIDatabase.swift`** — curated lookup of ~300 consumer-electronics OUIs (Apple, Amazon, Google/Nest, Samsung, Sonos, Bose, Roku, TP-Link, Ring, Philips Hue, Nintendo, Xbox, PlayStation, Dell, Lenovo, ASUS, Raspberry Pi, Espressif, Tuya, Wyze, Eufy, etc.). `manufacturer(forMAC:)` returns the vendor name or `nil`.
- **`DiscoveredDevice` additions:** `macAddress: String?`, `ouiVendor: String?`, `hasRandomizedMAC: Bool`.
- **Integration:** After all previous layers finish, `resolveMACAddresses()` runs once and annotates every device. If the MAC is locally-administered (randomized), we set the flag but skip the OUI lookup (it would be misleading). Otherwise we record the vendor and — if `manufacturer` was still empty — promote the OUI vendor into the display path. A conservative `refineClassificationFromVendor` step upgrades `.unknown` / `.iotDevice` classifications when the vendor + open ports give a strong signal (e.g., Amazon → speaker, HP + port 9100 → printer, Apple + port 548/445/22 → computer, Nintendo → gameConsole).
- **UI changes (`DeviceDiscoveryView.swift`):**
  - Device rows now show a `"Made by <Vendor>"` subtitle when a vendor is resolved and it isn't already part of the title.
  - When a MAC is randomized, the row shows "Randomized MAC (privacy mode)" so the user understands why no vendor is shown.
  - Display-name priority is now: Bonjour → hostname → `<OUI vendor> <ShortName>` → `<manufacturer> <ShortName>` → bare `<device type>` (the `Private <ShortName>` label was removed — see "Randomized-MAC wording" below).
  - Detail sheet adds **MAC Address** and **Made By** rows and a new **"Is this yours?" identification-tips card** that gives context-sensitive guidance — citing the vendor when known, explaining randomized MACs, pointing users at the unplug test and router admin page, and advising a Wi-Fi password change if the device can't be identified and isn't theirs.
  - Detail sheet is now wrapped in a `ScrollView` so the tips card never gets clipped on small phones.
  - Security assessment no longer counts devices with a known vendor (or a randomized-MAC flag) as "mystery unknowns" — knowing the hardware vendor is enough context for the user to recognize the device.

### Custom device names (rename after trusting)
- **Purpose:** Let users keep track of devices that don't advertise a hostname/Bonjour name/DNS — headless IoT gadgets, smart plugs, no-name cameras — by assigning a nickname (e.g., "Kitchen Roku", "Kid's iPad"). Without this, a trusted-but-unlabeled device comes back as "Made by TP-Link" or bare "Device" on every scan and the user has no way to tell which of their trusted devices is which.
- **Model changes (`NetworkScanner.swift`):**
  - `DiscoveredDevice.customName: String?` — nickname that wins over every auto-detected label in display.
  - `NetworkScanner.customNames(for networkID:)` — private lookup into a `[networkID: [ip: nickname]]` store under `UserDefaults` key `customDeviceNamesByNetwork`, read lazily so we stay in sync across launches. See "Per-network trust and nickname scoping" below.
  - `NetworkScanner.setCustomName(_:name:)` — sanitizes input (strips control characters/newlines, collapses whitespace, trims, caps at 40 chars), persists to `UserDefaults` under the **current network's ID**, and updates the live `devices` array. **Only allowed on trusted devices** (guarded by `devices[idx].isTrusted`) — renaming an unvetted device would give the user a false sense of recognition.
  - `setTrusted(_:trusted:)` now clears the stored custom name when a device is un-trusted, so a device the user no longer recognizes stops carrying a nickname that implies they know it.
  - Trust flags and nicknames are applied **at the end of every scan** (via `applyTrustAndCustomNames` called from the `resolveMACAddresses` `defer`), once the gateway's MAC is known and we can safely identify which network we're on. Until then all three `DiscoveredDevice` construction paths (port-scan, Bonjour-only, SSDP-only) build devices with `isTrusted: false, customName: nil`.

### Per-network trust and nickname scoping
- **Problem:** Trust flags and custom nicknames were originally persisted under flat `UserDefaults` keys keyed solely by IP (`trustedDeviceIPs: [String]`, `customDeviceNames: [String: String]`). Moving to a different Wi-Fi network that happened to reuse the same IP schema — **which is essentially every home/office router out there, since the default is `192.168.1.x` or `192.168.0.x`** — caused a **stranger's device** at, say, `192.168.1.10` to silently inherit the "TRUSTED" badge and nickname ("Kid's iPad") that the user had assigned to a completely different device on their home network. Besides the confusing UX, this quietly suppressed the security assessment's unknown-device count on unfamiliar networks, which is exactly when that count matters most.
- **Fix (`NetworkScanner.swift`):**
  - Storage is now **network-scoped**. New keys:
    - `trustedDevicesByNetwork : [networkID: [trustedIP]]`
    - `customDeviceNamesByNetwork : [networkID: [ip: nickname]]`
  - `networkID` is derived from the **gateway's hardware (MAC) address** via the ARP table read by `MACAddressResolver`. Gateway MACs are unique per router and, unlike client devices, are never privacy-randomized on the LAN-facing interface, so they're a stable per-network fingerprint. Format: `"gw:<lowercased-colon-mac>"`. `computeNetworkID(gatewayIP:arpTable:)` returns `nil` — and we treat every device as untrusted — when the gateway MAC isn't resolvable, or if it has the locally-administered bit set (a suspicious randomized router is not something to key trust on).
  - `@Published private(set) var currentNetworkID: String?` is cleared at `startScan` and repopulated inside `applyTrustAndCustomNames`, which runs as a `defer` inside `resolveMACAddresses` so it fires even when the ARP read returns empty (ensuring stale trust from a prior scan doesn't bleed into the UI).
  - `setTrusted(_:trusted:)` and `setCustomName(_:name:)` are both **no-ops** when `currentNetworkID` is nil — we never write persistent trust data without knowing which network it belongs to.
  - **One-shot legacy migration** (`migrateLegacyTrustIfNeeded(into:)`, gated by `trustMigrationCompleted_v2`): on the first scan after upgrade we inspect the pre-upgrade flat data (`trustedDeviceIPs`, `customDeviceNames`) and only carry it forward into the current `networkID` when **at least half** of the legacy trusted IPs are present on this network (strong signal we're on the original network where the trust was granted). Otherwise we **drop** the legacy entries — untrusting everything is a far better failure mode than silently re-trusting strangers on a new network that reuses the same IP schema. Either way we clear the legacy keys so migration runs exactly once.
- **UI (`DeviceDiscoveryView.swift`):**
  - `deviceDisplayName` (list row) and `DeviceDetailSheet.displayName` both check `customName` first, ahead of `isCurrentDevice`/router/Bonjour/hostname/vendor fallbacks.
  - Detail sheet adds a **"Name This Device" / "Rename Device"** button below the existing Trust button, shown **only when `device.isTrusted`**. The Trust button is kept as the only CTA for untrusted devices.
  - Tapping it opens an `.alert` with a SwiftUI `TextField` pre-filled with the current nickname, `.textInputAutocapitalization(.words)`, autocorrection disabled, and a live 40-char cap via `.onChange` (mirrors the scanner's `customNameMaxLength` so the UI can't outrun persistence). Actions: **Save**, **Clear Name** (destructive, only when a name already exists), **Cancel**.
  - After Save/Clear, the sheet dismisses — same UX pattern as the trust toggle.

### New-device alerts on trusted networks (April 2026)
- **Purpose:** Re-engagement hook for a "one-and-done" utility — users who solved their Wi-Fi once don't come back unless something prompts them. A stranger's device joining the home network is the single most compelling prompt.
- **Mechanism (`NetworkScanner.detectNewDeviceArrivals(networkID:)`)**: runs as part of `resolveMACAddresses`, immediately after `applyTrustAndCustomNames` once the current `networkID` is known. Maintains a `[networkID: [lowercased MAC]]` baseline under `UserDefaults` key `seenMACsByNetwork`. On each scan:
  - Skips networks with zero trusted IPs (we don't want to alert on coffee-shop/airport Wi-Fi — those are *supposed* to have unfamiliar devices).
  - Collects every MAC on the current scan except randomized ones, the current device itself, and devices with empty MACs.
  - On the **first-ever** scan of a given network (no baseline key yet) only populates the baseline; does not alert. Otherwise diffs against the stored baseline and forwards any MAC set not previously seen to `NewDeviceAlertNotifier.shared.postNewDeviceAlerts(_:)`.
  - Persists `previouslySeen ∪ observed` back to `UserDefaults` so a transient disappearance doesn't reset the baseline.
- **Why MAC-scoped and not IP-scoped:** Home DHCP leases rotate, so a given device's IP changes. MAC is stable per NIC and survives reconnects. Randomized MACs are excluded deliberately — every iPhone/Android on your network would look "new" every few weeks and the notification would become worthless.
- **Privacy:** Baseline is a `UserDefaults` dictionary keyed by the network's stable fingerprint (`gw:<mac>`); it never leaves the device. Notifications do not include IPs or MACs, only friendly names where available.

### Randomized-MAC wording ("Private Wi-Fi Address")
- **Problem:** Devices that couldn't be categorized and had randomized MACs displayed as `"Private <ShortName>"` (e.g., "Private Phone / Tablet", "Private Device"). The bare word **Private** as a prefix reads as "hidden / suspicious" to a non-technical user and created anxiety about devices that are almost always the user's own iPhone or Android. The subtitle "Randomized MAC (privacy mode)" reinforced the same uneasy framing.
- **Fix (`DeviceDiscoveryView.swift`):**
  - Both `deviceDisplayName` (list row) and `displayName` (detail sheet) no longer prepend "Private" when `hasRandomizedMAC` is true. They fall through to the plain `deviceType.rawValue` instead (e.g., "Phone / Tablet", "Device").
  - The vendor-line subtitle now says **"Uses Private Wi-Fi Address"** — the exact phrase iOS uses in Settings → Wi-Fi → (i). Framing this as a standard Apple privacy feature (rather than as "randomized/privacy mode") reassures users that it's normal iOS/Android behavior.
  - The MAC Address row in the detail sheet labels the MAC as `"(Private)"` instead of `"(Randomized)"`, again matching iOS's own terminology.
  - The "Is this yours?" tips card for randomized-MAC devices now reads: "This device uses a Private Wi-Fi Address, so we can't look up its manufacturer. iPhones, Android phones, Macs, and Windows laptops all turn this on by default — it's almost always one of your own devices, not an intruder."
- **Note:** This UX fix compounds with the `NSBonjourServices` Info.plist fix. Before that Info.plist fix, Bonjour browsing failed entirely (`NoAuth(-65555)` × 19), which meant **every** iPhone/Mac/Apple TV on the network collapsed into the randomized-MAC fallback and users saw a screen full of "Private X" devices. With both fixes applied, Bonjour identifies owned Apple hardware properly, and only the handful of genuinely un-identifiable (and almost always friendly) randomized-MAC devices hit the softened wording.

## Live topology card (Speed tab)

**Problem (user feedback, April 2026):** The "ISP → Router → Your Phone" graphic at the top of the Speed tab looked like a real diagnostic but was entirely static — the ISP always read "Available", the router always read "192.168.0.1" regardless of the user's actual subnet, the device always read "Your iPhone / Connected" even on cellular or offline, and the packet-flow dots on the connectors animated the same way whether the internet worked or not. Users rightly noticed it looked like a logo, not a live readout.

**Fix:** Introduced `NetworkTopologyMonitor` (documented in the architecture table above) and rewired the topology card in `DashboardView` to bind every piece of the graphic to a real measurement:

- **ISP node.** Icon color and status badge come from `topology.wanHealth`, classified off a live TCP ping to `8.8.8.8:53` (the same probe used by `LatencyProbe` throughout the app). Detail line shows the live ISP RTT in ms (e.g. "24 ms"); badge switches between `Online` (< 50 ms) / `Slow` (50–150 ms) / `Degraded` (> 150 ms) / `Unreachable`.
- **Router node.** Detail line shows the device's *real* inferred gateway IP (e.g. `10.0.0.1`, `192.168.1.1`) instead of a hardcoded string. Status badge shows the live gateway RTT in ms, colored by the LAN hop's `LinkHealth`. On cellular the badge reads "N/A" in a neutral tint — there's no local router to ping and a red "Unreachable" badge would misrepresent the state.
- **Device node.** Icon switches between `iphone` / `ipad` / `laptopcomputer` via `UIDevice.current.userInterfaceIdiom`. Label reads "Your iPhone" / "Your iPad" / "Your Mac" via `UIDevice.current.localizedModel`. Detail line shows the device's actual IPv4 from `getifaddrs`. Status badge mirrors `NetworkInterfaceMonitor.shared.status` — `Wi-Fi` (green), `Wired` (blue), `Cellular` (amber), `Offline` (red).
- **Connectors.** The old static dotted line was replaced by `TopologyPacketFlow` — a `TimelineView`-driven overlay that slides three dots left-to-right along the connector at a 1.4 s period when the hop has `isCarryingTraffic == true`, and *pauses* the animation (`TimelineView(...paused: !isActive)`) when the hop is offline or unknown. Connector tint comes from the hop's `LinkHealth` so a degraded WAN leg shows as amber/red while the LAN leg stays green, and vice versa.

**Why the two hops are classified separately:** WAN health is based on `ispLatencyMs` (end-to-end to 8.8.8.8), LAN health on `gatewayLatencyMs` (direct to the router). If the router is responsive but the ISP is down, the LAN hop stays green and the WAN hop goes red — exactly what the user should see when their Wi-Fi is fine but their internet is out, which is a common real-world failure mode and one a static card can never surface.

**Gateway latency tile (service grid).** The grid at the bottom of the Speed tab was probing `192.168.0.1` in `testServiceLatencies()` for every user. It now reads `topology.gatewayIP` so the Gateway tile and the router row in the topology card always agree on which IP is being pinged. A user on a `10.0.0.x` or `192.168.1.x` subnet now gets a real latency number instead of `--`.

**Lifecycle.** `NetworkTopologyMonitor` is started in `DashboardView.onAppear` and stopped in `onDisappear`, so backgrounded tabs don't keep hammering the network every 6 s. A completed speed test also kicks an immediate `topology.refresh()` so the card reflects the numbers the user just saw rather than the ~6 s-old sample from the previous cycle.

## Editable room names (April 2026)

**Problem:** `FloorPlanTemplate` ships with fixed room labels (Living Room / Kitchen / Bedroom 1 / Bedroom 2 / Bath / Master / Bath 1 / Bedroom 2 / Bedroom 3 / Closet / Hallway). Users whose actual space doesn't match — "Bedroom 2" is really the kids' room, "Closet" is really the home office, etc. — had no way to personalize the map, so a heatmap dead zone in "Bedroom 2" didn't map cleanly to a room in their head.

**Fix:** Per-template room nicknames persisted in `UserDefaults`, editable from a sheet on the Survey tab.

- **Persistence (`FloorPlanTemplate.swift` → `FloorPlanCustomRoomNames`)** — stores a `[templateRawValue: [originalRoomName: customName]]` map, JSON-encoded into a single `@AppStorage("customFloorPlanRoomNames")` string so a new `UserDefaults` key isn't needed for every template/room combination. Exposes four static helpers: `decode(_:)`, `encode(_:)`, `names(for:json:)` (returns overrides for one template), `setName(_:for:in:json:)` (writes or clears a single override), and `resetAll(for:json:)` (clears an entire template). `setName` trims whitespace, caps at `maxNameLength = 24`, and treats blank/whitespace-only input or "same as original" as a **clear** (removes the entry), so we never persist empty strings or redundant identity mappings.
- **Canvas rendering (`SignalCanvasView`)** — gained a `roomNameOverrides: [String: String] = [:]` parameter. Inside `drawFloorPlan`, each room's label is resolved as `roomNameOverrides[room.name] ?? room.name`. The original `room.name` remains the stable lookup key so switching the picker away and back preserves overrides, and the same key is used by the engine when referencing rooms.
- **Editor (`FloorPlanRoomNameEditor` in `ContentView.swift`)** — presented from a new "Rename Rooms" pill in the Floor Plan picker card header (only visible when the selected template has rooms, i.e. **not** Blank). The sheet is a scrollable themed list of rows, one per room, with: a room-tint swatch, the original room name as a small caption, a `TextField` for the nickname (pre-populated with any existing override, 24-char cap enforced live via `.onChange`, word-capitalization, `.done` submit label), and an inline `xmark.circle.fill` clear button that appears only when the row has an override. Below the list a destructive "Reset All to Defaults" button appears when at least one override exists for the current template; it clears every nickname for the template but leaves other templates untouched.
- **Wiring** — `ContentView` owns the `@AppStorage("customFloorPlanRoomNames")` string and passes `FloorPlanCustomRoomNames.names(for: selectedFloorPlan, json: customRoomNamesJSON)` through to every `SignalCanvasView` instance (calibration, expanded survey, finished review), so nicknames render consistently before, during, and after a walk.
- **Only shown when it makes sense** — the Rename Rooms pill is gated on `!selectedFloorPlan.rooms.isEmpty`, so the Blank template (which has no rooms) doesn't show an empty editor. The pill lives next to the "Floor Plan" header inside the picker card rather than as a standalone button to avoid adding vertical weight to the calibration screen.

## Survey point density (April 2026)

**Problem:** During a typical walk-around the app was producing very dense trails (sample every ~21 cm / every 120 ms), which made the post-survey review hard to use — tap-to-inspect hits were finicky because adjacent points overlapped in screen-space, and the visual pile-up obscured the underlying heatmap.

**Fix:** Roughly halved the sample density in `SignalMapViewModel`:
- `minimumSampleDistancePoints`: **8 → 16** (≈21 cm → ≈42 cm at `pointsPerMeter = 38`).
- `minimumSampleInterval`: **0.12 s → 0.25 s**.

**Why this doesn't meaningfully hurt accuracy:**
- **Radio reality.** Home Wi-Fi signal strength / latency is driven by walls, metal, and router distance on the meter scale; it doesn't change meaningfully over 20 cm of free-space translation. Two samples 20 cm apart in the same hallway are effectively measuring the same radio environment, so the denser sampling was paying CPU + UI clutter for redundant data.
- **Heatmap math.** Each `TrailPoint` paints a 108 pt (≈2.8 m) radial gradient in `drawHeatMap`. At 8 pt spacing adjacent blobs overlapped by ~92%; at 16 pt spacing they still overlap by ~85%, so the rendered heatmap stays smooth and gap-free.
- **Insights engine.** `SurveyInsightsEngine.generate` requires ≥ 8 rated samples before it returns a report. A typical 20–60 s walk still produces many dozens of rated points at 16 pt spacing, so coverage %s, dead-zone clustering (1.8 m merge threshold), and Pearson router-direction correlation all have plenty of signal to work with. The engine's thresholds are all stated in meters / ms, not sample counts, so they're invariant to this change.
- **Review UX.** Tap-to-inspect uses `pointHitRadius / effectiveScale ≈ 18 pt / scale`. With points now ≥ 16 pt apart, the target hit areas no longer fight each other at default zoom, which is the actual bug the user reported.

## Best/Worst spot markers on the review map (April 2026)

**Problem:** The Survey Insights panel surfaces median, Worst 5%, and Worst latency in the "Latency range" strip, and the engine computes `bestSpot` / `worstSpot` positions internally — but nothing on the map told the user *which* dot out of the dozens in the heatmap corresponded to "Best 18 ms" or "Worst 240 ms". Users could see the stats but had no visual way to tie them back to a room.

**Fix:**
- `SignalCanvasView` gained two optional parameters, `bestSpot: TrailPoint?` and `worstSpot: TrailPoint?`. When provided, a new `drawHighlightedSpots` pass runs **after** `drawPath` (so badges sit on top of the regular blue waypoints) and renders each spot as a filled 14-pt radius colored circle (green for best / red for worst) with a 2.5 pt white border, an SF Symbol glyph inside (star for best, exclamation for worst), and a small capsule "Best" / "Worst" tag 24 pt above/below the marker. The label placement is offset in opposite directions (best above, worst below) so the two badges never stack even when the underlying dots are close together.
- The glyphs are resolved through the `Canvas` symbol path (`BestSpotBadge` / `WorstSpotBadge` views tagged with static IDs), matching how `SurveyorSymbol` is rendered — keeps the icons crisp at any zoom level instead of approximating them with `Path`.
- When the user taps a badge, the regular `PointInfoCard` inspect flow still works: if `selectedPointID == best.id` (or `worst.id`), the marker is suppressed so the yellow inspect ring isn't hidden behind it. If `bestSpot.id == worstSpot.id` (degenerate single-sample case) only the best badge is drawn.
- `ContentView` computes `highlightedSpots: (best: TrailPoint?, worst: TrailPoint?)` inline (single `min`/`max` pass over the rated trail) and gates it on `calibrationStage == .finished` — during the live walk the extremes jump around as new pings arrive, so showing the badges only in review avoids a distracting "best/worst" flicker while surveying. The pair is passed through `mapCanvas(contentScale:)` so every finished-layout canvas instance gets them.
- `SurveyInsightsView.latencyRange` gained a `mapLegendHint` row underneath the four latency tiles — two small badges (green star + red exclamation, matching the map markers pixel-for-pixel in color) plus "marked on map" caption. Without this hint the badges on the map are easy to miss; the legend makes the Best/Worst tiles read as a clickable legend for the map above.

**Why not compute the extremes from the already-generated `SurveyInsightsReport.bestSpot`/`worstSpot`:** The report is `nil` when the walk has < 8 rated samples (the engine's minimum for drawing conclusions). For short walks we still want to mark the single best/worst dot visually even if the full report is withheld. Running the tiny `min`/`max` loop in `ContentView` decouples the badges from the report's availability.

## Swift 6 / strict-concurrency warning sweep (April 2026)

Cleared 82 Xcode warnings in a single pass (none were behavioral regressions — all were either stylistic, pre-Swift-6 isolation warnings, or duplicate dictionary keys that silently last-write-wins at runtime). Kept as a reference so future work doesn't re-introduce the same patterns:

- **`OUIDatabase.entries`** was a literal `[String: String]` with ~70 duplicate keys (one OUI can appear under multiple vendor sections, e.g. `40:A8:F0` under Apple / HP / Intel). Swift 5.9+ warns on every duplicate. Refactored into a `rawEntries: [(String, String)]` tuple array plus `Dictionary(rawEntries, uniquingKeysWith: { first, _ in first })` — keeps the *first* listed owner (which is the curated-by-most-common-brand order) and eliminates the warnings. Adding more entries in the future is still safe; duplicates just silently defer to whoever was listed first.
- **`SignalMapViewModel.startPingLoop`** — the `Timer.scheduledTimer` closure is nonisolated, so touching `@MainActor`-isolated `self.latencyProbe`, `self.latestLatencyMs`, and `self.refreshLatestSample()` from inside it raised three actor-isolation warnings. Wrapped both the timer body and the `LatencyProbe` completion callback in `Task { @MainActor [weak self] in … }` — `LatencyProbe.measureLatency` already dispatches its completion on `DispatchQueue.main`, but Swift's concurrency checker can't see through a `@escaping` closure signature, so the explicit main-actor hop is needed.
- **`ProStore.monthlyProductID` / `yearlyProductID` / `allProductIDs`** — these are compile-time constants but the `@MainActor` class annotation propagated to them, so SwiftUI views and `@ViewBuilder` bodies couldn't reference them without a main-actor hop. Marked `nonisolated static let` since they're immutable `String`/`Set<String>`.
- **`DashboardView`** — `.onChange(of:perform:)` with a single-parameter closure was deprecated in iOS 17; switched to the two-parameter `{ _, newPhase in }` form. Also removed an unused `let ul = speedTest.uploadSpeed` in `overallSummary` (the `activityRatings` copy still uses it).
- **`NetworkScanner.probeLivenessRefused` and `probePort`** — the inner `finish(_:)` helpers are called from two different thread contexts (the `NWConnection` state handler and a `probeQueue.asyncAfter` timeout block), so Swift 6 wants them `@Sendable`. The existing `var hasResumed = false` + `NSLock` pattern doesn't satisfy `@Sendable` (mutable local `var`s can't be captured). Added a small `private final class AtomicBool: @unchecked Sendable` one-shot latch at the top of the file and marked both `finish` helpers `@Sendable`. `@unchecked Sendable` is justified because all mutation is guarded by the internal `NSLock`.
- **`INFOPLIST_KEY_UIRequiresFullScreen = YES`** added to both Debug and Release build configurations in `project.pbxproj`. Silences the "All interface orientations must be supported unless the app requires full screen" warning. Full-screen is also the correct posture for an AR-based survey app — Stage Manager / Split View would break `ARWorldTrackingConfiguration` anyway.

Clean rebuild now reports zero warnings. `SWIFT_STRICT_CONCURRENCY` is still set to `minimal`; bumping it to `complete` or `targeted` would likely surface more Timer/DispatchQueue closure patterns — if that's attempted, expect similar `Task { @MainActor in … }` wrappers around every Combine `sink` and Timer body in `SignalMapViewModel` and `NetworkTopologyMonitor`.

## App Store readiness pass (April 2026)

Locked the project down for App Store Connect submission. All of the blockers that would have bounced a fresh `com.example.*` build were cleaned up in one pass. The app **builds cleanly for iOS Simulator** (`xcodebuild … build` → `** BUILD SUCCEEDED **`) with `com.wifibuddy.app` as the bundle id and the three new resources (`PrivacyInfo.xcprivacy`, `PrivacyPolicy.md`, `TermsOfUse.md`) verified inside the packaged `.app`.

### Identity and build settings (`project.pbxproj`)

- **Bundle ID** renamed from `com.example.SignalStrengthPainter` → `com.wifibuddy.app` in both the Debug and Release configurations of the `SignalStrengthPainter` target. The StoreKit product IDs (`com.wifibuddy.pro.monthly` / `com.wifibuddy.pro.yearly`) already lived under the same `com.wifibuddy.*` namespace, so nothing else needed renaming in `ProStore.swift` or `Configuration.storekit`.
- **Removed six dead `INFOPLIST_KEY_*` build settings** from both configs: `INFOPLIST_KEY_UIApplicationSceneManifest_Generation`, `INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents`, `INFOPLIST_KEY_UILaunchScreen_Generation`, `INFOPLIST_KEY_UIRequiresFullScreen`, `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`, `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone`. These were silently ignored because the target uses a static `Info.plist` (`GENERATE_INFOPLIST_FILE = NO`) — Xcode only merges `INFOPLIST_KEY_*` when it's generating the plist for you. Keeping them around was misleading; the static plist is now the single source of truth for every Info.plist key.

### `Info.plist` additions

Added four new keys (everything directly in the plist since `INFOPLIST_KEY_*` is a no-op under this build config):

- **`ITSAppUsesNonExemptEncryption = <false/>`** — the app only uses standard HTTPS/TLS (no custom crypto, no proprietary VPN, nothing export-controlled). Setting this declaratively in Info.plist skips the App Store Connect encryption questionnaire on every build upload, which otherwise has to be answered manually for each TestFlight build.
- **Orientation locked to portrait (iPhone-only build)**:
  ```xml
  <key>UISupportedInterfaceOrientations</key>
  <array><string>UIInterfaceOrientationPortrait</string></array>
  ```
  Why: `ARWorldTrackingConfiguration` anchors the map projection at Start Survey and converts the user's walk into floor-projected `(x, y)` positions using the camera transform. A landscape flip mid-walk rotates the projection matrix underneath the heatmap and visibly tears the trail. There is no `~ipad` override anymore — see the iPhone-only retarget below.
- **`UIRequiresFullScreen = <true/>`** — already declared indirectly by the (now-removed) `INFOPLIST_KEY_UIRequiresFullScreen = YES` build setting; promoted to the plist so it's explicit. Also a hard requirement for the AR session: `ARWorldTrackingConfiguration` pauses the moment its view shrinks (which is what would happen under iPad Stage Manager / Split View if the app were ever made universal again).
- **`UIRequiredDeviceCapabilities = [arkit, wifi]`** — makes the app invisible on devices that lack ARKit rather than letting users download an app whose marquee feature is a dead screen. `wifi` is technically redundant (every iOS device has Wi-Fi) but documents intent.

Left untouched: the existing `NSMotionUsageDescription` / `NSLocalNetworkUsageDescription` / `NSCameraUsageDescription` privacy strings and the 19-entry `NSBonjourServices` array (which **still must stay in sync** with `NetworkScanner.bonjourServiceTypes` — iOS silently drops browsers for any service type not listed in Info.plist, so Bonjour discovery would start failing the moment the list drifts).

### Privacy Manifest (`SignalStrengthPainter/PrivacyInfo.xcprivacy`)

New file — mandatory for all App Store submissions since May 1, 2024. Without it, `altool`/ASC rejects the upload before the build ever reaches review.

```xml
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

- **`NSPrivacyTracking = false`, empty `NSPrivacyTrackingDomains`** — the app has zero analytics, zero third-party SDKs, zero ad networks. No IDFA request, no AppTrackingTransparency prompt needed.
- **Empty `NSPrivacyCollectedDataTypes`** — "Data Not Collected" answer to every App Privacy question on the ASC App Privacy form. All survey history, device trust flags, Klaus chat transcripts, floor-plan room renames, and Pro entitlement cache are stored client-side only, never uploaded anywhere.
- **`NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`** — "Declare this reason to access user defaults that are only used by the app itself and/or its App Extensions and/or App Clips that are in the same group as the app." This covers every `@AppStorage` read/write across the codebase (theme preference, first-launch flag, trusted-device dictionary, custom room names, Klaus free-message counter, `isProUser` entitlement cache, etc.).
- **No other API reason codes** — the app doesn't use `NSUserDefaults` for cross-app data sharing (no App Groups), and doesn't touch any of the other four categories that now require reason codes (disk space, file timestamp, system boot time, active keyboards). If a future feature adds any of those (e.g., "available disk space" banner on the dashboard), the corresponding reason code must be added here **or** the upload will be rejected at submission time.

Wired into the Xcode project as both a `PBXFileReference` and a `PBXBuildFile` in the Resources build phase, so it ships inside the `.app` bundle — confirmed by inspecting the built `.app` after the `xcodebuild` pass.

### Bundled legal documents

To satisfy App Review Guideline 3.1.2 (auto-renewing subscriptions must expose Privacy Policy and Terms of Use directly from the paywall) without standing up a marketing website, both documents ship as Markdown files in the app bundle and are rendered in-app.

- **`SignalStrengthPainter/PrivacyPolicy.md`** — single-page policy. Lead line is "Your data stays on your device." Covers: no accounts / no servers / no analytics / no ads, what's stored locally (survey trails, topology snapshots, trusted device list, Klaus chat history, preferences), what outbound traffic the app does make (Cloudflare-backed speed test, TCP ping to `8.8.8.8:53` / `1.1.1.1:53` / OpenDNS / gateway, Bonjour + SSDP multicasts on the LAN — all non-identifying), StoreKit purchases are handled by Apple (Apple's privacy rules apply, not ours), local notifications, the three required permissions (Camera / Motion / Local Network), and a contact email placeholder.
- **`SignalStrengthPainter/TermsOfUse.md`** — ingests Apple's standard EULA by reference and then adds the subscription-specific terms: product names + prices (`WiFi Buddy Pro` Monthly `$3.99` / Yearly `$34.99` with a 3-day free trial on yearly when eligible), auto-renewal language with the explicit 24-hour-before-period-end cancellation window, billing charged to Apple ID, no refunds for partial periods, "what Pro unlocks" (unlimited AR surveys, unlimited Klaus chat, full insights report), acceptable use (only scan networks you own or have permission to scan), an accuracy disclaimer ("signal quality and device discovery are best-effort; don't use this to make contractual claims about coverage"), and liability limits.
- **`SignalStrengthPainter/LegalDocumentView.swift`** — new SwiftUI `View` that reads the bundled `.md` file from `Bundle.main.url(forResource:withExtension:)`, parses it with `AttributedString(markdown:)` (stdlib, no 3rd-party dependency), and renders it in a `ScrollView` inside a `NavigationStack` with a close button. Has a `Kind` enum (`.privacyPolicy` / `.termsOfUse`) that drives both the nav title and the resource name lookup, and conforms to `Identifiable` so it slots directly into `PaywallView.sheet(item:)`. Works entirely offline — important because the paywall might be shown on a device whose Wi-Fi is broken (which is literally the reason they'd use this app). A `fallbackMessage` view renders a "Couldn't load document" copy + the support email if the bundle lookup ever fails, so the sheet is never visibly empty.

### Paywall disclosures (`PaywallView.swift`)

Replaced the old one-line `"Subscription auto-renews. Cancel anytime in Settings."` with the full Apple-required language plus tappable policy links:

- **`@State private var legalDoc: LegalDocumentView.Kind?`** drives a single `.sheet(item:)` attached to the root `ZStack`, so whichever legal doc the user taps opens with `.withAppTheme()` applied (same theme plumbing as every other sheet in the app).
- **`disclosureLine`** now builds a truthful sentence by pulling the live `displayPrice` off `store.product(for:)` for whichever plan is currently selected, falling back to the hard-coded `fallbackMonthlyPrice` / `fallbackYearlyPrice` constants if StoreKit hasn't finished loading. The sentence covers: product name + price/period, trial prelude when `trialAvailableForSelection && selectedPlan == .yearly`, Apple-ID billing at confirmation, auto-renewal at the same price/period, the 24-hour-before-period-end cancellation window, the 24-hour-before-period-end charge window, cancel path (Settings → Apple ID → Subscriptions), and the unused-trial-forfeiture clause. This is the exact language App Review cross-checks against guideline 3.1.2(a).
- Under that, a compact horizontal row with two `Button`s: **Privacy Policy** and **Terms of Use**, both tinted `.blue` so they read as links, separated by a `•` in `theme.tertiaryText`. Tapping either sets `legalDoc = .privacyPolicy` / `.termsOfUse` which presents the sheet. Kept at 11 pt / medium weight — visible enough to read and tap, not so big that it competes with the CTA.

No change to the existing "Restore purchase" / "Not now" bottom links block below.

### Why "just link" instead of hosting externally

User explicitly picked `just_link` for the legal-doc strategy. Bundling them as Markdown means:
1. No web hosting / DNS / cert rotation to maintain.
2. Works offline — the paywall doesn't get stranded on a plane / hotel Wi-Fi.
3. Versioned with the code: when Terms change, they ship in the same commit as the feature change that justified the edit, so there's no legal/product drift between what the binary says and what a website says.
4. App Review checks the links during review by tapping them on-device, which bundled Markdown satisfies as well as any remote URL would.

Downside: any material terms change requires a new TestFlight build rather than just editing a web page. Acceptable tradeoff given the app doesn't have lawyers-on-call and rarely rewrites terms.

### README refresh

The repo's root `README.md` was stale (old bundle ID, wrong yearly price, no mention of AR / survey / topology / Klaus / new legal docs). Rewrote it to match April 2026 reality:

- Corrected bundle ID to `com.wifibuddy.app` and yearly price to `$34.99` (with `~~$39.99~~` strikethrough reference copy).
- Project-layout table gained entries for `LegalDocumentView.swift`, `AboutView.swift`, `PrivacyInfo.xcprivacy`, `PrivacyPolicy.md`, `TermsOfUse.md`, plus an expanded Info.plist description covering the new orientation / full-screen / encryption / device-capabilities keys.
- **New "Legal documents"** section explaining the bundled-markdown + `LegalDocumentView` strategy and why it satisfies guideline 3.1.2.
- **Expanded "Privacy and permissions"** section covering both the four Info.plist additions and the full Privacy Manifest (tracking / collected data / API-reasons) so a new contributor can see what Apple-facing promises the build has baked in.
- **New "App Store submission checklist"** at the bottom listing the external App Store Connect work that still needs to happen before the first build can be submitted (see "Remaining external work" below).

### Remaining external work (outside the codebase)

Everything in-codebase is done. The following ASC dashboard steps still need a human:

1. Create the app record in App Store Connect using `com.wifibuddy.app` as the bundle ID.
2. Configure both subscriptions in the same subscription group with the prices and free-trial rules that the `TermsOfUse.md` document currently commits to (`Monthly $3.99`, `Yearly $34.99`, 3-day free trial on yearly).
3. Upload screenshots at 6.7" / 6.5" / 5.5" iPhone per the current App Store spec. **No iPad screenshots are required** — the app is targeted iPhone-only (`TARGETED_DEVICE_FAMILY = "1"`); see the "iPhone-only retarget" entry below.
4. Fill in the App Privacy questionnaire — answer **"Data Not Collected"** for every category. This must match `PrivacyInfo.xcprivacy`; if they disagree, review will surface the inconsistency and reject.
5. App Review Notes suggested copy: *"Survey tab uses ARKit; please test on a physical device for world tracking. Paywall with Privacy Policy + Terms links is on the Pro tab; Klaus chat is on the Signal tab."*
6. Archive + upload via Xcode → Product → Archive → Distribute App → App Store Connect.

## Public Support + Privacy Policy URLs for App Store submission (April 24, 2026)

App Store Connect requires two **publicly reachable URLs** at submission time:
a **Support URL** (a page listing how to contact you) and, because WiFi Buddy
ships auto-renewing subscriptions, a **Privacy Policy URL** that hosts the same
text users see in-app. Apple wants the in-app and hosted policies to match — a
mismatch (different email, different "Last updated" date, different scope of
collected data) is a common rejection reason during review.

Rather than stand up a marketing site or GitHub Pages just to host two static
docs, two new top-level Markdown files were added to the repo root and pushed to
`main`. GitHub serves them at public `/blob/main/...` URLs that App Store Connect
accepts as both URL fields without any additional infrastructure.

### Files added at repo root

- **`Support.md`** (root) — public support page. Lists `justin.dev@gmail.com`
  as the support email (rendered as a `mailto:` link), tells users what info to
  include when reaching out (device model, iOS version, app version), and
  answers the support questions Apple Reviewers and end users hit first:
  how to cancel a subscription / free trial via iOS Settings → Apple ID →
  Subscriptions, how to **Restore Purchase** from the Pro tab, the
  "we don't collect your data" summary with a relative link to
  `PrivacyPolicy.md`, why the Survey tab needs Camera (ARKit world tracking;
  feed never recorded/transmitted), and why the Devices tab needs Local
  Network (Bonjour + SSDP + TCP probes; traffic never leaves the router).
- **`PrivacyPolicy.md`** (root) — byte-for-byte the same prose as the
  bundled `SignalStrengthPainter/PrivacyPolicy.md` that ships in the app's
  `LegalDocumentView`, except for the contact email
  (`justin.dev@gmail.com`) and the "Last updated" date (April 24, 2026).
  Apple Review compares the URL against the in-app document; keeping the
  text identical prevents the "your hosted policy says X but the in-app
  policy says Y" rejection.

### In-app `SignalStrengthPainter/PrivacyPolicy.md` synced

The bundled in-app privacy policy was edited in the same commit so its
contact email and date now match the root-level public copy:

- Contact line changed from `support@wifibuddy.app` (a placeholder that
  was never wired up to a real mailbox) to `justin.dev@gmail.com`.
- "Last updated" bumped from April 23, 2026 to April 24, 2026.

No other prose changed, and `LegalDocumentView.swift` already reads the
file by `Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "md")`,
so the in-app paywall link automatically picks up the new text on the next
build with no code changes.

### Public URLs to paste into App Store Connect

- **Support URL** (App Information → General Information → Support URL):
  <https://github.com/justinpizar13/SignalStrengthPainter/blob/main/Support.md>
- **Privacy Policy URL** (App Privacy → Privacy Policy URL, also surfaced
  next to subscription metadata):
  <https://github.com/justinpizar13/SignalStrengthPainter/blob/main/PrivacyPolicy.md>

The `/blob/main/` GitHub Markdown viewer is sufficient for review. If a
cleaner URL is wanted later, **GitHub Pages** (Settings → Pages →
Deploy from branch → `main`, root) will serve the same files at
`https://justinpizar13.github.io/SignalStrengthPainter/Support.md` etc.
without any code changes.

### Why two `PrivacyPolicy.md` files now exist (and that's fine)

- `PrivacyPolicy.md` (repo root) — served publicly by GitHub for the
  App Store Connect URL field.
- `SignalStrengthPainter/PrivacyPolicy.md` (target source dir) — bundled
  as a Copy Bundle Resource, read at runtime by `LegalDocumentView` for
  the paywall's "Privacy Policy" link.

They are intentionally kept in sync. If the privacy policy text ever
changes, **update both** in the same commit and bump the "Last updated"
date in both. A simple `diff PrivacyPolicy.md SignalStrengthPainter/PrivacyPolicy.md`
should print nothing (other than the header `# Privacy Policy` line which
is the same; both copies are identical end-to-end as of this commit).

The root-level `Support.md` does **not** have a bundled in-app twin —
the in-app equivalent is `AboutView.swift`'s "Getting Started" sheet,
which serves the same role (FAQ + how to use the app + contact info)
inside the binary, while `Support.md` exists purely so App Store Connect
has a URL to point at. If the support email ever changes, update it in
three places: `Support.md`, `PrivacyPolicy.md` (root), and
`SignalStrengthPainter/PrivacyPolicy.md` (bundled).

## Possible follow-ups (not done here)

- **Register the two product IDs in App Store Connect** (`com.wifibuddy.pro.monthly`, `com.wifibuddy.pro.yearly`) as auto-renewing subscriptions in a single subscription group before flipping the build on in production. Local simulator testing already works via `Configuration.storekit`, but `Product.products(for:)` will return empty on TestFlight / App Store builds until the products exist in App Store Connect. If different IDs are preferred, edit the two `static let` constants at the top of `ProStore.swift` and the matching `productID` fields in `Configuration.storekit`.
- **Gate additional Pro features behind `isProUser`** — three gates are live as of April 2026: Survey tab via `ContentView.handlePrimaryAction` (hard paywall on Start Survey, no free first walk), Chat with Klaus via `WiFiAssistantView.freeMessageLimit`, and post-survey insights as a safety-net via `LockedInsightsCard`. All three pass `store` in as an `@ObservedObject` from `MainTabView` rather than using an `@EnvironmentObject` because `ProStore` is already owned by `MainTabView` as a `@StateObject`. Apply the same pattern for future gates (e.g., advanced insights, device identification depth): accept `store: ProStore` as a parameter, check `store.isProUser`, and never read the persisted `@AppStorage("isProUser")` flag from within the gate.
- **Win-back offer (iOS 18+ `winBackOffer`) + weekly price-anchor plan ($4.99/wk)** are both called out in the monetization plan but not yet implemented. Win-back needs a cancelled-user detection path via `SubscriptionStatus` observation and a one-time sheet on re-launch; the weekly plan wants to sit behind an A/B flag before commitment since it lifts revenue 30–50% in top utility apps but raises support load.
- Replace sample floor plans with **user-provided image** + proper **scale/rotation** calibration (the three built-in `FloorPlanTemplate`s cover the common "main-floor apartment" and "upstairs" cases but still aren't the user's actual space).
- **Auto-follow surveyor** toggle — pan/zoom are in place (April 2026), but the view doesn't yet auto-scroll to keep the live surveyor centered while walking. A "follow me" mode would make long surveys hands-off.
- Tighter **multi-segment** landmark rotation (beyond first segment) if drift remains.

## iPhone-only retarget (April 24, 2026)

App Store Connect was prompting for iPad screenshots on the new app record. The build was inheriting that requirement from `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad) in `project.pbxproj`. WiFi Buddy is positioned and tested as an iPhone-only app — the AR Survey, the topology card layouts, and the entire screenshot library are designed around portrait iPhone widths — so the universal target was a stale default rather than an intentional choice.

Changes:
- `SignalStrengthPainter.xcodeproj/project.pbxproj` — `TARGETED_DEVICE_FAMILY` flipped from `"1,2"` to `"1"` in **both** Debug and Release configurations of the `SignalStrengthPainter` target. `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"` and `SUPPORTS_MACCATALYST = NO` were already correct and were left alone.
- `SignalStrengthPainter/Info.plist` — removed the `UISupportedInterfaceOrientations~ipad` array (which previously allowed all four orientations on iPad) since iPad is no longer a supported device family. The base `UISupportedInterfaceOrientations` key is still portrait-only and still drives the AR projection lock described in the orientation section above.

Why this is the right knob to turn:
- App Store Connect derives "iPad screenshots required" from `TARGETED_DEVICE_FAMILY`, **not** from `LSRequiresIPhoneOS` or from `UIRequiredDeviceCapabilities`. `LSRequiresIPhoneOS = true` was already set; that key only blocks Mac App Store distribution, it doesn't change the device-family slot in ASC. Likewise, requiring `arkit` filters out *some* iPads at install time but doesn't tell ASC to hide the iPad screenshot column on the metadata page.
- After uploading the next build (with bumped `CURRENT_PROJECT_VERSION`), the iPad slots in the version's Media section will disappear automatically and the "iPad screenshots required" blocker on the version page will clear.

If WiFi Buddy ever goes universal again:
1. Flip `TARGETED_DEVICE_FAMILY` back to `"1,2"`.
2. Restore the `UISupportedInterfaceOrientations~ipad` array so iPad gets the four-orientation override the AR projection can tolerate at review time on a flat surface.
3. Audit `MainTabView`/`DashboardView`/`PaywallView` for hardcoded portrait-iPhone width assumptions before shipping — the topology card and the swipeable paywall hero pages were both laid out against iPhone widths and have not been reviewed at iPad sizes.

The `NetworkTopologyMonitor.deviceLabel` and Speed-tab device-node icon code that reads `UIDevice.current.userInterfaceIdiom` and resolves to "Your iPad" / `ipad` is intentionally left in place — it's harmless on iPhone-only builds (the iPad branches just never fire) and is useful as-is if the universal target is ever re-enabled.

---

*Generated as a handoff summary for future Cursor chats.*
