#!/usr/bin/env python3
import json, os, re, base64, urllib.request
from nacl.public import PublicKey, SealedBox

def get_token():
    with open(os.path.expanduser("~/.git-credentials")) as f:
        creds = f.read().strip()
    m = re.match(r'https://[^:]+:(.+?)@', creds)
    return m.group(1) if m else ""

token = get_token()
owner, repo = "dczhou", "hermes-android"
headers = {"Authorization": f"token {token}", "Accept": "application/vnd.github.v3+json"}

def encrypt_secret(pub_b64, value):
    pk = PublicKey(base64.b64decode(pub_b64))
    sealed = SealedBox(pk)
    return base64.b64encode(sealed.encrypt(value.encode())).decode()

# Get public key
req = urllib.request.Request(
    f"https://api.github.com/repos/{owner}/{repo}/actions/secrets/public-key",
    headers=headers
)
resp = json.loads(urllib.request.urlopen(req).read())
key_id, pub_key = resp["key_id"], resp["key"]
print(f"Public key: key_id={key_id}")

# Read keystore and base64 encode
with open("/root/my-release-key.keystore", "rb") as f:
    ks_b64 = base64.b64encode(f.read()).decode()

secrets_map = {
    "KEYSTORE_BASE64": ks_b64,
    "STORE_PASSWORD": "ntlx02ca",
    "KEY_PASSWORD": "ntlx02ca",
    "KEY_ALIAS": "my-key-alias"
}

for name, value in secrets_map.items():
    encrypted = encrypt_secret(pub_key, value)
    body = json.dumps({"encrypted_value": encrypted, "key_id": key_id}).encode()
    req = urllib.request.Request(
        f"https://api.github.com/repos/{owner}/{repo}/actions/secrets/{name}",
        data=body,
        headers={**headers, "Content-Type": "application/json"},
        method="PUT"
    )
    resp = urllib.request.urlopen(req)
    print(f"  {name}: HTTP {resp.status} — {resp.read().decode()}")
