#!/usr/bin/env python3
"""Check use-case pages against the real routing engine, or print a trace to paste.

  verify.py                                 check every docs/use-cases/*.md
  verify.py trace <page.md> <url> [--source <bundleID>]
                                            print real `junction test` output for a page

Every ```json rule / ```json config block must pass `junction config validate`.
Every ```text junction test block must equal what the CLI prints for it, run
against the rule it names alone (so the trace reads `[1] <name>`) plus the
page's config blocks.

Run from the repo root after `swift build --product junction-cli`.
"""
import glob, json, os, re, subprocess, sys, tempfile

CLI = ".build/debug/junction-cli"
FENCE = re.compile(r"```json (rule|config)\n(.*?)```", re.S)
TRACE = re.compile(r"```text junction test\n\$ (junction test [^\n]+)\n(.*?)```", re.S)
tmp = tempfile.mkdtemp(prefix="use-case-")


def blocks(src):
    rules, config = [], {}
    for kind, body in FENCE.findall(src):
        obj = json.loads(body)
        rules.append(obj) if kind == "rule" else config.update(obj)
    return rules, config


def write_config(rules, config):
    cfg = {"version": 1, "fallback": {"app": "com.apple.Safari"}, "rules": rules, **config}
    fd, path = tempfile.mkstemp(suffix=".json", dir=tmp)
    with os.fdopen(fd, "w") as f:
        json.dump(cfg, f)
    return path


def run_test(path, url, source=None):
    args = [CLI, "test", url, "--config", path] + (["--source", source] if source else [])
    return subprocess.run(args, capture_output=True, text=True).stdout.strip()


def check():
    problems = 0
    for page in sorted(glob.glob("docs/use-cases/*.md")):
        src = open(page).read()
        rules, config = blocks(src)
        for kind, body in FENCE.findall(src):
            obj = json.loads(body)
            path = write_config([obj], {}) if kind == "rule" else write_config([], obj)
            v = subprocess.run([CLI, "config", "validate", "--config", path], capture_output=True, text=True)
            if v.returncode:
                problems += 1
                print(f"INVALID {kind} in {page}:\n{v.stdout}{v.stderr}")
        for cmd, shown in TRACE.findall(src):
            url = re.search(r'"([^"]+)"', cmd).group(1)
            source = re.search(r"--source (\S+)", cmd)
            named = re.search(r"rule:\s+\[1\] (.+)", shown)
            only = [r for r in rules if named and r["name"] == named.group(1).strip()]
            real = run_test(write_config(only, config), url, source and source.group(1))
            if real != shown.strip():
                problems += 1
                print(f"TRACE MISMATCH in {page} for {url}\n--- CLI ---\n{real}\n--- page ---\n{shown.strip()}\n")
    print(f"{len(glob.glob('docs/use-cases/*.md'))} pages, {problems} problem(s)")
    return problems == 0


def trace(page, url, source=None):
    rules, config = blocks(open(page).read())
    # first rule that matches on its own, so the output reads `[1] <name>`
    for rule in rules:
        out = run_test(write_config([rule], config), url, source)
        if "rule:        none" not in out:
            break
    else:
        out = run_test(write_config([], config), url, source)
    cmd = f'$ junction test "{url}"' + (f" --source {source}" if source else "")
    print(f"```text junction test\n{cmd}\n{out}\n```")


if __name__ == "__main__":
    if not os.access(CLI, os.X_OK):
        sys.exit(f"{CLI} missing — run `swift build --product junction-cli` from the repo root")
    if sys.argv[1:2] == ["trace"]:
        a = sys.argv[2:]
        src = a[a.index("--source") + 1] if "--source" in a else None
        trace(a[0], a[1], src)
    else:
        sys.exit(0 if check() else 1)
