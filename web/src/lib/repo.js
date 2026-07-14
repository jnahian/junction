// The site's facts come from the repo, not from a copy of the repo.
// Everything here runs at build time only — never import this from src/scripts/.
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

// Resolve against the repo root (the parent of this Astro project). Not import.meta.url:
// the bundler relocates this module into dist/, and the relative path would follow it.
const read = (path) => readFileSync(resolve(process.cwd(), "..", path), "utf8");

export const CHANGE_TYPES = [
  { key: "all", label: "All" },
  { key: "add", label: "Added" },
  { key: "chg", label: "Changed" },
  { key: "fix", label: "Fixed" },
];

const MARKERS = { added: "add", changed: "chg", fixed: "fix" };

/** The shipped version, from the one place a release bumps it. */
export function version() {
  const plist = read("App/Info.plist");
  const match = plist.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/);
  if (!match) throw new Error("CFBundleShortVersionString not found in App/Info.plist");
  return `v${match[1]}`;
}

/**
 * Releases, parsed from CHANGELOG.md. Headings are `## <version> — <date>`;
 * bullets are `- Added|Changed|Fixed: <body>`. A bullet without a marker is a
 * build error rather than a silently untyped entry — see the note in CHANGELOG.md.
 */
export function releases() {
  const sections = read("CHANGELOG.md").split(/^## /m).slice(1);

  return sections.map((section) => {
    const [heading, ...lines] = section.split("\n");
    const [rawVersion, rawDate] = heading.split("—").map((s) => s.trim());

    const changes = lines
      .filter((line) => line.startsWith("- "))
      .map((line) => {
        const match = line.slice(2).match(/^(Added|Changed|Fixed):\s*(.+)$/);
        if (!match) throw new Error(`CHANGELOG.md ${rawVersion}: bullet has no Added/Changed/Fixed marker — ${line}`);
        return { type: MARKERS[match[1].toLowerCase()], body: match[2] };
      });

    // work lands under `## Unreleased`; the release skill renames it to `## X.Y.Z — DATE`
    const unreleased = rawVersion.toLowerCase() === "unreleased";

    return {
      version: unreleased ? "Unreleased" : `v${rawVersion}`,
      unreleased,
      date: unreleased
        ? null
        : new Date(`${rawDate}T00:00:00`).toLocaleDateString("en-US", {
            month: "short",
            day: "numeric",
            year: "numeric",
          }),
      changes,
    };
  });
}

/**
 * The deep-link rewriters that actually ship. Two of them target Slack, so the
 * app list is shorter than the rewriter count — the site quotes both.
 */
export function rewriters() {
  const { rewriters: all } = JSON.parse(read("Sources/JunctionCore/Resources/rewriters.json"));

  const apps = [];
  for (const { id, name } of all) {
    const app = name.replace(/\s*\(.*\)$/, ""); // "Slack (message links)" → "Slack"
    if (apps.some((a) => a.name === app)) continue; // two rewriters, one Slack

    // icons are named after the rewriter id; a rewriter without one just renders as text
    const icon = `/icons/${id}.svg`;
    const hasIcon = existsSync(resolve(process.cwd(), "public", icon.slice(1)));
    apps.push({ name: app, icon: hasIcon ? icon : null });
  }

  return { count: all.length, apps };
}
