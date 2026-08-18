#!/usr/bin/env bash
# Post-deploy smoke checks against a public Selenoid base URL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_LIB="${SCRIPT_DIR}/lib/require-public-auth.sh"
if [[ ! -f "$AUTH_LIB" ]]; then
  AUTH_LIB="${SCRIPT_DIR}/../lib/require-public-auth.sh"
fi
# shellcheck source=lib/require-public-auth.sh
source "$AUTH_LIB"

BASE_URL="${1:-${SELENOID_PUBLIC_URL:-}}"
if [[ -z "$BASE_URL" ]]; then
  echo "Usage: $0 <base-url>  (or set SELENOID_PUBLIC_URL)" >&2
  exit 1
fi
BASE_URL="${BASE_URL%/}"

require_public_auth
SELENOID_USER="$SELENOID_PUBLIC_USER"
SELENOID_PASSWORD="$SELENOID_PUBLIC_PASSWORD"
AUTH=(-u "${SELENOID_USER}:${SELENOID_PASSWORD}")
# Guest tokens for nginx ?accessKey= checks (same user:pass as Basic Auth).
PUBLIC_ACCESS_KEY="$(public_access_key)"
STUDENT_ACCESS_KEY="${STUDENT_ACCESS_KEY:-${PLAYWRIGHT_STUDENT_ACCESS_KEY:-user1:1234}}"
CURL_RETRIES="${CURL_RETRIES:-5}"
CURL_RETRY_DELAY="${CURL_RETRY_DELAY:-3}"
PLAYWRIGHT_SMOKE_TIMEOUT="${PLAYWRIGHT_SMOKE_TIMEOUT:-20}"

curl_retry() {
  local url="$1" attempt
  shift
  for attempt in $(seq 1 "$CURL_RETRIES"); do
    if curl "$@" "$url"; then
      return 0
    fi
    if [[ "$attempt" -lt "$CURL_RETRIES" ]]; then
      echo "curl failed (attempt ${attempt}/${CURL_RETRIES}), retry in ${CURL_RETRY_DELAY}s..." >&2
      sleep "$CURL_RETRY_DELAY"
    fi
  done
  return 1
}

urlencode() {
  python -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

curl_http_code() {
  local url="$1" attempt code
  shift
  for attempt in $(seq 1 "$CURL_RETRIES"); do
    code="$(curl -s -o /dev/null -w "%{http_code}" "$@" "$url" 2>/dev/null || true)"
    if [[ -n "$code" && "$code" != "000" ]]; then
      echo "$code"
      return 0
    fi
    if [[ "$attempt" -lt "$CURL_RETRIES" ]]; then
      echo "no HTTP response (attempt ${attempt}/${CURL_RETRIES}), retry in ${CURL_RETRY_DELAY}s..." >&2
      sleep "$CURL_RETRY_DELAY"
    fi
  done
  echo "000"
  return 1
}

echo "=== GET $BASE_URL/status (no auth) — FLAT upstream-selenoid contract ==="
status_json="$(curl_retry "$BASE_URL/status" -fsSL)"
echo "$status_json" | (command -v jq >/dev/null && jq . || cat)

echo "=== GET $BASE_URL/ui/status (no auth) — UI-shaped {state,...} ==="
ui_status_json="$(curl_retry "$BASE_URL/ui/status" -fsSL)"
echo "$ui_status_json" | (command -v jq >/dev/null && jq . || cat)

if ! command -v jq >/dev/null; then
  echo "jq not found — skipping browser version assertions" >&2
  exit 0
fi

# Contract lock: public /status MUST stay FLAT (has .total, no .state wrapper).
# Guards against re-proxying /status to selenoid-ui — the regression (648a34f) that
# broke student autotests written against the original {total,used,...} shape.
if jq -e 'has("total") and (has("state") | not)' <<<"$status_json" >/dev/null; then
  echo "OK  /status is flat {total,used,queued,pending,browsers} (upstream contract)"
else
  echo "FAIL /status must be FLAT hub JSON (has .total, no .state) — do NOT proxy /status to selenoid-ui" >&2
  exit 1
fi

# Box1 warm-pool: hub -warm-pool-url → warmReady/warmTotal + hotReady/hotTotal.
# Skip with EXPECT_WARM_METRICS=0 (non-prod / no orchestrator).
EXPECT_WARM_METRICS="${EXPECT_WARM_METRICS:-1}"
EXPECTED_WARM_TOTAL="${EXPECTED_WARM_TOTAL:-4}"
EXPECTED_HOT_TOTAL="${EXPECTED_HOT_TOTAL:-2}"
if [[ "$EXPECT_WARM_METRICS" != "0" ]]; then
  echo "=== warm-pool metrics (warmReady/warmTotal + hotReady/hotTotal) ==="
  echo "$status_json" | jq '{warmReady,warmTotal,hotReady,hotTotal,used,total}'
  if ! jq -e --argjson n "$EXPECTED_WARM_TOTAL" \
      '(.warmTotal | type == "number") and (.warmTotal >= $n) and (.warmReady | type == "number")' \
      <<<"$status_json" >/dev/null; then
    echo "FAIL /status must expose warmReady/warmTotal>=${EXPECTED_WARM_TOTAL} (hub -warm-pool-url + live orchestrator)" >&2
    exit 1
  fi
  if ! jq -e --argjson n "$EXPECTED_WARM_TOTAL" \
      '(.state.warmTotal | type == "number") and (.state.warmTotal >= $n)' \
      <<<"$ui_status_json" >/dev/null; then
    echo "FAIL /ui/status.state must expose warmTotal>=${EXPECTED_WARM_TOTAL} for UI WARM tile" >&2
    exit 1
  fi
  if ! jq -e --argjson n "$EXPECTED_HOT_TOTAL" \
      '(.hotTotal | type == "number") and (.hotTotal >= $n) and (.hotReady | type == "number")' \
      <<<"$status_json" >/dev/null; then
    echo "FAIL /status must expose hotReady/hotTotal>=${EXPECTED_HOT_TOTAL} (hub split pool=hot)" >&2
    exit 1
  fi
  if ! jq -e --argjson n "$EXPECTED_HOT_TOTAL" \
      '(.state.hotTotal | type == "number") and (.state.hotTotal >= $n)' \
      <<<"$ui_status_json" >/dev/null; then
    echo "FAIL /ui/status.state must expose hotTotal>=${EXPECTED_HOT_TOTAL} for UI HOT tile" >&2
    exit 1
  fi
  echo "OK  warm 4/4 + hot 2/2 present (hub + UI feed)"
fi

echo "=== browser versions ==="
for pair in "chrome:149.0" "firefox:151.0" "msedge:145.0" "playwright-chromium:1.61.1" "playwright-chrome:1.61.1" "playwright-msedge:1.61.1"; do
  browser="${pair%%:*}"
  version="${pair##*:}"
  # flat /status → .browsers[b][v]; UI /ui/status → .state.browsers[b][v]
  if jq -e --arg b "$browser" --arg v "$version" '.browsers[$b][$v] != null' <<<"$status_json" >/dev/null \
     && jq -e --arg b "$browser" --arg v "$version" '.state.browsers[$b][$v] != null' <<<"$ui_status_json" >/dev/null; then
    echo "OK  $browser $version"
  else
    echo "FAIL $browser $version missing in /status (flat) and/or /ui/status (.state)" >&2
    exit 1
  fi
done

# UI v3.0.7+: guest creds are build-time hubAuth (VITE_HUB_ACCESS_KEY), not /ui/status.accessKey
# and not a runtime -access-key / -playwright-access-key flag.
if jq -e 'has("accessKey") or has("playwrightAccessKey")' <<<"$ui_status_json" >/dev/null; then
  echo "FAIL /ui/status must not expose accessKey/playwrightAccessKey (hubAuth is build-time)" >&2
  exit 1
fi
echo "OK  /ui/status has no accessKey field (hubAuth build-time)"

echo "=== GET $BASE_URL/ (UI, no auth) ==="
ui_code="$(curl_http_code "$BASE_URL/")"
if [[ "$ui_code" == "200" ]]; then
  echo "OK  UI is public (HTTP 200)"
else
  echo "FAIL UI should be public without credentials (HTTP $ui_code)" >&2
  exit 1
fi

echo "=== GET $BASE_URL/wd/hub/status without auth (expect 401) ==="
wd_no_auth="$(curl_http_code "$BASE_URL/wd/hub/status")"
if [[ "$wd_no_auth" == "401" ]]; then
  echo "OK  /wd/hub requires auth (HTTP 401)"
else
  echo "FAIL /wd/hub should require auth (HTTP $wd_no_auth)" >&2
  exit 1
fi

echo "=== GET $BASE_URL/wd/hub/status (with basic auth) ==="
wd_json="$(curl_retry "$BASE_URL/wd/hub/status" -fsSL "${AUTH[@]}")"
echo "$wd_json" | (command -v jq >/dev/null && jq . || cat)
if ! jq -e '.value.ready == true' <<<"$wd_json" >/dev/null; then
  echo "FAIL /wd/hub/status ready!=true" >&2
  exit 1
fi
echo "OK  /wd/hub with auth (ready)"

# /status.version is selenoid-ui build stamp; hub revision lives in W3C /wd/hub/status.
EXPECTED_HUB_VERSION="${EXPECTED_HUB_VERSION:-${SELENOID_VERSION:-v3.0.5}}"
EXPECTED_HUB_VERSION="${EXPECTED_HUB_VERSION#v}"
hub_msg="$(jq -r '.value.message // empty' <<<"$wd_json")"
if [[ "$hub_msg" == *"Selenoid v${EXPECTED_HUB_VERSION}"* ]]; then
  echo "OK  hub version: $hub_msg"
else
  echo "FAIL hub version: want Selenoid v${EXPECTED_HUB_VERSION}*, got: ${hub_msg:-<empty>}" >&2
  exit 1
fi

# UI build stamp lives on /ui/status (flat public /status is hub — no .version).
ui_version="$(jq -r '.version // empty' <<<"$ui_status_json")"
EXPECTED_UI_VERSION="${EXPECTED_UI_VERSION:-${SELENOID_UI_VERSION:-v3.0.45}}"
EXPECTED_UI_VERSION="${EXPECTED_UI_VERSION#v}"
# Releases often stamp gitRevision[buildStamp], not the semver tag.
EXPECTED_UI_MINOR="${EXPECTED_UI_VERSION%.*}"
UI_REV_OK=false
if [[ -z "$ui_version" ]]; then
  echo "FAIL UI /ui/status.version empty" >&2
  exit 1
fi
if [[ -n "$EXPECTED_UI_VERSION" ]]; then
  if [[ "$ui_version" == v${EXPECTED_UI_VERSION}* ]] || [[ "$ui_version" == ${EXPECTED_UI_VERSION}* ]]; then
    UI_REV_OK=true
  elif [[ -n "$EXPECTED_UI_MINOR" && "$ui_version" == v${EXPECTED_UI_MINOR}.* ]]; then
    UI_REV_OK=true
  fi
fi
if [[ "$UI_REV_OK" != true ]]; then
  UI_ALT="${SELENOID_UI_GIT_REVISION:-}"
  UI_ALT="${UI_ALT#v}"
  if [[ -n "$UI_ALT" && "$ui_version" == ${UI_ALT}* ]]; then
    UI_REV_OK=true
  fi
fi
# Accept gitRevision[buildStamp] when pin is a release tag (binary rarely embeds semver).
if [[ "$UI_REV_OK" != true && "$ui_version" =~ ^[0-9a-f]{7,40}\[ ]]; then
  UI_REV_OK=true
  if [[ -n "$EXPECTED_UI_VERSION" ]]; then
    echo "OK  UI /ui/status.version: $ui_version (git stamp; pin v${EXPECTED_UI_VERSION})"
  else
    echo "OK  UI /ui/status.version: $ui_version"
  fi
elif [[ "$UI_REV_OK" == true ]]; then
  echo "OK  UI /ui/status.version: $ui_version"
else
  echo "FAIL UI version: want v${EXPECTED_UI_VERSION}* / v${EXPECTED_UI_MINOR}.* (or SELENOID_UI_GIT_REVISION), got: ${ui_version}" >&2
  exit 1
fi

echo "=== GET $BASE_URL/playwright/... without accessKey (expect 401) ==="
pw_no_key="$(curl_http_code "$BASE_URL/playwright/playwright-chromium/1.61.1" --max-time "$PLAYWRIGHT_SMOKE_TIMEOUT")"
if [[ "$pw_no_key" == "401" ]]; then
  echo "OK  /playwright/ requires accessKey at nginx edge (HTTP 401)"
else
  echo "FAIL /playwright/ should require accessKey (HTTP $pw_no_key, want 401)" >&2
  exit 1
fi

echo "=== GET $BASE_URL/playwright/... with student/public accessKey (expect 400 — WS upgrade required) ==="
for key in "$STUDENT_ACCESS_KEY" "$PUBLIC_ACCESS_KEY"; do
  encoded_key="$(urlencode "$key")"
  pw_code="$(curl_http_code "$BASE_URL/playwright/playwright-chromium/1.61.1?accessKey=${encoded_key}" --max-time "$PLAYWRIGHT_SMOKE_TIMEOUT")"
  if [[ "$pw_code" == "400" || "$pw_code" == "426" ]]; then
    echo "OK  /playwright/ accepts accessKey=${key%%:*}:*** (HTTP $pw_code)"
  else
    echo "FAIL /playwright/ should accept accessKey=${key%%:*}:*** (HTTP $pw_code, want 400/426)" >&2
    exit 1
  fi
done

echo "=== GET $BASE_URL/har/?json (expect 200 — HAR listing enabled) ==="
har_list="$(curl -sSL "$BASE_URL/har/?json" 2>/dev/null || true)"
if echo "$har_list" | jq -e '.total != null and (.videos | type == "array")' >/dev/null 2>&1; then
  echo "OK  /har/?json listing enabled (total=$(echo "$har_list" | jq -r .total))"
else
  echo "FAIL /har/?json should list HAR files (got: ${har_list:0:160})" >&2
  echo "     (hub needs -har-output-dir in selenoid-hub.service / deploy.sh)" >&2
  exit 1
fi

echo "=== GET $BASE_URL/logs/unknown-session with auth (expect 400 — WS upgrade required) ==="
logs_code="$(curl_http_code "$BASE_URL/logs/unknown-session" "${AUTH[@]}")"
if [[ "$logs_code" == "400" ]]; then
  echo "OK  /logs/ proxied to hub (HTTP 400)"
else
  echo "FAIL /logs/ should proxy to hub with auth (HTTP $logs_code, want 400)" >&2
  exit 1
fi

echo "=== GET $BASE_URL/logs/unknown-session without auth (expect 401) ==="
logs_no_auth="$(curl_http_code "$BASE_URL/logs/unknown-session")"
if [[ "$logs_no_auth" == "401" ]]; then
  echo "OK  /logs/ requires auth (HTTP 401)"
else
  echo "FAIL /logs/ should require auth (HTTP $logs_no_auth)" >&2
  exit 1
fi

echo "=== GET $BASE_URL/error with auth (expect 404 — invalid session JSON) ==="
# Hub returns HTTP 404 with valid JSON — do not use curl -f here.
error_json="$(curl -sSL "${AUTH[@]}" "$BASE_URL/error" 2>/dev/null || true)"
echo "$error_json" | (command -v jq >/dev/null && jq . || cat)
if jq -e '.value.error == "invalid session id"' <<<"$error_json" >/dev/null; then
  echo "OK  /error proxied to hub (invalid session JSON)"
else
  echo "FAIL /error should proxy to hub invalid-session JSON" >&2
  exit 1
fi

echo "=== GET $BASE_URL/error without auth (expect 401) ==="
error_no_auth="$(curl_http_code "$BASE_URL/error")"
if [[ "$error_no_auth" == "401" ]]; then
  echo "OK  /error requires auth (HTTP 401)"
else
  echo "FAIL /error should require auth (HTTP $error_no_auth)" >&2
  exit 1
fi

echo "=== GET $BASE_URL/vnc/unknown-session with auth (expect 400 — WS upgrade required) ==="
vnc_code="$(curl_http_code "$BASE_URL/vnc/unknown-session" "${AUTH[@]}")"
if [[ "$vnc_code" == "400" ]]; then
  echo "OK  /vnc/ proxied to hub (HTTP 400)"
else
  echo "FAIL /vnc/ should proxy to hub with auth (HTTP $vnc_code, want 400)" >&2
  exit 1
fi

echo "=== GET $BASE_URL/vnc/unknown-session without auth (expect 401) ==="
vnc_no_auth="$(curl_http_code "$BASE_URL/vnc/unknown-session")"
if [[ "$vnc_no_auth" == "401" ]]; then
  echo "OK  /vnc/ requires auth (HTTP 401)"
else
  echo "FAIL /vnc/ should require auth (HTTP $vnc_no_auth)" >&2
  exit 1
fi

echo "Smoke OK: $BASE_URL (auth: $SELENOID_USER:***)"
