// The authoring rules for docs/use-cases/*.md that the content schema in
// content.config.js can't express. Called from the article route, so a broken
// page fails the build (and the Vercel deploy), and from `npm test`.
import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import assert from "node:assert/strict";

// paths from web/, like repo.js — import.meta.url doesn't survive bundling
const dir = resolve(process.cwd(), "../docs/use-cases");
const docs = JSON.parse(readFileSync(resolve(process.cwd(), "src/data/docs.json"), "utf8"));
const docIds = new Set(docs.nav.flatMap((g) => g.links).map((l) => l.href).filter((h) => h.startsWith("#")).map((h) => h.slice(1)));
const slugify = (s) => s.toLowerCase().replace(/[^\w\s-]/g, "").trim().replace(/\s+/g, "-");

export function checkUseCases() {
  const pages = readdirSync(dir).filter((f) => f.endsWith(".md")).map((file) => {
    const src = readFileSync(resolve(dir, file), "utf8");
    const [, front, body] = src.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
    const prose = body.replace(/```[\s\S]*?```/g, ""); // headings and links, not code
    return {
      slug: file.replace(/\.md$/, ""),
      order: Number(front.match(/^order: (\d+)$/m)[1]),
      body,
      h1s: prose.match(/^# .+$/gm) ?? [],
      h2s: prose.match(/^## .+$/gm) ?? [],
      anchors: new Set((prose.match(/^#{2,3} .+$/gm) ?? []).map((h) => slugify(h.replace(/^#+ /, "")))),
      links: [...prose.matchAll(/\]\(([^)]+)\)/g)].map((m) => m[1]),
      json: [...body.matchAll(/```json[^\n]*\n([\s\S]*?)```/g)].map((m) => m[1]),
    };
  });
  const bySlug = Object.fromEntries(pages.map((p) => [p.slug, p]));

  assert.equal(new Set(pages.map((p) => p.order)).size, pages.length, "two pages share an `order`");

  for (const p of pages) {
    const at = `docs/use-cases/${p.slug}.md`;
    assert.equal(p.h1s.length, 1, `${at}: needs exactly one H1`);
    assert.equal(p.h2s.at(-1), "## Get Junction", `${at}: last section must be "## Get Junction"`);
    assert.ok(!p.body.includes("ld+json"), `${at}: JSON-LD is generated — don't write it by hand`);
    p.json.forEach((block) => JSON.parse(block)); // every rule/config sample is valid JSON

    const targets = new Set();
    for (const href of p.links) {
      const md = href.match(/^(?:\.\/)?([\w-]+)\.md(?:#(.+))?$/);
      if (md) {
        const target = bySlug[md[1]];
        assert.ok(target, `${at}: link to missing page ${href}`);
        if (md[2]) assert.ok(target.anchors.has(md[2]), `${at}: link to missing heading ${href}`);
        targets.add(md[1]);
      } else if (href.startsWith("/docs#")) {
        assert.ok(docIds.has(href.slice(6)), `${at}: no docs section ${href}`);
        targets.add(href);
      }
    }
    assert.ok(targets.size >= 2, `${at}: link to at least 2 other pages`);
  }

  for (const p of pages) {
    const inbound = pages.some((o) => o !== p && o.links.some((l) => l.replace(/^\.\//, "").split("#")[0] === `${p.slug}.md`));
    assert.ok(inbound, `docs/use-cases/${p.slug}.md: no other use case links to it`);
  }

  return pages.length;
}
