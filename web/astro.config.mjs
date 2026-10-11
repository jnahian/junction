import { defineConfig } from "astro/config";
import { satteri } from "@astrojs/markdown-satteri";
import { useCasesPlugin } from "./src/lib/markdown.js";

export default defineConfig({
  site: "https://junction.jnahian.me",
  // keep styles and scripts as their own files instead of inlined into the HTML
  build: { inlineStylesheets: "never" },
  vite: { build: { assetsInlineLimit: 0 } },
  // only the use-case pages are markdown; their code blocks reuse the docs styling
  markdown: { syntaxHighlight: false, processor: satteri({ mdastPlugins: [useCasesPlugin] }) },
});
