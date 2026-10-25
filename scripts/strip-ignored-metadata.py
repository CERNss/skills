#!/usr/bin/env python3
"""Git clean filter for skills/.metadata.json.

Drops entries whose skill directory is excluded by .gitignore, so internal
skills stay out of the published metadata while the local file is untouched.
"""
import json
import subprocess
import sys

raw = sys.stdin.read()
try:
    data = json.loads(raw)
except ValueError:
    sys.stdout.write(raw)
    sys.exit(0)

entries = data.get("entries", {})
paths = ["skills/%s/" % name for name in entries]
ignored = set()
if paths:
    out = subprocess.run(
        ["git", "check-ignore", "--no-index", "--stdin"],
        input="\n".join(paths), capture_output=True, text=True,
    ).stdout
    ignored = {p[len("skills/"):-1] for p in out.splitlines()}

data["entries"] = {k: v for k, v in entries.items() if k not in ignored}
sys.stdout.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
