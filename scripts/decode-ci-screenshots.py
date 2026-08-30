#!/usr/bin/env python3
"""Decode the ===SHOT blocks a CI job log carries into PNG files.

Usage:  python3 scripts/decode-ci-screenshots.py <job-log.txt> <out-dir>

The full log of any run is downloadable without a credential: ask the
GitHub API for the run's logs URL (actions_get / get_workflow_run_logs_url
returns a signed link), curl the zip, and feed the iOS job's .txt to this.
That is how AE-032 recovered every frame the 2.6 MB log-tail cap had
swallowed (TECH_DEBT TD-020)."""

log_path, out_dir = sys.argv[1], sys.argv[2]
os.makedirs(out_dir, exist_ok=True)
text = open(log_path, errors="replace").read()
# Strip timestamps GitHub prepends ("2026-08-30T19:55:01.1234567Z ").
lines = [re.sub(r"^\S+Z ", "", l) for l in text.splitlines()]
i, count = 0, 0
while i < len(lines):
    m = re.match(r"===SHOT (.+?) (\d+)$", lines[i].strip())
    if not m:
        i += 1
        continue
    name = m.group(1)
    data = []
    i += 1
    while i < len(lines) and not lines[i].strip().startswith("===ENDSHOT"):
        data.append(lines[i].strip())
        i += 1
    try:
        raw = base64.b64decode("".join(data))
        safe = re.sub(r"[^A-Za-z0-9._-]", "_", name)
        with open(os.path.join(out_dir, safe + ".png"), "wb") as f:
            f.write(raw)
        count += 1
    except Exception as e:
        print(f"FAILED {name}: {e}")
    i += 1
print(f"decoded {count} screenshots into {out_dir}")
