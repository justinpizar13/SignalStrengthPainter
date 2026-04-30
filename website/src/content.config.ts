import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

const blog = defineCollection({
  loader: glob({ pattern: "**/*.{md,mdx}", base: "./src/content/blog" }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    pubDate: z.coerce.date(),
    updated: z.coerce.date().optional(),
    keywords: z.array(z.string()).default([]),
    /** When true, the post is hidden from the index but still builds. */
    draft: z.boolean().default(false),
  }),
});

// Legal documents are populated by scripts/sync-legal.mjs from the
// canonical Markdown files at the repo root. They have no frontmatter
// (we never want to mutate the App Store-bundled copies), so the schema
// is intentionally empty.
const legal = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/legal" }),
  schema: z.object({}),
});

export const collections = { blog, legal };
