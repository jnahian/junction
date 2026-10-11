---
title: Open localhost Links in a Separate Browser
order: 11
summary: Send localhost, preview deployments, and terminal links to your dev browser, and open repos in GitHub Desktop and VS Code. Junction routes dev links by rule.
related: [rules, cli, deeplinks]
---

# Keep localhost and dev links in your dev browser

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. Developers use it to keep local servers, preview deployments, and terminal links in one browser, away from the one they read and browse in.

## How do I open localhost links in a different browser?

Write a rule with `localhost` and `127.0.0.1` as bare-host patterns. A bare host matches every path on it, and the port doesn't stop the match.

```json rule
{
  "name": "localhost → Canary",
  "match": { "patterns": ["localhost", "127.0.0.1"] },
  "action": { "app": "com.google.Chrome.canary" }
}
```

```text junction test
$ junction test "http://localhost:3000/dashboard"
input:       http://localhost:3000/dashboard
rule:        [1] localhost → Canary
action:      open in com.google.Chrome.canary
url:         http://localhost:3000/dashboard
```

## Can preview deployments open next to localhost?

Yes. Match the preview hosts with a subdomain wildcard and send them to the same browser.

```json rule
{
  "name": "Preview deploys → Canary",
  "match": { "patterns": ["*.vercel.app/*", "*.netlify.app/*"] },
  "action": { "app": "com.google.Chrome.canary" }
}
```

## Can links I click in the terminal open in my dev browser?

Yes, with a rule that matches the terminal app instead of the link — see [routing links by app](links-from-apps.md#can-terminal-links-open-in-my-dev-browser).

## How do I open GitHub repo links in GitHub Desktop?

Use the `github-desktop` deep link, and limit it with a `regex` to repository home pages. Pull requests, issues, and files keep opening in the browser.

```json rule
{
  "name": "Repo home → GitHub Desktop",
  "match": { "regex": "^https://github\\.com/[^/]+/[^/?#]+/?$" },
  "action": { "deepLink": "github-desktop" }
}
```

Patterns only see the host and path; `regex` matches the full URL, so use it when the shape of the link matters this much.

## How do I open vscode.dev links in VS Code?

Use the `vscode` deep link. A shared `vscode.dev` or `github.dev` link then opens in your local editor. This deep link is marked experimental.

```json rule
{
  "name": "vscode.dev → VS Code",
  "match": { "patterns": ["vscode.dev/*", "github.dev/*"] },
  "action": { "deepLink": "vscode" }
}
```

```text junction test
$ junction test "https://vscode.dev/github/jnahian/junction"
input:       https://vscode.dev/github/jnahian/junction
rule:        [1] vscode.dev → VS Code
action:      deep link (vscode)
url:         vscode://github/jnahian/junction
```

Linear, Figma, and Notion links are in [design and project tools](figma-notion-linear-links.md).

## How do I check a rule before relying on it?

Run `junction test` with the link. It prints the winning rule and the action without opening anything. `junction config validate` checks the whole file and explains any problem.

| Command | What it does |
| --- | --- |
| `junction test <url>` | Shows which rule wins, and why |
| `junction open <url>` | Routes the link and opens it |
| `junction config path` | Prints the config file's path |
| `junction config validate` | Checks the config file |

The config is a plain JSON file at `~/.config/junction/config.json`, so you can keep it in your dotfiles — see [syncing rules across Macs](sync-rules-across-macs.md). When a link goes somewhere unexpected, start with [why links open in the wrong browser](links-open-wrong-browser.md).

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
