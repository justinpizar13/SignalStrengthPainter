# SignalStrengthPainter — session memory (reference for future chats)

This document summarizes what was built and changed across the conversation so you can paste or `@`-reference it in a new chat.

## Product goal

An iOS SwiftUI app that feels closer to tools like **NetSpot**: walk a space, see a **person/marker** on a **floor plan**, and **paint signal quality** (here: **TCP connect latency** to `8.8.8.8:53`) onto the map as a **heatmap-style** overlay plus a **breadcrumb path**.

## Branding

The app is called **Wifi Buddy** (project/repo name remains `SignalStrengthPainter`). The premium tier is **Wifi Buddy Pro**.

## Current architecture (high level)

| Layer | Role |
|--------|------|
| **`SignalStrengthPainterApp.swift`** | App entry point. Shows **`MainTabView`** as the root view. |
| **`MainTabView.swift`** | **Tab-based UI** with 4 tabs: **Speed** (dashboard), **Survey** (AR walk), **Signal** (connection quality), **Pro** (paywall — hidden for pro users). Uses `@AppStorage("isProUser")` to gate Pro tab visibility. Also contains `SignalDetailView` (Signal tab). |
| **`DashboardView.swift`** | **Speed tab**: WiFiman/Speedtest-inspired dashboard with **network topology** visualization (ISP → Router → Device), **speed test** (download + upload via Cloudflare with live sparkline, ping/jitter), **latency test** (10-ping burst with sparkline chart), **service latency grid** (Google DNS, Cloudflare, OpenDNS, Gateway), and a **survey quick-action card**. |
| **`SpeedTestManager.swift`** | Multi-phase speed test engine: **latency** (10 HTTP pings, trimmed mean + jitter), **download** (8 concurrent async streams fetching 4 MB chunks via `URLSession.data(for:)` in a `TaskGroup`), **upload** (8 concurrent async streams uploading 4 MB chunks via `URLSession.upload(for:from:)`). Both transfer phases use `TransferCounter` for byte tracking, a shared `sampleTransferPhase()` loop (250 ms sampling, rolling 4-sample window for live display), and compute final speed as total bytes / total time. Each phase runs up to 12 s. |
| **`PaywallView.swift`** | NetSpot-inspired Pro upsell screen: Canvas hero, pricing cards (**Monthly $1.99**, **Lifetime ~~$19.99~~ $9.99** with "Best Deal" badge), Buy Now CTA, Restore / Not Now links, X close. Now accepts optional `onPurchase` closure for tab-mode integration. StoreKit not yet wired. |
| **`ARTrackingManager.swift`** | Runs `ARWorldTrackingConfiguration`, publishes **world-space camera displacement** from a session anchor, floor-projected **heading**, and tracking status/reliability. |
| **`SignalMapViewModel.swift`** | Combines AR position → **map coordinates**, **latency** sampling, **trail** of `TrailPoint`s, **calibration stages**, **landmark re-anchor**, **map rotation** (slider + optional first landmark segment). |
| **`SignalCanvasView.swift`** | Draws placeholder floor plan, heat blobs, blue path, surveyor symbol; optional **content scale**; map taps in map space. |
| **`LatencyProbe.swift`** | Measures RTT-ish time via `NWConnection` TCP to `8.8.8.8:53`. |
| **`SignalTrailModels.swift`** | `TrailPoint`, `LatencyQuality`, **heat color** derived from latency bands. |
| **`ContentView.swift`** | **Survey tab**: Two layouts: **calibration** (full chrome) vs **expanded survey/review** (map-first). **Reset** uses **confirmation dialog**. |
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
- **Tabs:** Speed (dashboard), Survey (AR walk), Signal (connection quality), Pro (paywall).
- **Pro tab** is **conditionally shown** based on `@AppStorage("isProUser")`. When `isProUser == true`, the Pro tab is hidden.
- **DashboardView (Speed tab):** Network topology visualization, 10-ping latency test with smooth sparkline chart, service latency grid (Google, Cloudflare, OpenDNS, Gateway), and a survey quick-action card.
- **SignalDetailView (Signal tab):** Animated WiFi signal rings, latency-based quality indicator, metrics grid, and improvement tips.
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
- **UI integration in `DashboardView`:** "Speed Test" section appears between the topology card and the existing Latency Test. Three states: empty (no results yet), active (phase indicator with live Mbps gauge + sparkline + progress bar), complete (side-by-side Download/Upload tiles + Ping/Jitter badges). Start/Stop/Test Again button.

## Possible follow-ups (not done here)

- **Wire StoreKit 2** to PaywallView: product loading, purchase flow, receipt validation, entitlement gating of Pro features.
- Replace placeholder floor plan with **user-provided image** + proper **scale/rotation** calibration.
- **Pan/zoom** or **follow camera** so the user never leaves the visible region without relying only on global scale.
- **README refresh** to match AR + survey flow.
- Tighter **multi-segment** landmark rotation (beyond first segment) if drift remains.

---

*Generated as a handoff summary for future Cursor chats.*
