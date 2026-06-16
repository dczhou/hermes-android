#!/usr/bin/env python3
import json, os, re, urllib.request, zipfile, io

with open(os.path.expanduser("~/.git-credentials")) as f:
    creds = f.read().strip()
m = re.match(r'https://[^:]+:(.+?)@', creds)
token = m.group(1) if m else ""
headers = {"Authorization": f"token {token}", "Accept": "application/vnd.github.v3+json"}

# Get latest run
req = urllib.request.Request(
    "https://api.github.com/repos/dczhou/hermes-android/actions/runs?per_page=1",
    headers=headers
)
data = json.loads(urllib.request.urlopen(req).read())
run_id = data["workflow_runs"][0]["id"]
print(f"Run ID: {run_id}")

# Download logs zip
log_req = urllib.request.Request(
    f"https://api.github.com/repos/dczhou/hermes-android/actions/runs/{run_id}/logs",
    headers=headers
)
log_data = urllib.request.urlopen(log_req).read()

with zipfile.ZipFile(io.BytesIO(log_data)) as zf:
    for name in sorted(zf.namelist()):
        print(f"  File: {name}")
    print()
    # Find Build APK step
    for name in sorted(zf.namelist()):
        lower = name.lower()
        if "build apk" in lower or ("build" in lower and "apk" in lower):
            content = zf.read(name).decode("utf-8", errors="replace")
            lines = content.strip().split("\n")
            print(f"=== {name} ({len(lines)} lines) ===")
            for line in lines[-80:]:
                print(line)
            print()
