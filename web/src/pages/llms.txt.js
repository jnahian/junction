import site from "../data/site.json";
import { version, rewriters } from "../lib/repo.js";

// llms.txt (llmstxt.org): a plain-text map of the site for LLMs. Generated at
// build time like every other page, so the version and app list never drift
// from the repo. Relative links resolve against wherever the site is served.
export function GET() {
  const { count, apps } = rewriters();
  const names = apps.map((a) => a.name).join(", ");

  const text = `# ${site.name}

> ${site.tagline}

Junction is a macOS menu-bar app that registers as the default browser and
routes every clicked http(s) link to a browser, browser profile, or native app
via an ordered, first-match-wins rule list. Rules live in a plain JSON file at
${site.configPath} and can be edited in the GUI, a text editor, or the bundled
\`junction\` CLI. Current version: ${version()}.

Links that match no rule go to a fallback — a browser, or a picker that asks
every time. ${count} built-in deep-link rewriters can open links in native apps
instead of the browser: ${names}. Adding an app is a JSON-only contribution.

## Documentation

- [Docs](/docs): rules, wildcard pattern semantics, actions, deep links, the CLI, and troubleshooting
- [Changelog](/changelog): every release with Added/Changed/Fixed notes

## Source and distribution

- [GitHub repository](${site.github}): MIT-licensed source (Swift, SPM, no Xcode project)
- [README](${site.github}#readme): install (Homebrew cask or DMG), config file format, CLI usage
- [Contributing](${site.contributing}): how to add a deep-link app without writing Swift
- [rewriters.json](${site.rewritersJson}): the data file behind the built-in deep links
- [Releases](${site.releases}): signed DMGs and the Sparkle appcast
`;

  return new Response(text, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}
