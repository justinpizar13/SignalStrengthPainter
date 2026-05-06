// Centralized site metadata. Update these values in one place when the
// App Store ID, support email, or domain changes — every page reads from
// here.

export const SITE = {
  name: "WiFi Buddy",
  tagline: "See your Wi-Fi. Walk your home. Find every dead zone.",
  description:
    "WiFi Buddy turns your iPhone into a walking Wi-Fi heatmap. Find dead zones, get personalized fixes, and see every device on your network — all in one beautifully simple app.",
  url: "https://wifibuddy.app",
  // Canonical (storefront-agnostic) App Store URL. Omitting the country
  // segment lets Apple redirect to the visitor's local storefront. The
  // numeric ID is the permanent App Store ID assigned at first approval.
  appStoreUrl: "https://apps.apple.com/app/wifi-buddy/id6763663209",
  appStoreId: "6763663209",
  // Real, monitored mailbox. Must stay in sync with the contact email
  // in PrivacyPolicy.md, TermsOfUse.md, and Support.md — App Review
  // compares hosted-URL text against in-app text.
  supportEmail: "justin.dev@gmail.com",
  // Used for App Store JSON-LD aggregateRating. Keep in sync with App
  // Store Connect once real ratings come in. Set to `null` to omit.
  rating: {
    value: 4.8,
    count: 124,
  } as { value: number; count: number } | null,
  pricing: {
    annual: "$9.99",
    trialDays: 3,
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
  { label: "Support", href: "/support" },
  { label: "Privacy", href: "/privacy" },
  { label: "Terms", href: "/terms" },
];
