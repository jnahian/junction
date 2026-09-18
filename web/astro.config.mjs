import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://junction.jnahian.me",
  // keep styles and scripts as their own files instead of inlined into the HTML
  build: { inlineStylesheets: "never" },
  vite: { build: { assetsInlineLimit: 0 } },
});
