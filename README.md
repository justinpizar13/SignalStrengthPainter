# WiFi Buddy

_Repository name: `SignalStrengthPainter` — the shipping app is branded **WiFi Buddy**, with a **WiFi Buddy Pro** premium tier._

A SwiftUI iOS app for diagnosing home Wi-Fi. It combines a NetSpot-style AR walkthrough survey (with a live heatmap, floor-plan templates, and a post-survey A–F report) with a WiFiman/Speedtest-style dashboard (live network topology, Cloudflare-backed speed test, service latency grid) and a "who's on my Wi-Fi?" device scanner that identifies devices through eight overlapping layers (Bonjour, SSDP, UPnP, TCP port fingerprinting, liveness, reverse DNS, HTTP, and MAC/OUI vendor lookup).

The project started life as a pedometer-based 2D "paint your walk" prototype (see git history). It is now a multi-tab consumer app built around ARKit world tracking, live network telemetry, and a keyword-matched assistant character named **Klaus**.

## Highlights

- **Five tabs**: Speed, Survey, Signal, Devices, Pro (the Pro tab hides itself once the user is entitled).
- **AR-based survey** with a live heatmap painted onto a selectable floor plan, editable room names, pinch/pan/zoom, tap-to-inspect data points, and best/worst-spot markers.
- **Post-survey insights report**: A–F grade, coverage breakdown, dead-zone clustering, latency profile, stability warning, router-direction hint, and tailored "what to do next" recommendations — all computed locally.
- **Live network topology card** on the Speed tab — ISP, router, and device nodes driven by real TCP pings and interface monitoring (no static diagrams).
- **Cloudflare-backed speed test** with server selection (colo + distance + ISP), trimmed-mean ping/jitter, 8-stream concurrent download and upload, and a contextual Wi-Fi report rating the connection for streaming / gaming / video calls / home office / browsing.
- **Device discovery** that identifies ~every device on the LAN by name, vendor, type, and open ports, with per-network trust flags and custom nicknames.
- **Klaus, the WiFi Buddy assistant** — a pixel-art mascot fronting an offline, keyword-matched Q&A knowledge base (no LLM, no network calls).
- **Light/dark/system** theming, persisted across launches.
- **StoreKit 2 paywall** (monthly and yearly subscriptions) with a local `Configuration.storekit` for simulator testing.

## The five tabs

### Speed (dashboard)

- **Live network topology**: ISP → Router → Device, each node driven by `NetworkTopologyMonitor`. The ISP node pings `8.8.8.8:53`; the Router node pings the real inferred gateway IP; the Device node reflects `UIDevice.current` plus the live interface (Wi-Fi / Wired / Cellular / Offline). Connectors animate packet-flow dots only while the hop is carrying traffic, and tint themselves per hop so a responsive router with a dead ISP shows green/red at the same time.
- **Speed test**: Cloudflare-backed with a four-phase flow (Server Selection → Ping → Download → Upload). The server card surfaces the chosen colo, city, great-circle distance, and detected ISP, and warns when the colo is > 500 mi away (a known ISP routing failure mode).
- **Post-test Wi-Fi report** rating the connection for Netflix/streaming, gaming, video calls, home office, and browsing.
- **Service latency grid**: Google DNS, Cloudflare, OpenDNS, and the user's actual gateway.
- **Survey quick-action card** and an **appearance toggle** (system / light / dark) in the header.

### Survey (AR walk + heatmap)

- **AR world-tracking** (`ARWorldTrackingConfiguration`) converts the user's walk into floor-projected `(x, y)` positions. Origin is locked at **Start Survey**; **Re-anchor Here** lets the user correct drift mid-walk by tapping their true location on the map.
- **Floor plan picker** with three templates: Blank, Apartment, Upstairs. Rooms are tinted and labeled; users can rename rooms via a sheet ("Rename Rooms") and the overrides persist per-template in `UserDefaults`.
- **Heatmap + breadcrumb trail**: each `TrailPoint` paints a radial gradient colored by latency quality (Excellent / Good / Poor), stacked under a blue breadcrumb path and a surveyor marker.
- **Pinch to zoom, drag to pan**, and a zoom-controls overlay (`+` / `−` / recenter). Tap any trail point to see a floating card with its latency and capture time.
- **Post-survey insights** (at Stop Survey): an A–F letter-grade header, 2×2 stat grid, stacked coverage bar, latency range strip (Best / Median / Worst 5% / Worst), and ranked insight cards — coverage breakdown, dead-zone count and worst-zone stats, latency profile, stability warning, router-direction hint (via Pearson correlation), and a tailored "what to do next" list. The map keeps rendering the heatmap and adds **Best / Worst spot badges** so users can see which rooms the report is referring to.
- **Free users** see a paywall upsell for this tab; Pro users get unlimited surveys.

### Signal (connection quality)

- Animated Wi-Fi rings + a latency-based quality card (latest RTT, quality label, "Excellent" / "Good" / "Poor" tint).
- **Manual refresh** button re-measures on demand.
- **Context-aware insights**: a positive "Signal is Great" card when latency is excellent, or an actionable "Improve Your Signal" card otherwise.
- **Chat with Klaus** CTA opens a full-screen assistant sheet. Klaus is a pixel-art mascot fronting an offline Q&A engine — 24 curated answers across Coverage / Reliability / Setup / Streaming / Security / Speed / Gaming, matched by a deterministic keyword scorer. Each reply is preceded by a "thinking" bubble and followed by three related follow-up chips. Free users can ask **one** question per install; Pro users get unlimited chat.

### Devices (who's on my Wi-Fi?)

Scans the LAN and identifies each device through eight layers (in order):

1. **Bonjour** — 19 mDNS service types browsed for the full scan window (plus `NetService`-based name + IP resolution).
2. **SSDP / UPnP** — UDP multicast M-SEARCH with three `ST` values.
3. **UPnP device descriptions** — parallel fetches of each device's `LOCATION` URL for `<friendlyName>` / `<manufacturer>` / `<modelName>`.
4. **TCP port fingerprinting** — 21 common ports probed concurrently.
5. **TCP liveness** — fast-RST detection for firewalled hosts.
6. **Reverse DNS** — `getnameinfo` with a hostname-cleanup pass (strips `.local`, `.home`, `.lan`, `.fritz.box`, etc.).
7. **HTTP fingerprinting** — parses `Server` headers, HTML `<title>`, and UPnP XML fallback paths from port 80 / 8080.
8. **MAC + OUI vendor lookup** — reads the kernel ARP table via `sysctl(NET_RT_FLAGS)` and maps each device's MAC OUI against a curated ~300-entry vendor database.

The device list shows Bonjour/DNS names, vendor line ("Made by Apple" / "Uses Private Wi-Fi Address" for randomized MACs), device-type icons, latency badges, and trusted badges. Each device's detail sheet shows hostname, open ports, services, MAC, vendor, and an "Is this yours?" tips card, plus **Trust**, **Rename** (for trusted devices), and **Remove Trust** buttons.

Trust flags and custom names are **scoped per network** — the network ID is derived from the gateway's MAC address, so moving to a different Wi-Fi doesn't silently re-trust a stranger's `192.168.1.10`.

### Pro (paywall)

- StoreKit 2 integration via `ProStore.swift`.
- **Monthly $3.99** and **Yearly $34.99** (with a `~~$39.99~~` strikethrough and "Best Deal" badge), plus a 3-day free trial on the yearly plan when the user is still eligible. Prices hydrate from `Product.products(for:)` when available.
- Paywall includes the full Apple-required subscription disclosure (auto-renewal, 24-hour cancellation window, Apple ID billing) plus tappable **Privacy Policy** and **Terms of Use** links that open `LegalDocumentView` over the bundled Markdown docs.
- Buy / Restore are wired end-to-end. Entitlement is derived from `Transaction.currentEntitlements` (never persisted), with a long-lived `Transaction.updates` listener for Ask-to-Buy / refunds.
- Local simulator testing via `Configuration.storekit` (referenced by the shared scheme; no per-developer setup needed).

## Project layout

```
SignalStrengthPainter/
├── SignalStrengthPainterApp.swift      App entry; applies theming; hosts MainTabView
├── MainTabView.swift                    5-tab shell; contains SignalDetailView + AppearanceToggle
├── AppTheme.swift                       Centralized light/dark theming
├── AppLogoView.swift                    Programmatic Wi-Fi glyph logo (matches app icon)
├── DashboardView.swift                  Speed tab: topology, speed test, latency grid
├── ContentView.swift                    Survey tab: calibration + expanded + finished layouts
├── SignalCanvasView.swift               Heatmap/path renderer with pinch/pan/tap-to-inspect
├── SignalMapViewModel.swift             AR → map projection, trail, calibration state machine
├── ARTrackingManager.swift              ARWorldTracking-backed position + heading
├── LatencyProbe.swift                   NWConnection TCP ping (`8.8.8.8:53`)
├── SignalTrailModels.swift              TrailPoint, LatencyQuality, heat color mapping
├── SurveyInsightsEngine.swift           A–F grade + coverage + dead zones + insights
├── SurveyInsightsView.swift             Themed renderer for the insights report
├── FloorPlanTemplate.swift              Blank / Apartment / Upstairs + custom room names
├── DeviceDiscoveryView.swift            Devices tab UI + detail sheet
├── NetworkScanner.swift                 8-layer device discovery engine
├── NetworkTopologyMonitor.swift         Live ISP/Router/Device health
├── NetworkInterfaceMonitor.swift        Wi-Fi / Wired / Cellular / Offline monitoring
├── SpeedTestManager.swift               Cloudflare 4-phase speed test (server/ping/DL/UL)
├── MACAddressResolver.swift             ARP table reader (sysctl NET_RT_FLAGS)
├── OUIDatabase.swift                    ~300-vendor OUI lookup
├── WiFiAssistantView.swift              Klaus chat sheet (Q&A engine + thinking bubble)
├── KlausMascotView.swift                Animated pixel-art mascot (GIF via ImageIO)
├── PaywallView.swift                    Pro upsell + StoreKit 2 purchase flow
├── ProStore.swift                       StoreKit 2 manager (products/purchase/restore)
├── LegalDocumentView.swift              In-app Markdown viewer for Privacy Policy / Terms
├── AboutView.swift                      About sheet (version, links, credits)
├── Info.plist                           Motion, Local Network, Camera, NSBonjourServices,
│                                        orientation (portrait on iPhone),
│                                        UIRequiresFullScreen, UIRequiredDeviceCapabilities,
│                                        ITSAppUsesNonExemptEncryption=false
├── PrivacyInfo.xcprivacy                Apple Privacy Manifest (no tracking, UserDefaults CA92.1)
├── PrivacyPolicy.md                     Bundled privacy policy (rendered by LegalDocumentView)
├── TermsOfUse.md                        Bundled terms of use (rendered by LegalDocumentView)
└── Assets.xcassets                      AppIcon + Klaus GIFs (NSDataAsset)

Configuration.storekit                   Local StoreKit config (simulator testing)
scripts/                                 Icon + Klaus frame generators (Python / Pillow)
MEMORY.md                                Session memory / detailed architecture notes
```

## Requirements

- **Xcode 15+** (Swift 5.9+, iOS 17 SDK or later).
- **iOS 17+** device or simulator. A **physical iPhone or iPad** is strongly recommended for the Survey tab — ARKit world tracking needs a real camera and IMU.
- A **Local Network permission** prompt appears on first scan (Devices tab). Grant it, otherwise Bonjour discovery silently fails with `NoAuth(-65555)` and most devices fall back to generic labels.
- The Survey tab requests **Camera** and **Motion** permissions.

## Build and run

1. Open `SignalStrengthPainter.xcodeproj` in Xcode.
2. Select the **SignalStrengthPainter** scheme plus your iPhone (recommended) or a simulator.
3. In **Signing & Capabilities**, choose your **Team**. The bundle ID is `com.wifibuddy.app`; change it in the target's **General** tab if you're testing a personal fork. `CFBundleDisplayName` is set to `WiFi Buddy` so that name appears under the home-screen icon.
4. Build and run (**⌘R**).

### StoreKit (Pro tab)

- The shared scheme already references `Configuration.storekit` under **Run → Options → StoreKit Configuration**, so Buy / Restore work in the Simulator without an Apple ID.
- On a **physical device** launched from Xcode, StoreKit also uses the local config. If you detach the device and relaunch from the home screen, `Product.products(for:)` returns empty (the storekit config is scheme-scoped, not bundled in the app). Test purchases on-device either by staying attached to Xcode, by using the Simulator, or by configuring real products in App Store Connect and signing in with a Sandbox tester.
- Product IDs (`com.wifibuddy.pro.sub.monthly` / `com.wifibuddy.pro.sub.yearly`) are declared in two places — `ProStore.swift` and `Configuration.storekit`. Keep them in sync when renaming.

### Running the Survey without a device

The Simulator can render the Survey UI, the heatmap, and the post-survey report (using the calibration flow), but ARKit tracking only produces synthetic motion there. Use a real iPhone/iPad to exercise the actual walk-and-paint experience.

## Privacy and permissions

`Info.plist` declares:

- `NSMotionUsageDescription` — CoreMotion access for legacy pedometer fallback.
- `NSLocalNetworkUsageDescription` — LAN scanning for the Devices tab.
- `NSCameraUsageDescription` — ARKit world tracking for the Survey tab.
- `NSBonjourServices` — the 19 mDNS service types the scanner browses. This **must stay in sync** with `NetworkScanner.bonjourServiceTypes`; iOS will silently drop any browser for a type not listed here.
- `ITSAppUsesNonExemptEncryption=false` — the app only uses standard HTTPS/TLS, which is export-compliance exempt; this flag skips the App Store Connect encryption questionnaire on every build upload.
- iPhone is locked to **portrait** orientation (`UISupportedInterfaceOrientations`), while iPad keeps all four orientations. ARKit world-tracking surveys behave much better when the map projection can't flip mid-walk.
- `UIRequiresFullScreen=true` and `UIRequiredDeviceCapabilities = [arkit, wifi]` — keeps the app off split-screen iPad multitasking (AR + survey assumes a single full window) and hides the app from devices that can't run ARKit.

The app ships a full **Apple Privacy Manifest** at `PrivacyInfo.xcprivacy`. It declares `NSPrivacyTracking=false`, no tracking domains, and no collected data types. The only privacy-sensitive API declared is `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` (accessing user defaults from within the same app) — used by the `@AppStorage` calls that persist preferences, trust flags, survey history, and Klaus chat state.

The app makes no analytics or third-party network calls. The speed test, latency probes, and gateway pings are the only outbound traffic. The assistant (Klaus) runs entirely offline.

## Legal documents

Privacy Policy and Terms of Use ship as bundled Markdown (`PrivacyPolicy.md`, `TermsOfUse.md`) and are rendered in-app by `LegalDocumentView` via `AttributedString`'s native Markdown parser. The paywall exposes both links next to the Apple-required subscription disclosure, satisfying App Store Review Guideline 3.1.2 without relying on an external hosted web page.

## App Store submission checklist

When preparing a new build for App Store Connect, double-check:

- Bundle identifier is `com.wifibuddy.app` in both Debug and Release configs.
- `Info.plist` has the four usage-description strings plus `ITSAppUsesNonExemptEncryption`, the orientation arrays, `UIRequiresFullScreen`, and `UIRequiredDeviceCapabilities`.
- `PrivacyInfo.xcprivacy` is present in the target's **Copy Bundle Resources** phase (the project wires it in automatically).
- `PrivacyPolicy.md` and `TermsOfUse.md` are in **Copy Bundle Resources**.
- StoreKit product IDs (`com.wifibuddy.pro.sub.monthly`, `com.wifibuddy.pro.sub.yearly`) exist in App Store Connect with matching pricing tiers, and a 3-day free trial is configured on the yearly SKU if that funnel is enabled.
- App Review Notes include: "Survey tab uses ARKit; please run on a physical device to exercise world tracking. Paywall disclosures and Privacy/Terms links are on the Pro tab."

## Further reading

`MEMORY.md` in the repo root is a detailed, section-by-section architecture journal (topology monitor internals, StoreKit integration, device-classification heuristics, insights-engine thresholds, Klaus asset pipeline, etc.). It's maintained alongside the code as a deep reference for anyone picking up the project in a new session.
