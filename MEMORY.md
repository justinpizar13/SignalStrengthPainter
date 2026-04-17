# SignalStrengthPainter — session memory (reference for future chats)

This document summarizes what was built and changed across the conversation so you can paste or `@`-reference it in a new chat.

## Product goal

An iOS SwiftUI app that feels closer to tools like **NetSpot**: walk a space, see a **person/marker** on a **floor plan**, and **paint signal quality** (here: **TCP connect latency** to `8.8.8.8:53`) onto the map as a **heatmap-style** overlay plus a **breadcrumb path**.

## Branding

The app is called **Wi-Fi Buddy** (project/repo name remains `SignalStrengthPainter`). The premium tier is **Wi-Fi Buddy Pro**. `CFBundleDisplayName` in `Info.plist` is set to "Wi-Fi Buddy" so that name appears under the icon on the iOS home screen.

### App Icon

Custom app icon stored in `Assets.xcassets/AppIcon.appiconset/` — a single 1024x1024 PNG (iOS 17+ universal format). Generated programmatically via `scripts/generate_app_icon.py` (Pillow) to exactly match `AppLogoView`.

**Current design (in-app-logo match iteration):**
- **Pure black background** (full-bleed; iOS applies its own squircle mask at runtime).
- **Wi-Fi glyph** — three concentric arcs + a center dot, filled with an iridescent material driven by the **exact same 6-stop diagonal gradient** used by `AppLogoView` in dark mode. Stops at `(0.00, 0.20, 0.40, 0.60, 0.80, 1.00)` along TL→BR are pink `(255, 184, 214)` → silverWarm `(240, 232, 237)` → peach `(255, 212, 166)` → mint `(189, 237, 224)` → lavender `(204, 186, 250)` → silverCool `(230, 232, 237)`. The gradient parameter at pixel `(x, y)` reduces to `t = (u + v) / 2` on a square canvas.
- **No vertical depth shading.** Earlier icon iterations applied a top-brighten / bottom-darken ramp to fake a lit-form "3D glass" effect; this was removed so the PNG matches the SwiftUI view (which renders a flat diagonal gradient with no vertical modulation).
- **Specular sheen** — a tight diagonal white band peaking at gradient location `0.39` (i.e. `u + v ≈ 0.78`) with symmetric transparent stops at `0.26` and `0.52`, peak alpha `≈ 178` (70% white). Triangular falloff mirrors SwiftUI's linear-gradient interpolation between the peak stop and the adjacent transparent stops. Clipped to the glyph via the glyph mask so the highlight reads as polished glass rather than a canvas-wide wash.
- **Geometry (shared with `AppLogoView`)** — `cx = width/2`, `cy = height * 0.635`. Outer/middle/inner arcs use bbox radii `0.425 / 0.302 / 0.180` and stroke thickness `0.096`; dot radius `0.064`. PIL `arc(width=w)` draws the stroke band inward from the bbox radius, so round-cap disks are stamped at the stroke centerline `r_outer − w/2` to avoid bulbous ends.
- **Sparkles** — three 4-pointed stars in the upper-right at the same fractional positions as `AppLogoView`: `(0.810, 0.185, 0.082)`, `(0.905, 0.295, 0.050)`, `(0.705, 0.095, 0.042)` (`x frac, y frac, arm frac`). They're painted with the iridescent gradient **RGB-dimmed to 0.9** (not alpha-dimmed) via a per-channel LUT — mirroring `Color.dimmed(by:)` in SwiftUI so the sparkles read as slightly muted gradient tints rather than translucent ghosts.
- **Rendering** — drawn at 4× supersampling (`4096×4096`) and downsampled with LANCZOS to 1024×1024 for crisp anti-aliased edges. Masks are slightly Gaussian-blurred (`radius = SCALE * 0.3–0.4`) before compositing to avoid aliasing on the curved strokes. Final PNG is flattened to opaque RGB (App Store requirement).

**Design history of this iteration:**
- v1 (Apple-glass, pale): silver-white dominated with barely-visible pastel hints, glyph at `cy = 0.575` with `r_outer = 0.355`. User feedback: too pale, rainbow colors gone, not centered/sized to fill the icon.
- v2 (Apple-TV-glass): grew radii, shifted `cy` down to visually center, bumped tint saturation + strength via bilinear 4-corner tint (pink TL / mint TR / lavender BR / peach BL), added vertical 3D depth shading (+14% top / −22% bottom), tightened the sheen band.
- v3 (current): user preferred the in-app logo coloring, so the PNG was rewritten to **exactly mirror `AppLogoView`**: same 6-stop diagonal gradient, same stop locations, no vertical depth shading, matching sparkle positions and RGB-based sparkle dimming. The home-screen icon and the in-app branding now use identical color math.

The asset catalog is registered in `project.pbxproj` with `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.

**Prior design (archived):** blue-to-cyan vertical gradient background with traffic-light colored arcs (green/yellow/orange) + red dot + white sparkles, `cy = 0.68`. Replaced in favor of the black + Apple-glass look.

### In-App Branding (`AppLogoView.swift`)

Reusable `AppLogoView` SwiftUI view that draws the branded logo programmatically using `Canvas`. **Renders on a transparent background** (no black tile) so it composites cleanly over themed cards and headers — the black squircle is reserved for the home-screen app icon PNG. Three layers composed in order:

1. **Wi-Fi glyph** — three arcs + dot stroked/filled with an iridescent diagonal `linearGradient` (stops: pink → warm silver → peach → mint → lavender → cool silver, top-left → bottom-right). Round caps via `StrokeStyle(lineCap: .round)`. **Geometry matches the 1024×1024 PNG** (`cy = 0.635`, radii `0.425 / 0.302 / 0.180`, thickness `0.096`, dot `0.064`) — stored as static constants so the in-app logo and home-screen icon stay visually identical at any scale.
2. **Glass sheen** — a tight diagonal sheen clipped to the glyph path. Gradient runs **top-left → bottom-right** with stops at `(0.00, 0.26, 0.39, 0.52, 1.00)` — only the `0.39` stop carries the sheen color at `palette.sheenAlpha`; the rest are transparent. This gives iso-lines parallel to `u+v = const`, matching the PNG's sheen geometry (peak at `u+v ≈ 0.78`).
3. **Sparkles** — three 4-pointed stars in the upper-right at the same fractional positions as the PNG, using the iridescent gradient with a `dim` factor of `0.9` (attenuates RGB via `Color.dimmed(by:)` which extracts channels through `UIColor`).

**Palette is color-scheme aware** via `IridescentPalette.resolved(for: colorScheme)`:

- **Dark palette** (matches the home-screen icon) — near-silver base with **moderately saturated** pink / peach / mint / lavender stops (RGB components ranging `0.62–1.00`) so the rainbow reads subtly on dark card fills. Sheen is pure white at `0.70` alpha — a brighter specular than before so the glass look holds up against `cardFill = white @ 4% alpha`.
- **Light palette** — same hue rotation but inverted to dark slate tones (luminance `0.20–0.46`) so the glyph stays legible on `cardFill = Color.white` in light mode. Slightly bumped saturation so the rainbow still reads against white. Sheen is a soft warm off-white at `0.40` alpha.

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
- **Fix:** `resolveServiceEndpoint` now extracts the IPv4 address from `connection.currentPath` in `.failed` and `.waiting` states (not just `.ready`), and also attempts extraction in the timeout handler before giving up. DNS resolution completes before the TCP handshake, so the resolved IP is available in the path even when the connection ultimately fails.
- **Impact:** Computers like Mac Mini that advertise Bonjour services but have firewalled service ports now get their Bonjour sharing name (e.g., "Justin's Mac Mini") attached correctly.

### Additional Bonjour service types for computers
- Added `_afpovertcp._tcp` (AFP file sharing) and `_rfb._tcp` (Screen Sharing/VNC) to the 19 browsed service types (now 19 total), with friendly names "File Sharing" and "Screen Sharing" respectively.
- Screen Sharing (`_rfb._tcp`) is now recognized as a computer-indicating service in the AirPlay co-detection branch and the general Bonjour classification, alongside File Sharing and Remote Desktop.

### Updated `NetworkScanner` identification layers (now seven)
1. **Bonjour** (19 service types including `_afpovertcp._tcp`, `_rfb._tcp`, `_apple-mobdev2._tcp`, `_touch-able._tcp`)
2. **SSDP / UPnP** (UDP multicast M-SEARCH with 3 ST values, parallel with Bonjour)
3. **UPnP device descriptions** (fetches LOCATION URLs for friendlyName/manufacturer/model)
4. **TCP port fingerprinting** (21 ports)
5. **TCP liveness** (fast RST detection for firewalled hosts)
6. **Reverse DNS** (with improved reclassification logic, hostname cleanup)
7. **HTTP fingerprinting** (fetches HTTP responses + UPnP XML from port 80/8080 for devices still needing identification)

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

## Possible follow-ups (not done here)

- **Wire StoreKit 2** to PaywallView: product loading, purchase flow, receipt validation, entitlement gating of Pro features.
- Replace placeholder floor plan with **user-provided image** + proper **scale/rotation** calibration.
- **Pan/zoom** or **follow camera** so the user never leaves the visible region without relying only on global scale.
- **README refresh** to match AR + survey flow.
- Tighter **multi-segment** landmark rotation (beyond first segment) if drift remains.

---

*Generated as a handoff summary for future Cursor chats.*
