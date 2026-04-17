# SignalStrengthPainter — session memory (reference for future chats)

This document summarizes what was built and changed across the conversation so you can paste or `@`-reference it in a new chat.

## Product goal

An iOS SwiftUI app that feels closer to tools like **NetSpot**: walk a space, see a **person/marker** on a **floor plan**, and **paint signal quality** (here: **TCP connect latency** to `8.8.8.8:53`) onto the map as a **heatmap-style** overlay plus a **breadcrumb path**.

## Branding

The app is called **Wi-Fi Buddy** (project/repo name remains `SignalStrengthPainter`). The premium tier is **Wi-Fi Buddy Pro**. `CFBundleDisplayName` in `Info.plist` is set to "Wi-Fi Buddy" so that name appears under the icon on the iOS home screen.

### App Icon

Custom app icon stored in `Assets.xcassets/AppIcon.appiconset/` — a single 1024x1024 PNG (iOS 17+ universal format). Generated programmatically via `scripts/generate_app_icon.py` (Pillow) to exactly match `AppLogoView`.

**Current design (unified earthy palette iteration):**
- **Light cream background** `(242, 241, 246)` (full-bleed; iOS applies its own squircle mask at runtime). Replaced the earlier pure-black background because the darker earthy glyph would otherwise be invisible.
- **Wi-Fi glyph** — three concentric arcs + a center dot, filled with an iridescent material driven by the **exact same 6-stop diagonal gradient** used by `AppLogoView` (`IridescentPalette.earthy`). Stops at `(0.00, 0.20, 0.40, 0.60, 0.80, 1.00)` along TL→BR are pink/burgundy `(122, 56, 87)` → silverWarm `(69, 64, 71)` → peach/warm-brown `(115, 82, 51)` → mint/forest `(51, 92, 77)` → lavender/plum `(71, 59, 117)` → silverCool `(64, 66, 71)`. The gradient parameter at pixel `(x, y)` reduces to `t = (u + v) / 2` on a square canvas. Result is a muted earthy rainbow: burgundy → slate → warm brown → forest green → plum → slate.
- **No vertical depth shading.** Earlier icon iterations applied a top-brighten / bottom-darken ramp to fake a lit-form "3D glass" effect; this was removed so the PNG matches the SwiftUI view (which renders a flat diagonal gradient with no vertical modulation).
- **Specular sheen** — a tight diagonal warm-off-white `(255, 250, 245)` band peaking at gradient location `0.39` (i.e. `u + v ≈ 0.78`) with symmetric transparent stops at `0.26` and `0.52`, peak alpha `≈ 102` (40% intensity). Triangular falloff mirrors SwiftUI's linear-gradient interpolation between the peak stop and the adjacent transparent stops. Clipped to the glyph via the glyph mask so the highlight reads as a subtle polished-surface lift rather than a canvas-wide wash.
- **Geometry (shared with `AppLogoView`)** — `cx = width/2`, `cy = height * 0.635`. Outer/middle/inner arcs use bbox radii `0.425 / 0.302 / 0.180` and stroke thickness `0.096`; dot radius `0.064`. PIL `arc(width=w)` draws the stroke band inward from the bbox radius, so round-cap disks are stamped at the stroke centerline `r_outer − w/2` to avoid bulbous ends.
- **Sparkles** — three 4-pointed stars in the upper-right at the same fractional positions as `AppLogoView`: `(0.810, 0.185, 0.082)`, `(0.905, 0.295, 0.050)`, `(0.705, 0.095, 0.042)` (`x frac, y frac, arm frac`). They're painted with the iridescent gradient **RGB-dimmed to 0.9** (not alpha-dimmed) via a per-channel LUT — mirroring `Color.dimmed(by:)` in SwiftUI so the sparkles read as slightly muted gradient tints rather than translucent ghosts.
- **Rendering** — drawn at 4× supersampling (`4096×4096`) and downsampled with LANCZOS to 1024×1024 for crisp anti-aliased edges. Masks are slightly Gaussian-blurred (`radius = SCALE * 0.3–0.4`) before compositing to avoid aliasing on the curved strokes. Final PNG is flattened to opaque RGB on the cream background (App Store requires no alpha channel).

**Design history of this iteration:**
- v1 (Apple-glass, pale): silver-white dominated with barely-visible pastel hints, glyph at `cy = 0.575` with `r_outer = 0.355`. User feedback: too pale, rainbow colors gone, not centered/sized to fill the icon.
- v2 (Apple-TV-glass): grew radii, shifted `cy` down to visually center, bumped tint saturation + strength via bilinear 4-corner tint (pink TL / mint TR / lavender BR / peach BL), added vertical 3D depth shading (+14% top / −22% bottom), tightened the sheen band.
- v3 (black + pastel glass): rewrote the PNG to exactly mirror the in-app `AppLogoView` dark palette — pure black background with pastel pink/silver/peach/mint/lavender gradient stops. Sparkles RGB-dimmed by 0.9.
- v4 (current — unified earthy palette): user preferred the muted earthy tones that the light-mode `AppLogoView` was rendering (burgundy/olive/forest/plum). Consolidated the two scheme-specific palettes into a single `IridescentPalette.earthy` used by both the in-app view (regardless of color scheme) and the home-screen icon. Icon background swapped from black to a light cream `(242, 241, 246)` since the darker earthy glyph would disappear on black. Sheen color/alpha swapped from `white @ 0.70` to `warm off-white @ 0.40` to match the earthy surface.

The asset catalog is registered in `project.pbxproj` with `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.

**Prior designs (archived):**
- Blue-to-cyan vertical gradient background with traffic-light colored arcs (green/yellow/orange) + red dot + white sparkles, `cy = 0.68`.
- Black background with pastel Apple-glass pink/silver/peach/mint/lavender gradient — replaced in favor of the unified earthy palette below.

### In-App Branding (`AppLogoView.swift`)

Reusable `AppLogoView` SwiftUI view that draws the branded logo programmatically using `Canvas`. **Renders on a transparent background** (no tile) so it composites cleanly over themed cards and headers — the cream squircle is reserved for the home-screen app icon PNG. Three layers composed in order:

1. **Wi-Fi glyph** — three arcs + dot stroked/filled with an iridescent diagonal `linearGradient` (stops: burgundy → slate → warm brown → forest green → plum → slate, top-left → bottom-right). Round caps via `StrokeStyle(lineCap: .round)`. **Geometry matches the 1024×1024 PNG** (`cy = 0.635`, radii `0.425 / 0.302 / 0.180`, thickness `0.096`, dot `0.064`) — stored as static constants so the in-app logo and home-screen icon stay visually identical at any scale.
2. **Glass sheen** — a tight diagonal sheen clipped to the glyph path. Gradient runs **top-left → bottom-right** with stops at `(0.00, 0.26, 0.39, 0.52, 1.00)` — only the `0.39` stop carries the sheen color at `palette.sheenAlpha`; the rest are transparent. This gives iso-lines parallel to `u+v = const`, matching the PNG's sheen geometry (peak at `u+v ≈ 0.78`).
3. **Sparkles** — three 4-pointed stars in the upper-right at the same fractional positions as the PNG, using the iridescent gradient with a `dim` factor of `0.9` (attenuates RGB via `Color.dimmed(by:)` which extracts channels through `UIColor`).

**Palette is unified across both color schemes** via `IridescentPalette.earthy` (returned by `IridescentPalette.resolved(for:)` regardless of the `colorScheme` argument):

- Six stops (RGB 0–1): pink/burgundy `(0.48, 0.22, 0.34)` → silverWarm `(0.27, 0.25, 0.28)` → peach/warm-brown `(0.45, 0.32, 0.20)` → mint/forest `(0.20, 0.36, 0.30)` → lavender/plum `(0.28, 0.23, 0.46)` → silverCool `(0.25, 0.26, 0.28)`. Muted/low-luminance so the darker rainbow stays legible on both white light-mode card fills and near-black dark-mode card fills.
- Sheen is a soft warm off-white `Color(1.0, 0.98, 0.96)` at `0.40` alpha — lifts the darker base without blowing it out.
- Earlier iteration had separate `dark` (pastel Apple-glass) and `light` (slate) palettes; they were consolidated into this single earthy palette after the user preferred the light-mode rendering. The `colorScheme` environment is still read in `AppLogoView` (for API stability) but the resolved palette is the same either way.

Accepts a `size` parameter; every element scales proportionally so the logo holds up from 26pt (compact survey header) to 100pt (paywall hero).

The logo+sparkle is used consistently across all tabs:
- **`DashboardView.swift`** — Speed tab header shows `AppLogoView(size: 44)` + "Wi-Fi Buddy" title.
- **`PaywallView.swift`** — Feature icon section shows `AppLogoView(size: 100)`.
- **`MainTabView.swift` (`SignalDetailView`)** — Signal tab header shows `AppLogoView(size: 44)` above the "Signal Strength" heading.
- **`DeviceDiscoveryView.swift`** — Devices tab header shows `AppLogoView(size: 44)` above the "Device Discovery" heading.
- **`ContentView.swift`** — Survey tab calibration header shows `AppLogoView(size: 34)`; compact/expanded survey header shows `AppLogoView(size: 26)`. Replaces the previous SF Symbol `map.fill` icon in both layouts.

## Current architecture (high level)

| Layer | Role |
|--------|------|
| **`SignalStrengthPainterApp.swift`** | App entry point. Shows **`MainTabView`** as the root view. Applies `.withAppTheme()` for centralized theming. |
| **`AppLogoView.swift`** | Reusable branded logo drawn with `Canvas` — signal-strength colored Wi-Fi arcs (green/yellow/orange) + red dot + sparkle accents (three 4-pointed stars in upper-right). Accepts `size` parameter for flexible rendering. Used across all tab headers: DashboardView, SignalDetailView, DeviceDiscoveryView, ContentView (Survey), and PaywallView. |
| **`AppTheme.swift`** | Centralized theming: `AppearanceMode` enum (system/light/dark), `AppTheme` struct with semantic colors for both modes, `EnvironmentKey` injection, `ThemedRootModifier`. User preference persisted via `@AppStorage("appearanceMode")`. |
| **`MainTabView.swift`** | **Tab-based UI** with 5 tabs: **Speed** (dashboard), **Survey** (AR walk), **Signal** (connection quality), **Devices** (network device discovery), **Pro** (paywall — hidden for pro users). Uses `@AppStorage("isProUser")` to gate Pro tab visibility. Also contains `AppearanceToggle` and `SignalDetailView` (Signal tab). |
| **`DashboardView.swift`** | **Speed tab**: WiFiman/Speedtest-inspired dashboard with **network topology** visualization (ISP → Router → Device), **speed test** (download + upload via Cloudflare with live sparkline, ping/jitter), **speed report** (post-test contextual report rating connection for Netflix/streaming, gaming, video calls, home office, and browsing), **service latency grid** (Google DNS, Cloudflare, OpenDNS, Gateway), **survey quick-action card**, and **appearance toggle** (light/dark/system) in the Wi-Fi header. |
| **`SpeedTestManager.swift`** | Multi-phase speed test engine: **latency** (10 HTTP pings, trimmed mean + jitter), **download** (8 concurrent async streams fetching 4 MB chunks via `URLSession.data(for:)` in a `TaskGroup`), **upload** (8 concurrent async streams uploading 4 MB chunks via `URLSession.upload(for:from:)`). Both transfer phases use `TransferCounter` for byte tracking, a shared `sampleTransferPhase()` loop (250 ms sampling, rolling 4-sample window for live display), and compute final speed as total bytes / total time. Each phase runs up to 12 s. |
| **`PaywallView.swift`** | NetSpot-inspired Pro upsell screen: Canvas hero, pricing cards (**Monthly $1.99**, **Lifetime ~~$19.99~~ $9.99** with "Best Deal" badge), Buy Now CTA, Restore / Not Now links, X close. Now accepts optional `onPurchase` closure for tab-mode integration. StoreKit not yet wired. |
| **`ARTrackingManager.swift`** | Runs `ARWorldTrackingConfiguration`, publishes **world-space camera displacement** from a session anchor, floor-projected **heading**, and tracking status/reliability. |
| **`SignalMapViewModel.swift`** | Combines AR position → **map coordinates**, **latency** sampling, **trail** of `TrailPoint`s, **calibration stages**, **landmark re-anchor**, **map rotation** (slider + optional first landmark segment). |
| **`SignalCanvasView.swift`** | Draws placeholder floor plan, heat blobs, blue path, surveyor symbol; optional **content scale**; map taps in map space. |
| **`LatencyProbe.swift`** | Measures RTT-ish time via `NWConnection` TCP to `8.8.8.8:53`. |
| **`SignalTrailModels.swift`** | `TrailPoint`, `LatencyQuality`, **heat color** derived from latency bands. |
| **`MACAddressResolver.swift`** | **MAC address resolver** — reads the iOS kernel ARP table via `sysctl(NET_RT_FLAGS)` and returns a `[IP: MAC]` map. Parses the packed `rt_msghdr` / `sockaddr_in` / `sockaddr_dl` stream with raw byte offsets (the C types aren't bridged to Swift). Also exposes `isLocallyAdministered(_:)` for detecting iOS/Android randomized privacy MACs and `oui(from:)` for extracting the 3-byte OUI. |
| **`OUIDatabase.swift`** | **OUI vendor database** — curated `[OUI: Manufacturer]` lookup covering ~300 common consumer-electronics manufacturers (Apple, Amazon, Google, Samsung, Sonos, Roku, Philips Hue, Ring, Nintendo, Raspberry Pi, Espressif, Tuya, etc.). `manufacturer(forMAC:)` powers the eighth identification layer so devices that evade Bonjour/SSDP/HTTP still get a trustworthy "Made by …" label. |
| **`NetworkScanner.swift`** | **Device discovery engine** using four identification layers: **(1) Bonjour service discovery** — browses 14 service types (`_airplay._tcp`, `_smb._tcp`, `_homekit._tcp`, `_companion-link._tcp`, etc.), then **resolves each endpoint to an IP** via `NWConnection` so Bonjour names reliably attach to scanned devices. Bonjour-discovered devices are **always included** even if no TCP ports respond. **(2) TCP port fingerprinting** — probes 21 ports per host **concurrently** (80, 443, 62078, 548, 445, 7000, 8080, 9100, 631, 554, 8008, 8443, 1883, 3689, **22/SSH**, **139/NetBIOS**, **5353/mDNS**, 8888, 5000, 515, 3000); open ports stored on each device and used for **port-based classification** (e.g., 62078 = Apple phone, 548 = Mac/AFP, 22 = SSH/computer, 139 = NetBIOS/Windows, 9100 = printer, 7000 = AirPlay/TV). **(3) TCP liveness check** — for hosts with no open probed ports, a secondary check tries ports 443/80/7/1 and treats **fast connection refusal (TCP RST < 500 ms)** as proof the host is alive; discovers firewalled devices that drop all specific port probes. **(4) Reverse DNS** (`getnameinfo`) resolves hostnames; resolved names also feed into name-based classification. Classification cascade: gateway/self → Bonjour services + names → port fingerprint → hostname keywords → unknown. Supports **trusted device** marking persisted in `UserDefaults`. Uses `getifaddrs` for local IP/mask. Scans in batches of 20 with **800 ms** timeout per probe (increased from 300 ms to avoid dropping slower-responding devices). |
| **`DeviceDiscoveryView.swift`** | **Devices tab**: "Who's on my Wi-Fi?" experience. Shows network info card, scan button, live progress. Device list shows type icons, **Bonjour/DNS names as primary label**, latency badges, **port-hint subtitles** (e.g., "Apple Sync", "AirPlay", "SMB") for devices without Bonjour services, and **"TRUSTED" badge**. Detail sheet shows resolved hostname, **open ports list**, services, trust status, and **Trust / Remove Trust** button. Security assessment counts only **untrusted unknown** devices. Identified devices sorted above unknowns. |
| **`ContentView.swift`** | **Survey tab**: Two layouts: **calibration** (scrollable, full chrome) vs **expanded survey/review** (map-first). Custom gradient/card-styled buttons (no system `.borderedProminent`). Footer shows latency + point count in card tiles. **Reset** uses **confirmation dialog**. Styled to match the dark-card design language of the other tabs. |
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

### Stop vs reset

- **Stop Survey** (`stopSurvey()`): stops AR + ping loop, sets **`finished`**, **keeps** trail and samples for review.
- **Reset**: clears everything; gated by **`confirmationDialog`** (“Clear map and all samples”) so accidental taps are harder.

### Expanded map layout

When **`usesExpandedMapLayout`** is true (`surveying`, `selectingReanchorPoint`, **`finished`**):

- **Map-first** layout: large vertical space for `SignalCanvasView`, compact header/instructions/footer.
- **`mapContentScale`** (e.g. **0.48**): uniform **zoom-out** around canvas center so longer walks stay on-screen; **tap coordinates** are divided by the same scale so taps stay correct.

Tunable: `mapContentScale` in `SignalMapViewModel`.

### Visual style (canvas)

- Placeholder **floor plan** (drawn in `drawFloorPlan`) — user deferred replacing with a real image.
- **Heatmap:** radial gradients per `TrailPoint` using **`heatColor`** from `SignalTrailModels`.
- **Path:** blue segments + waypoints; **surveyor** uses SF Symbol via Canvas **symbols** when tracking.

## Xcode project

- **`ARTrackingManager.swift`** was added to **`project.pbxproj`** (target **Sources**).
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
- **DashboardView (Speed tab):** Network topology visualization, speed test with download/upload/ping/jitter, **post-test Wi-Fi report** (rates connection for streaming, gaming, video calls, home office, and browsing with contextual verdicts), service latency grid (Google, Cloudflare, OpenDNS, Gateway), and a survey quick-action card. The standalone latency test section was removed in favor of the integrated speed test.
- **SignalDetailView (Signal tab):** Animated WiFi signal rings, latency-based quality indicator, metrics grid, **manual refresh button** (re-measures latency on demand), and **context-aware tips** (positive "Signal is Great" card when latency is excellent; actionable "Improve Your Signal" tips when good/poor).
- **DeviceDiscoveryView (Devices tab):** Four-layer identification: **(1) Bonjour** (14 service types, resolved to IPs — always included even if port scan misses them), **(2) TCP port fingerprinting** (21 ports probed concurrently — 62078 = Apple phone, 548 = Mac, 22 = SSH, 139 = NetBIOS/Windows, 9100/631 = printer, 7000 = AirPlay/TV, etc.), **(3) TCP liveness check** (detects firewalled hosts via fast RST), **(4) reverse DNS**. Shows device list with **Bonjour/DNS names**, type classification, port-hint subtitles, response times, **trusted badges**, security assessment (rates safety based on **untrusted** unknowns only), and security tips. Detail sheet shows hostname, **open ports**, services, timestamps, and **Trust / Remove Trust** button. Trusted devices persist in `UserDefaults`. `NetworkScanner` manages all discovery state.
- **PaywallView** now accepts an optional `onPurchase` closure. In tab mode, "Buy Now" calls `onPurchase` (sets `isProUser = true`) and switches back to the Speed tab.

## Paywall / monetization

- **`PaywallView`** is now shown as the **Pro tab** for free users (no longer a fullscreen cover on launch).
- **Pricing:** Monthly **$1.99**, Lifetime **$9.99** (shown with ~~$19.99~~ strikethrough + red "Best Deal" badge).
- **Tab behavior:** "Buy Now" triggers `onPurchase` callback + sets `isPresented = false` (switches to Speed tab). "Not now" and X also switch away.
- **StoreKit 2 integration not yet implemented** — `onPurchase` currently just sets `@AppStorage("isProUser") = true`; no real purchase flow, receipt validation, or entitlement gating yet.
- **Restore purchase** button present but not wired to StoreKit.

## Speed Test (download / upload)

- **`SpeedTestManager`** drives a three-phase test: Ping → Download → Upload.
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
  - `NetworkScanner.customNames` — computed `[String: String]` backed by `UserDefaults` under key `customDeviceNames` (IP → nickname), read lazily to stay in sync across launches.
  - `NetworkScanner.setCustomName(_:name:)` — sanitizes input (strips control characters/newlines, collapses whitespace, trims, caps at 40 chars), persists to `UserDefaults`, and updates the live `devices` array. **Only allowed on trusted devices** (guarded by `devices[idx].isTrusted`) — renaming an unvetted device would give the user a false sense of recognition.
  - `setTrusted(_:trusted:)` now clears the stored custom name when a device is un-trusted, so a device the user no longer recognizes stops carrying a nickname that implies they know it.
  - All three `DiscoveredDevice` construction paths (port-scan, Bonjour-only, SSDP-only) populate `customName: customNames[ip]` so nicknames survive rescans.
- **UI (`DeviceDiscoveryView.swift`):**
  - `deviceDisplayName` (list row) and `DeviceDetailSheet.displayName` both check `customName` first, ahead of `isCurrentDevice`/router/Bonjour/hostname/vendor fallbacks.
  - Detail sheet adds a **"Name This Device" / "Rename Device"** button below the existing Trust button, shown **only when `device.isTrusted`**. The Trust button is kept as the only CTA for untrusted devices.
  - Tapping it opens an `.alert` with a SwiftUI `TextField` pre-filled with the current nickname, `.textInputAutocapitalization(.words)`, autocorrection disabled, and a live 40-char cap via `.onChange` (mirrors the scanner's `customNameMaxLength` so the UI can't outrun persistence). Actions: **Save**, **Clear Name** (destructive, only when a name already exists), **Cancel**.
  - After Save/Clear, the sheet dismisses — same UX pattern as the trust toggle.

### Randomized-MAC wording ("Private Wi-Fi Address")
- **Problem:** Devices that couldn't be categorized and had randomized MACs displayed as `"Private <ShortName>"` (e.g., "Private Phone / Tablet", "Private Device"). The bare word **Private** as a prefix reads as "hidden / suspicious" to a non-technical user and created anxiety about devices that are almost always the user's own iPhone or Android. The subtitle "Randomized MAC (privacy mode)" reinforced the same uneasy framing.
- **Fix (`DeviceDiscoveryView.swift`):**
  - Both `deviceDisplayName` (list row) and `displayName` (detail sheet) no longer prepend "Private" when `hasRandomizedMAC` is true. They fall through to the plain `deviceType.rawValue` instead (e.g., "Phone / Tablet", "Device").
  - The vendor-line subtitle now says **"Uses Private Wi-Fi Address"** — the exact phrase iOS uses in Settings → Wi-Fi → (i). Framing this as a standard Apple privacy feature (rather than as "randomized/privacy mode") reassures users that it's normal iOS/Android behavior.
  - The MAC Address row in the detail sheet labels the MAC as `"(Private)"` instead of `"(Randomized)"`, again matching iOS's own terminology.
  - The "Is this yours?" tips card for randomized-MAC devices now reads: "This device uses a Private Wi-Fi Address, so we can't look up its manufacturer. iPhones, Android phones, Macs, and Windows laptops all turn this on by default — it's almost always one of your own devices, not an intruder."
- **Note:** This UX fix compounds with the `NSBonjourServices` Info.plist fix. Before that Info.plist fix, Bonjour browsing failed entirely (`NoAuth(-65555)` × 19), which meant **every** iPhone/Mac/Apple TV on the network collapsed into the randomized-MAC fallback and users saw a screen full of "Private X" devices. With both fixes applied, Bonjour identifies owned Apple hardware properly, and only the handful of genuinely un-identifiable (and almost always friendly) randomized-MAC devices hit the softened wording.

## Possible follow-ups (not done here)

- **Wire StoreKit 2** to PaywallView: product loading, purchase flow, receipt validation, entitlement gating of Pro features.
- Replace placeholder floor plan with **user-provided image** + proper **scale/rotation** calibration.
- **Pan/zoom** or **follow camera** so the user never leaves the visible region without relying only on global scale.
- **README refresh** to match AR + survey flow.
- Tighter **multi-segment** landmark rotation (beyond first segment) if drift remains.

---

*Generated as a handoff summary for future Cursor chats.*
