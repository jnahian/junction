import { defineCollection } from "astro:content";
import { glob } from "astro/loaders";
import { z } from "astro/zod";
import docs from "./data/docs.json";

// /docs anchors a page may list in `related` — whatever the docs sidebar links to
const docIds = docs.nav.flatMap((g) => g.links).map((l) => l.href).filter((h) => h.startsWith("#")).map((h) => h.slice(1));

// The use-case pages live outside web/ (docs/use-cases/*.md), like CHANGELOG.md.
// The spec's limits are enforced here, so a page that breaks one fails the build.
const useCases = defineCollection({
  loader: glob({ pattern: "*.md", base: "../docs/use-cases" }),
  schema: z.object({
    title: z.string().max(48),
    order: z.number().int(),
    summary: z.string().min(145).max(160),
    related: z.array(z.enum(docIds)).min(1),
  }),
});

export const collections = { useCases };
