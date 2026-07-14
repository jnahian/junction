#!/usr/bin/env bash
# Print one version's CHANGELOG section as the HTML fragment Sparkle's update
# dialog renders. Exits non-zero if that section is missing or has no entries.
#
# release.sh pipes this into Junction.html next to the DMG; CI runs it against the
# version in App/Info.plist so a release with no notes fails on the pull request
# rather than in front of users. One parser, so the two can't drift — an earlier
# split is exactly how a heading format change silently blanked the update dialog.
set -euo pipefail

VERSION="${1:?usage: release-notes.sh <version>}"
CHANGELOG="$(dirname "$0")/../CHANGELOG.md"

# Headings carry a date (`## 0.5.1 — 2026-07-14`), so match the version as a whole
# word after `## ` — not the entire line (misses the date) and not a bare prefix
# (`0.5` would match `## 0.5.1`).
NOTES="$(awk -v version="$VERSION" '
  index($0, "## " version) == 1 &&
  (length($0) == length("## " version) || substr($0, length("## " version) + 1, 1) == " ") {
    inSection = 1; next
  }
  /^## / { inSection = 0 }
  inSection && /^- / { if (!open) { print "<ul>"; open = 1 }; sub(/^- /, ""); print "<li>" $0 "</li>" }
  END { if (open) print "</ul>" }
' "$CHANGELOG")"

if [ -z "$NOTES" ]; then
  echo "Error: no '## ${VERSION}' section with entries in CHANGELOG.md." >&2
  echo "       Sparkle's update dialog would ship blank. Write the section —" >&2
  echo "       heading '## ${VERSION} — YYYY-MM-DD', bullets 'Added:/Changed:/Fixed:'." >&2
  echo "       See the document-change skill." >&2
  exit 1
fi

printf '%s\n' "$NOTES"
