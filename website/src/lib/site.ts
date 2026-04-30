// Centralized site metadata. Update these values in one place when the
// App Store ID, support email, or domain changes — every page reads from
// here.

export const SITE = {
  name: "WiFi Buddy",
  tagline: "See your Wi-Fi. Walk your home. Find every dead zone.",
  description:
    "WiFi Buddy turns your iPhone into a walking Wi-Fi heatmap. Survey your home in AR, see exactly where the dead zones are, and get personalized fixes — plus an 8-layer device scanner that names every gadget on your network.",
  url: "https://wifibuddy.app",
  // Replace `idTODO` with the real App Store ID once the listing is live.
  // We use the Smart App Banner-friendly canonical URL so Apple gets
  // attribution and the install completes inside the App Store.
  appStoreUrl: "https://apps.apple.com/app/wifi-buddy/idTODO",
  supportEmail: "support@wifibuddy.app",
  // Used for App Store JSON-LD aggregateRating. Keep in sync with App
  // Store Connect once real ratings come in. Set to `null` to omit.
  rating: {
    value: 4.8,
    count: 124,
  } as { value: number; count: number } | null,
  pricing: {
    monthly: "$3.99",
    yearly: "$34.99",
  },
  twitter: "@wifibuddyapp",
} as const;

export type NavItem = { label: string; href: string };

export const PRIMARY_NAV: NavItem[] = [
  { label: "Features", href: "/features" },
  { label: "Devices", href: "/devices" },
  { label: "Releases", href: "/releases" },
  { label: "Blog", href: "/blog" },
];

export const FOOTER_NAV: NavItem[] = [
  { label: "Features", href: "/features" },
  { label: "Devices", href: "/devices" },
  { label: "Releases", href: "/releases" },
  { label: "Blog", href: "/blog" },
  { label: "Privacy", href: "/privacy" },
  { label: "Terms", href: "/terms" },
];
