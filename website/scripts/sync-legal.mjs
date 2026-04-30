#!/usr/bin/env node
// Copies the canonical legal markdown files (the ones shipped with the
// iOS app and shown in LegalDocumentView) into src/content/legal/ so
// /privacy and /terms render the exact same text App Store reviewers
// see in-app. Run as a predev / prebuild hook.
//
// We intentionally copy (rather than symlink) so the build works on any
// platform without symlink permissions — important for CI.

import { mkdirSync, copyFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "..", "..");
const targetDir = resolve(__dirname, "..", "src", "content", "legal");

mkdirSync(targetDir, { recursive: true });

const sources = [
  {
    from: resolve(repoRoot, "PrivacyPolicy.md"),
    to: resolve(targetDir, "privacy.md"),
    label: "Privacy Policy",
  },
  {
    // Public TermsOfUse.md at the repo root is the canonical EULA —
    // it's the file App Store Connect's EULA field and the App
    // Description's "Terms of Use" link both point at. The in-app
    // bundled copy at SignalStrengthPainter/TermsOfUse.md must be
    // kept byte-identical to this file so reviewers see matching
    // text in-app and on the web (April 2026 rejection 3.1.2(c)).
    from: resolve(repoRoot, "TermsOfUse.md"),
    to: resolve(targetDir, "terms.md"),
    label: "Terms of Use",
  },
  {
    // Public Support.md at the repo root is the canonical support
    // doc rendered at /support on the marketing site. App Store
    // Connect's Support URL field points at https://wifibuddy.app/support.
    from: resolve(repoRoot, "Support.md"),
    to: resolve(targetDir, "support.md"),
    label: "Support",
  },
];

for (const { from, to, label } of sources) {
  if (!existsSync(from)) {
    // Validate input paths instead of failing silently — we never want
    // the website to ship with stale legal docs.
    console.error(`[sync-legal] missing source: ${from}`);
    process.exit(1);
  }
  copyFileSync(from, to);
  console.log(`[sync-legal] ${label}: ${from} → ${to}`);
}
