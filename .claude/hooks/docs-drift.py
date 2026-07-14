#!/usr/bin/env python3
"""Nudge toward the document-change skill after a change to the app's source.

Runs as a PostToolUse hook on Edit/Write. It never blocks — it adds a line of
context Claude sees, once per session, so a user-visible change doesn't get
committed with no changelog entry and stale docs.

Silent when: the edit isn't under Sources/, or this session has already been
nudged, or CHANGELOG.md already has an Unreleased section that this session
touched (nothing left to remind about).
"""

import json
import os
import pathlib
import sys

payload = json.load(sys.stdin)
path = payload.get("tool_input", {}).get("file_path", "")

# Only the app's own source. Tests, scripts, and the website don't ship behavior.
if "/Sources/" not in path or "/Tests/" in path:
    sys.exit(0)

# One nudge per session; the reminder loses its force if it fires on every edit.
session = payload.get("session_id", "unknown")
flag = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / f"junction-docs-nudge-{session}"
if flag.exists():
    sys.exit(0)
flag.touch()

print(
    json.dumps(
        {
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": (
                    "You edited Sources/. If this change is user-visible, it needs a CHANGELOG.md "
                    "entry (under `## Unreleased`, prefixed `Added:`/`Changed:`/`Fixed:`) and may "
                    "need docs updates in web/src/data/ — the website is generated from this repo. "
                    "Use the `document-change` skill before committing. If the change is internal "
                    "(refactor, test, build), ignore this."
                ),
            }
        }
    )
)
