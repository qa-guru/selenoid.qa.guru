#!/usr/bin/env bash
# Local safe checks for auth wiring (no live prod calls, no real secrets).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== YAML syntax (.github/workflows) ==="
python - <<'PY'
import pathlib, sys
try:
    import yaml
except ImportError:
    print("SKIP: PyYAML not installed")
    sys.exit(0)
for path in sorted(pathlib.Path(".github/workflows").glob("*.yml")):
    with path.open(encoding="utf-8") as f:
        yaml.safe_load(f)
    print(f"OK  {path}")
PY

echo "=== require-public-auth fail-fast ==="
if bash -c 'source deploy/lib/require-public-auth.sh; require_public_auth' 2>/dev/null; then
  echo "FAIL: require_public_auth should exit when env unset" >&2
  exit 1
fi
echo "OK  exits when SELENOID_PUBLIC_* unset"

echo "=== nginx placeholder patch (dummy creds) ==="
TMP="$(mktemp)"
cp deploy/nginx-selenoid.conf "$TMP"
export SELENOID_PUBLIC_USER=test_user
export SELENOID_PUBLIC_PASSWORD='test-pass'
# shellcheck source=lib/require-public-auth.sh
source deploy/lib/require-public-auth.sh
patch_nginx_public_access_keys "$TMP"
grep -q 'test_user:test-pass' "$TMP"
grep -q 'test_user%3Atest-pass' "$TMP"
grep -q '__SELENOID_PUBLIC_ACCESS_KEY' "$TMP" && { echo "FAIL: placeholder left"; exit 1; }
rm -f "$TMP"
echo "OK  placeholders replaced"

echo "=== smoke-remote fail-fast (no URL/creds) ==="
if ./deploy/smoke-remote.sh 2>/dev/null; then
  echo "FAIL: smoke-remote should require args/env" >&2
  exit 1
fi
echo "OK  smoke-remote rejects missing URL"

echo "=== edge.py ssl_ctx pins TLS 1.2+ ==="
python - <<'PY'
import importlib.util
import ssl
from pathlib import Path

spec = importlib.util.spec_from_file_location("edge", Path("deploy/edge.py"))
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)
ctx = mod.ssl_ctx()
if ctx.minimum_version < ssl.TLSVersion.TLSv1_2:
    raise SystemExit(f"FAIL: ssl_ctx minimum_version={ctx.minimum_version}")
if ctx.verify_mode != ssl.CERT_REQUIRED:
    raise SystemExit(f"FAIL: ssl_ctx verify_mode={ctx.verify_mode}")
print("OK  TLS 1.2+ and CERT_REQUIRED")
PY

echo "=== UI is public; /wd/hub is auth_basic + auth_request + satisfy any ==="
python - <<'PY'
from pathlib import Path

raw = Path("deploy/nginx-selenoid.conf").read_text(encoding="utf-8")
text = "\n".join(line.split("#", 1)[0] for line in raw.splitlines())
if "location ^~ /wd/hub" not in text:
    raise SystemExit("FAIL: missing /wd/hub location")
hub = text.split("location ^~ /wd/hub", 1)[1].split("location ", 1)[0]
if 'auth_basic "Selenoid";' not in hub:
    raise SystemExit("FAIL: /wd/hub must keep auth_basic so clients see WWW-Authenticate")
if "auth_request" not in hub:
    raise SystemExit("FAIL: /wd/hub must use auth_request for personal tokens")
if "satisfy any" not in hub:
    raise SystemExit("FAIL: auth_request on /wd/hub requires satisfy any (do not replace auth_basic)")
if "location = /_auth/selenoid-token" not in text:
    raise SystemExit("FAIL: missing internal /_auth/selenoid-token")
auth = text.split("location = /_auth/selenoid-token", 1)[1].split("location ", 1)[0]
if "internal" not in auth:
    raise SystemExit("FAIL: /_auth/selenoid-token must be internal")
if "proxy_cache" not in auth:
    raise SystemExit("FAIL: /_auth/selenoid-token must cache validator 204")
if "proxy_cache_path /var/cache/nginx/selenoid-token" not in text:
    raise SystemExit("FAIL: missing proxy_cache_path for ~30s token cache")
if "listen 4445" in text:
    extra = text.split("listen 4445", 1)[1]
    if "auth_request" in extra:
        raise SystemExit("FAIL: :4445 must stay htpasswd-only (no auth_request)")
pw = text.split("location ^~ /playwright/", 1)[1].split("location ", 1)[0]
if "auth_request" in pw:
    raise SystemExit("FAIL: /playwright/ must not use auth_request")
ui = text.split("location / {", 1)[1].split("server {", 1)[0]
if "auth_request" in ui or "/oauth2/" in ui:
    raise SystemExit("FAIL: location / must not use oauth2-proxy / auth_request")
if "auth_basic off" not in ui:
    raise SystemExit("FAIL: location / must be public (auth_basic off)")
for chunk in text.split("location "):
    if "auth_request" not in chunk:
        continue
    head = chunk.lstrip()
    if head.startswith("= /_auth/"):
        continue
    if "satisfy any" not in chunk or "auth_basic" not in chunk:
        raise SystemExit("FAIL: auth_request is allowed only together with auth_basic and satisfy any")
print("OK  UI public; /wd/hub auth_basic + auth_request + satisfy any")
PY

echo "=== token-validator self-test ==="
python3 deploy/token-validator.py --self-test

echo "=== tracked repo: no legacy public password literal ==="
if grep -R --exclude='test-auth-wiring.sh' -n 'aAb_' deploy/ .github/ README.md 2>/dev/null; then
  echo "FAIL: legacy password literal still in tracked files" >&2
  exit 1
fi

echo "OK  no legacy password literal in deploy/workflows/docs"

echo "All auth wiring checks passed."
