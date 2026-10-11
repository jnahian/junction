---
title: Open Figma, Notion & Linear Links in Their Apps
order: 9
summary: Open Figma files, Notion pages, and Linear issues in their desktop apps instead of in browser tabs. Junction turns each web link into a native app link.
related: [deeplinks, actions, rules]
icons: [figma, notion, linear]
---

# Open Figma, Notion, and Linear links in their desktop apps

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. Its deep links open design files, docs, and issues in their desktop apps, on the file, page, or issue the link points to.

## How do I make Figma links open in the Figma app?

Turn on **Figma** in **Settings → Deep Links**, or add a rule with the `figma` deep link. Design, FigJam, slides, and prototype links all open in the app.

```json rule
{
  "name": "Figma → app",
  "match": { "patterns": ["*.figma.com/design/*", "*.figma.com/file/*", "*.figma.com/board/*", "*.figma.com/slides/*", "*.figma.com/proto/*"] },
  "action": { "deepLink": "figma" }
}
```

```text junction test
$ junction test "https://www.figma.com/design/AbC123xyz/Checkout?node-id=1-2"
input:       https://www.figma.com/design/AbC123xyz/Checkout?node-id=1-2
rule:        [1] Figma → app
action:      deep link (figma)
url:         figma://file/AbC123xyz/Checkout?node-id=1-2
```

The `node-id` comes along, so the app opens on the frame that was linked.

## How do I open Notion links in the Notion app?

Turn on **Notion** in **Settings → Deep Links**, or add a rule for Notion's domain.

```json rule
{
  "name": "Notion → app",
  "match": { "patterns": ["*.notion.so/*"] },
  "action": { "deepLink": "notion" }
}
```

## How do I open Linear issues in the Linear app?

Turn on **Linear** in **Settings → Deep Links**, or add a rule for issue links.

```json rule
{
  "name": "Linear → app",
  "match": { "patterns": ["linear.app/*/issue/*"] },
  "action": { "deepLink": "linear" }
}
```

## Which project tools have built-in deep links?

| App | Deep link | Opens |
| --- | --- | --- |
| Figma | `figma` | Design, FigJam, slides, and prototype files |
| Notion | `notion` | Workspace pages |
| Linear | `linear` | Issues, projects, views, and more |
| ClickUp | `clickup`, `clickup-doc` | Tasks and docs |
| Asana | `asana` | Asana links |
| Todoist | `todoist` | Tasks |

All of them are off until you turn them on, and each only fires when its app is installed — otherwise the link opens in your fallback browser. The [docs list every built-in deep link](/docs#deeplinks). Meeting links are in [Zoom and Teams links](zoom-teams-links.md), and music in [Spotify and Apple Music links](spotify-music-links.md).

## Can work tools open in a browser profile instead?

Yes — if you'd rather keep Jira or ClickUp in a browser, send them to your work profile. See [Chrome profiles](chrome-profile-links.md).

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
