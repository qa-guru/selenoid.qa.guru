#!/usr/bin/env bash
# Live /wd/hub auth cases: guest htpasswd, personal token, bad token, anonymous.
# Does not print secrets. Deletes the probe session.
set -euo pipefail

BASE_URL="${1:-${SELENOID_PUBLIC_URL:-https://selenoid.qa.guru}}"
BASE_URL="${BASE_URL%/}"
GUEST_USER="${SELENOID_STUDENT_USER:-user1}"
GUEST_PASSWORD="${SELENOID_STUDENT_PASSWORD:-1234}"
TOKEN_USER="${SELENOID_TOKEN_USER:?SELENOID_TOKEN_USER required}"
TOKEN_VALUE="${SELENOID_TOKEN:?SELENOID_TOKEN required}"
export SELENOID_PROBE_CHROME="${SELENOID_PROBE_CHROME:-152.0}"

payload="$(python3 -c '
import json, os
print(json.dumps({
  "capabilities": {
    "alwaysMatch": {
      "browserName": "chrome",
      "browserVersion": os.environ["SELENOID_PROBE_CHROME"],
      "selenoid:options": {"enableVNC": False, "enableVideo": False},
    }
  }
}))
')"

fail() { echo "FAIL: $*" >&2; exit 1; }

anon_headers="$(mktemp)"
anon_code="$(curl -sS -D "$anon_headers" -o /dev/null -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' -d "$payload" \
  "${BASE_URL}/wd/hub/session")"
if [[ "$anon_code" != "401" ]]; then
  fail "anonymous want 401, got ${anon_code}"
fi
if ! grep -qiE '^www-authenticate:[[:space:]]*Basic' "$anon_headers"; then
  cat "$anon_headers" >&2
  fail "anonymous missing WWW-Authenticate: Basic"
fi
rm -f "$anon_headers"
echo "OK  anonymous 401 + WWW-Authenticate: Basic"

bad_code="$(curl -sS -o /dev/null -w '%{http_code}' \
  -u "${TOKEN_USER}:definitely-not-a-valid-selenoid-token" \
  -X POST -H 'Content-Type: application/json' -d "$payload" \
  "${BASE_URL}/wd/hub/session")"
if [[ "$bad_code" != "401" ]]; then
  fail "bad token want 401, got ${bad_code}"
fi
echo "OK  bad token 401"

guest_code="$(curl -sS -o /dev/null -w '%{http_code}' \
  -u "${GUEST_USER}:${GUEST_PASSWORD}" \
  "${BASE_URL}/wd/hub/status")"
if [[ "$guest_code" != "200" ]]; then
  fail "guest htpasswd /wd/hub/status want 200, got ${guest_code}"
fi
echo "OK  guest htpasswd 200"

session_json="$(curl -sS -u "${TOKEN_USER}:${TOKEN_VALUE}" \
  -X POST -H 'Content-Type: application/json' -d "$payload" \
  --max-time 90 \
  "${BASE_URL}/wd/hub/session")"
session_id="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("value") or {}).get("sessionId") or d.get("sessionId") or "")' <<<"$session_json")"
if [[ -z "$session_id" ]]; then
  echo "$session_json" >&2
  fail "handle+token did not create a session"
fi
curl -sS -o /dev/null -u "${TOKEN_USER}:${TOKEN_VALUE}" \
  -X DELETE "${BASE_URL}/wd/hub/session/${session_id}" || true
echo "OK  handle+token session ${session_id:0:8}…"
echo "All /wd/hub personal-token checks passed."
