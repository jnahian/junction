import { getCollection } from "astro:content";

// List the pages by hand rather than pull in @astrojs/sitemap; the use-case
// articles come from docs/use-cases/, so a new file is listed without an edit here.
export async function GET({ site }) {
  const useCases = (await getCollection("useCases")).map((page) => `/use-cases/${page.id}`);
  const pages = ["/", "/docs", "/use-cases", ...useCases, "/changelog"];
  const urls = pages.map((p) => `  <url><loc>${new URL(p, site).href}</loc></url>`).join("\n");
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls}
</urlset>
`;

  return new Response(xml, {
    headers: { "Content-Type": "application/xml; charset=utf-8" },
  });
}
