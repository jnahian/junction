import { defineConfig } from "astro/config";

export default defineConfig({
  // keep styles and scripts as their own files instead of inlined into the HTML
  build: { inlineStylesheets: "never" },
  vite: { build: { assetsInlineLimit: 0 } },
});
