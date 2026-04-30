import { defineConfig } from "astro/config";
import mdx from "@astrojs/mdx";
import sitemap from "@astrojs/sitemap";
import tailwindcss from "@tailwindcss/vite";

// IMPORTANT: keep this in sync with src/lib/site.ts → SITE.url.
// Used to build absolute URLs in the sitemap and Open Graph tags.
export default defineConfig({
  site: "https://wifibuddy.app",
  trailingSlash: "ignore",
  build: {
    format: "directory",
  },
  integrations: [
    mdx(),
    sitemap({
      changefreq: "monthly",
      priority: 0.7,
    }),
  ],
  vite: {
    plugins: [tailwindcss()],
  },
});
