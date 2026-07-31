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

echo "=== tracked repo: no legacy public password literal ==="
if grep -R --exclude='test-auth-wiring.sh' -n 'aAb_' deploy/ .github/ README.md 2>/dev/null; then
  echo "FAIL: legacy password literal still in tracked files" >&2
  exit 1
fi

echo "OK  no legacy password literal in deploy/workflows/docs"

echo "All auth wiring checks passed."
