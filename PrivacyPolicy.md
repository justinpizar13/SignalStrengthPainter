# Privacy Policy

_Last updated: May 6, 2026_

WiFi Buddy ("we", "our", "the app") is designed to help you understand
and improve the Wi-Fi network you already have. We built the app with
privacy as a first-order requirement: **your data stays on your
device.**

## What data we collect

**None.** We do not operate servers. We do not have accounts. We do not
have logins. We do not run analytics. We do not show ads. We do not
sell, rent, or share user data — because we do not have any.

The app stores the following information **only on your iPhone or iPad,
in the app's local storage (UserDefaults)**:

- **Survey history** — your walked trails, latency samples, and the
  derived insights report.
- **Device list and trust state** — the Wi-Fi devices the app has
  discovered on each network you've scanned, plus which ones you've
  marked as trusted and any nicknames you've given them.
- **Chat history with Klaus** — the questions you've asked our in-app
  assistant (Klaus runs entirely on-device; your messages are never
  sent anywhere).
- **Appearance, floor-plan, and room-name preferences** — so your
  settings persist between launches.
- **Anonymous usage flags** — e.g., whether you've seen the
  "Getting Started" screen, how many free Klaus questions you've used.

This data is scoped to this app's own storage area on your device. We
never read it; no one else does either.

## What data leaves your device

Three narrow categories of network traffic leave your device, and none
of them carry identifying information about you:

1. **Speed test traffic** — When you tap "Start Speed Test", the app
   connects to **speed.cloudflare.com** (Cloudflare's public
   speed-test endpoint) to fetch the nearest test server's metadata
   and to run the download/upload phases. Cloudflare sees your IP
   address (same as any website you visit) and the bytes of the test
   payload (random data). Cloudflare's privacy policy applies to this
   interaction: <https://www.cloudflare.com/privacypolicy/>.
2. **Latency pings** — The app opens TCP connections to public DNS
   resolvers (8.8.8.8, 1.1.1.1, 208.67.222.222) to measure round-trip
   time. These are plain connection attempts; no application data is
   sent over them.
3. **Local-network discovery** — When you open the Devices tab, the
   app browses local Bonjour services, sends SSDP multicast probes,
   and scans local TCP ports — **all within your home/office Wi-Fi
   network**. None of this traffic leaves your router.

The app does not integrate with any third-party analytics, advertising,
tracking, crash reporting, or attribution SDKs.

## Subscriptions (WiFi Buddy Pro)

Subscription purchases are handled entirely by Apple's StoreKit. We
never see your payment information. Apple's own privacy policy covers
the purchase flow: <https://www.apple.com/legal/privacy/>.

We use Apple's StoreKit to verify whether you have an active
subscription. The verification runs on-device against Apple-signed
transaction data — no server call from us is involved.

## Notifications

If you permit them, the app schedules **local** notifications for:

- Free-trial charge reminder (24 hours before the trial ends)
- Re-survey reminders (30 / 90 / 180 days after a completed survey)
- New-device alerts on networks you've marked as trusted

All of these are scheduled and delivered by iOS itself. No push
notification servers are used. No content is sent to our servers
because we do not have servers.

## Required permissions

The app asks for these iOS permissions only when the feature that
needs them is actively used:

- **Camera** — required by ARKit to track your device's position
  during a Wi-Fi survey. The camera feed is never recorded, screenshot,
  or transmitted.
- **Motion & Fitness** — supplements AR tracking for the survey map.
- **Local Network** — required to discover devices on your Wi-Fi.
- **Notifications** — optional; used only for local reminders
  described above.

## Children

The app is not directed to children under 13. We do not knowingly
collect information from children because we do not collect any
information at all.

## Changes

If this policy changes materially, we will update the "Last updated"
date at the top and surface the change in an app update.

## Contact

Questions? Email: [justin.dev@gmail.com](mailto:justin.dev@gmail.com)
