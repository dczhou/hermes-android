#!/usr/bin/env python3
import json, os, re, urllib.request

with open(os.path.expanduser("~/.git-credentials")) as f:
    creds = f.read().strip()
m = re.match(r'https://[^:]+:(.+?)@', creds)
token = m.group(1) if m else ""

body = {
    "title": "fix: fall back to debug signing when no keystore secrets configured",
    "body": "## Problem\n\nThe `Build Release APK` workflow fails with:\n```\nKeytoolException: Failed to read key from store \"release.keystore\":\nTag number over 30 is not supported\n```\n\n**Root cause:** This repo is forked from `rusty4444/hermes-android`. GitHub forks do **not** inherit Actions secrets (`KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`). The workflow unconditionally writes an empty `key.properties` and decodes an empty base64 string into `release.keystore`, producing a 0-byte file that the signing step cannot read.\n\n## Fix\n\nTwo-layer fallback so the APK always builds:\n\n### 1. `build-apk.yml` — skip keystore setup when secret is empty\n```yaml\nif [ -z \"$KEYSTORE_BASE64\" ]; then\n  echo \"::warning::No KEYSTORE_BASE64 secret — build will use debug signing.\"\n  exit 0\nfi\n```\n\n### 2. `build.gradle.kts` — fall back to built-in debug signingConfig\n```kotlin\nsigningConfig = if (hasReleaseKeystore)\n    signingConfigs.getByName(\"release\")\nelse\n    signingConfigs.getByName(\"debug\")\n```\n\nWhen keystore secrets ARE configured (original repo or after manual setup), release signing works exactly as before.\n\n## Files changed\n\n- `android/app/build.gradle.kts` — conditional release/debug signingConfig\n- `.github/workflows/build-apk.yml` — skip keystore step when `KEYSTORE_BASE64` is empty\n\n## Test plan\n\n- [ ] Run the `Build Release APK` workflow — should succeed with debug signing\n- [ ] (Optional) Set up `KEYSTORE_BASE64` etc. in Settings > Secrets to verify release signing still works",
    "head": "fix/keystore-fallback",
    "base": "main"
}

data = json.dumps(body).encode()
req = urllib.request.Request(
    "https://api.github.com/repos/dczhou/hermes-android/pulls",
    data=data,
    headers={
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
        "Content-Type": "application/json"
    },
    method="POST"
)
try:
    resp = urllib.request.urlopen(req)
    result = json.loads(resp.read())
    print(f"PR created: #{result['number']}")
    print(f"URL: {result['html_url']}")
except urllib.error.HTTPError as e:
    print(f"HTTP {e.code}: {e.read().decode()}")
