import { readFileSync } from "node:fs";
import { getCollection } from "astro:content";

// /use-cases/<slug>.md — the page's Markdown source, for readers and LLMs that
// want it raw. Links to other use cases (`other-page.md`) already resolve from
// here; screenshots point at repo files, so they're swapped for the built images.
const shots = import.meta.glob("../../../../docs/assets/screenshots/**/*.png", { eager: true, import: "default" });

export async function getStaticPaths() {
  const pages = await getCollection("useCases");
  return pages.map((page) => ({ params: { slug: page.id }, props: { page } }));
}

export function GET({ props: { page } }) {
  const md = readFileSync(page.filePath, "utf8").replace(
    /\]\(\.\.\/assets\/screenshots\/([^)]+)\)/g,
    (_, rest) => `](${shots[`../../../../docs/assets/screenshots/${rest}`].src})`
  );
  return new Response(md, { headers: { "Content-Type": "text/markdown; charset=utf-8" } });
}
