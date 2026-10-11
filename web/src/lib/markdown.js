import { highlightJson } from "./highlight.js";

const escape = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// The one Markdown plugin the use-case pages need (Sätteri, Astro 7's processor):
// - `other-page.md#x` links become `/use-cases/other-page#x` (usecases.js checks the target exists)
// - fenced code becomes the docs page's `.code` block, the fence meta as its title
//   bar (```json rule). JSON gets highlightJson's colors and a Copy button; a
//   pasted `junction test` transcript isn't worth copying.
export const useCasesPlugin = {
  name: "junction-use-cases",
  link(node, ctx) {
    const m = node.url.match(/^(?:\.\/)?([\w-]+)\.md(#.*)?$/);
    if (!m) return;
    ctx.setProperty(node, "url", `/use-cases/${m[1]}${m[2] ?? ""}`);
  },
  code(node, ctx) {
    const json = node.lang === "json";
    const body = json ? highlightJson(node.value) : escape(node.value);
    const copy = json ? `<button class="copy-btn">Copy</button>` : "";
    ctx.replaceNode(node, {
      type: "html",
      value: `<div class="code"><div class="code-bar"><span>${escape(node.meta ?? node.lang ?? "")}</span>${copy}</div><pre><code>${body}</code></pre></div>`,
    });
  },
};
