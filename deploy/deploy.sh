#!/usr/bin/env bash
# Deploy qa-guru Selenoid stack via cm (hub + UI + browser images).
# Run on the server as selenoid — not via sudo.
set -euo pipefail

CONFIG_DIR="${SELENOID_CONFIG_DIR:-/opt/selenoid}"
CM_BIN="${CM_BIN:-$HOME/cm}"
CM_URL="${CM_URL:-https://github.com/qa-guru/cm/releases/latest/download/cm_linux_amd64}"
VERSION="${SELENOID_VERSION:-v3.0.4}"
UI_VERSION="${SELENOID_UI_VERSION:-v3.0.13}"
CM_VERSION="${CM_VERSION:-v3.0.1}"
VIDEO_RECORDER_IMAGE="${VIDEO_RECORDER_IMAGE:-qaguru/video-recorder:latest}"
GITHUB_OWNER="${GITHUB_OWNER:-qa-guru}"
version_args=()
if [[ -n "$VERSION" ]]; then
  version_args=(-v "$VERSION")
fi

if ! groups | grep -qw docker; then
  echo "Current user is not in the docker group. Run deploy/bootstrap.sh first." >&2
  exit 1
fi

mkdir -p "$CONFIG_DIR/bin"

if [[ ! -x "$CM_BIN" ]]; then
  echo "Downloading cm to $CM_BIN"
  curl -fsSL "$CM_URL" -o "$CM_BIN"
  chmod +x "$CM_BIN"
fi

refresh_cm() {
  # cm release tags are independent of hub SELENOID_VERSION
  local tag="${CM_VERSION:-latest}"
  local url="https://github.com/${GITHUB_OWNER}/cm/releases/download/${tag}/cm_linux_amd64"
  if [[ "$tag" == "latest" ]]; then
    url="$CM_URL"
  fi
  echo "Refreshing cm from ${url}"
  curl -fsSL "$url" -o "${CM_BIN}.new.$$"
  chmod +x "${CM_BIN}.new.$$"
  mv "${CM_BIN}.new.$$" "$CM_BIN"
}
refresh_cm

download_binary() {
  local repo="$1" dest="$2" tag="${3:-${VERSION:-latest}}"
  local url="https://github.com/${GITHUB_OWNER}/${repo}/releases/download/${tag}/${repo}_linux_amd64"
  local tmp="${dest}.new.$$"
  echo "Downloading ${repo} ${tag} → ${dest}"
  curl -fsSL "$url" -o "$tmp"
  chmod 755 "$tmp"
  mv "$tmp" "$dest"
}

echo "=== stop legacy containers ==="
docker stop selenoid selenoid-ui 2>/dev/null || true
docker rm selenoid selenoid-ui 2>/dev/null || true

echo "=== stop cm-managed services ==="
"$CM_BIN" selenoid stop -c "$CONFIG_DIR" 2>/dev/null || true
"$CM_BIN" selenoid-ui stop -c "$CONFIG_DIR" 2>/dev/null || true

echo "=== stop systemd-managed hub (if any) before binary refresh ==="
sudo -n systemctl stop selenoid-hub.service 2>/dev/null || true

if pgrep -f "${CONFIG_DIR}/bin/selenoid" >/dev/null 2>&1; then
  pkill -f "${CONFIG_DIR}/bin/selenoid" || true
  sleep 1
fi

echo "=== download hub binaries (selenoid ${VERSION:-latest}, selenoid-ui ${UI_VERSION:-latest}) ==="
download_binary selenoid "$CONFIG_DIR/bin/selenoid" "$VERSION"
download_binary selenoid-ui "$CONFIG_DIR/bin/selenoid-ui" "$UI_VERSION"

echo "=== configure hub (browsers.json + pull images) ==="
BROWSERS_PRODUCTION="${BROWSERS_PRODUCTION:-/tmp/browsers-production.json}"
if [[ -f "$BROWSERS_PRODUCTION" ]]; then
  echo "=== apply production browsers.json (skip cm configure) ==="
  cp "$BROWSERS_PRODUCTION" "$CONFIG_DIR/browsers.json"
else
  "$CM_BIN" selenoid configure -c "$CONFIG_DIR" -f "${version_args[@]}"
fi

echo "=== pull all browser images from browsers.json (always refresh tags) ==="
pull_images() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.. | objects | select(has("image")) | .image' "$CONFIG_DIR/browsers.json" | sort -u
  else
    grep -oE '"image": "[^"]+"' "$CONFIG_DIR/browsers.json" | cut -d'"' -f4 | sort -u
  fi
}
while read -r img; do
  [[ -z "$img" ]] && continue
  echo "--- docker pull ${img} ---"
  docker pull "$img"
  docker image inspect "$img" --format '{{.RepoTags}} {{.Id}} {{.Created}}' 2>/dev/null || true
done < <(pull_images)
docker pull "${VIDEO_RECORDER_IMAGE}"

mkdir -p "$CONFIG_DIR/video" "$CONFIG_DIR/logs" "$CONFIG_DIR/har"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# cleanup/retention scripts live next to deploy.sh when run from a clone or GHA staging.
for helper in cleanup-videos.sh video-retention.sh; do
  if [[ -f "${SCRIPT_DIR}/${helper}" ]]; then
    install -m 755 "${SCRIPT_DIR}/${helper}" "${CONFIG_DIR}/bin/${helper}"
  fi
done

# Auth SSOT (v3.0.7+):
# - WebDriver: nginx Basic Auth (htpasswd)
# - Playwright WS: nginx map on ?accessKey=
# - UI Create Session / snippets: build-time hubAuth (VITE_HUB_ACCESS_KEY), not a runtime flag
# Drop stale playwright-access.env left by older deploys.
rm -f "${CONFIG_DIR}/playwright-access.env"

echo "=== docker network selenoid ==="
docker network inspect selenoid >/dev/null 2>&1 || docker network create selenoid

echo "=== start hub (native binary on host — hub-in-docker breaks browser port bindings) ==="
# Do NOT pin DOCKER_API_VERSION: moby client auto-negotiates with the engine
# (Docker Engine 29.x → API 1.55). A stale pin (e.g. 1.45) is unnecessary.
unset DOCKER_API_VERSION || true

# Remove any stale cm-managed hub-in-docker container that would hold :4444.
docker stop selenoid 2>/dev/null || true
docker rm selenoid 2>/dev/null || true

HUB_UNIT_SRC="${HUB_UNIT_SRC:-${SCRIPT_DIR}/selenoid-hub.service}"
if [[ ! -f "$HUB_UNIT_SRC" && -f /tmp/selenoid-hub.service ]]; then
  HUB_UNIT_SRC=/tmp/selenoid-hub.service
fi
# Strip legacy access-key EnvironmentFile / flags from older unit copies.
HUB_UNIT_RENDER="/tmp/selenoid-hub.service.rendered"
if [[ -f "$HUB_UNIT_SRC" ]]; then
  sed -e '/EnvironmentFile=.*playwright-access.env/d' \
      -e '/EnvironmentFile=.*access.env/d' \
      -e '/-playwright-access-key=/d' \
      -e '/-access-key=/d' \
      "$HUB_UNIT_SRC" >"$HUB_UNIT_RENDER"
  HUB_UNIT_SRC="$HUB_UNIT_RENDER"
fi
HUB_UNIT_DEST="/etc/systemd/system/selenoid-hub.service"
hub_via_systemd=false
# sudoers allow only: install -m 644 /tmp/selenoid-hub.service → unit path
if [[ -f "$HUB_UNIT_SRC" ]]; then
  install -m 644 "$HUB_UNIT_SRC" /tmp/selenoid-hub.service
  echo "--- install + enable systemd unit selenoid-hub.service (autostart on reboot) ---"
  if sudo -n install -m 644 /tmp/selenoid-hub.service "$HUB_UNIT_DEST" \
    && sudo -n systemctl daemon-reload \
    && sudo -n systemctl enable selenoid-hub.service \
    && sudo -n systemctl restart selenoid-hub.service; then
    hub_via_systemd=true
    echo "OK  hub managed by systemd — :4444 comes up automatically after reboot"
  else
    echo "WARN: systemd unit install failed — falling back to nohup (no autostart)" >&2
  fi
fi

if [[ "$hub_via_systemd" != true ]] && systemctl is-active --quiet selenoid-hub.service 2>/dev/null; then
  # Unit exists and owns :4444 but we lack sudo to manage it — do NOT nohup
  # (that would pkill the systemd-managed process and fight Restart=always).
  echo "--- selenoid-hub.service already active; not starting nohup ---"
  if ! sudo -n systemctl restart selenoid-hub.service 2>/dev/null; then
    echo "WARN: apply new browsers.json/binary manually: sudo systemctl restart selenoid-hub.service" >&2
  fi
  hub_via_systemd=true
fi

if [[ "$hub_via_systemd" != true ]]; then
  echo "--- start hub via nohup (no reboot autostart; install selenoid-hub.service for that) ---" >&2
  pkill -f "${CONFIG_DIR}/bin/selenoid" 2>/dev/null || true
  nohup "${CONFIG_DIR}/bin/selenoid" \
    -conf "${CONFIG_DIR}/browsers.json" \
    -limit 25 \
    -container-network selenoid \
    -video-output-dir "${CONFIG_DIR}/video/" \
    -video-recorder-image "${VIDEO_RECORDER_IMAGE}" \
    -log-output-dir "${CONFIG_DIR}/logs/" \
    -har-output-dir "${CONFIG_DIR}/har/" \
    -listen :4444 \
    >> "${CONFIG_DIR}/logs/selenoid.log" 2>&1 &
fi

for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sf "http://127.0.0.1:4444/status" >/dev/null 2>&1; then
    break
  fi
  echo "hub /status not ready (attempt ${attempt}/10)..." >&2
  sleep 2
done

echo "=== start UI (host network -> 127.0.0.1:4444) ==="
"$CM_BIN" selenoid-ui download -c "$CONFIG_DIR" "${version_args[@]}" 2>/dev/null || true
docker stop selenoid-ui 2>/dev/null || true
docker rm selenoid-ui 2>/dev/null || true
"$CM_BIN" selenoid-ui stop -c "$CONFIG_DIR" 2>/dev/null || true

UI_IMAGE="qaguru/selenoid-ui:latest-release"
docker pull "$UI_IMAGE" >/dev/null 2>&1 || true
docker run -d --name selenoid-ui \
  --restart unless-stopped \
  --network host \
  -v "${CONFIG_DIR}:/etc/selenoid:ro" \
  -v "${CONFIG_DIR}/bin/selenoid-ui:/selenoid-ui:ro" \
  --entrypoint /selenoid-ui \
  "$UI_IMAGE" \
    -selenoid-uri=http://127.0.0.1:4444 \
    -browsers-conf=/etc/selenoid/browsers.json \
    -listen=:8080

echo "=== local hub status ==="
curl -sf "http://127.0.0.1:4444/status" | (command -v jq >/dev/null && jq . || cat)
echo

echo "=== UI backend status ==="
# Do not use shared /tmp for body — another user (e.g. qaguru) may own the file
# and curl exit 23 then appends "000" via || → HTTP "200000".
UI_STATUS_FILE="${CONFIG_DIR}/logs/ui-status.$$.json"
ui_json=""
ui_http="000"
for attempt in 1 2 3 4 5 6; do
  ui_http="000"
  if curl -sS -o "$UI_STATUS_FILE" -w '%{http_code}' "http://127.0.0.1:8080/status" >"${UI_STATUS_FILE}.code" 2>/dev/null; then
    ui_http="$(tr -d '[:space:]' <"${UI_STATUS_FILE}.code")"
  fi
  rm -f "${UI_STATUS_FILE}.code"
  if [[ "$ui_http" == "200" ]]; then
    ui_json="$(cat "$UI_STATUS_FILE")"
    break
  fi
  echo "UI /status HTTP ${ui_http} (attempt ${attempt}/6), waiting..." >&2
  sleep 2
done
rm -f "$UI_STATUS_FILE" "${UI_STATUS_FILE}.code"
if [[ "$ui_http" != "200" || -z "$ui_json" ]]; then
  echo "FAIL: selenoid-ui /status HTTP ${ui_http}" >&2
  docker logs --tail 40 selenoid-ui 2>&1 || true
  docker inspect selenoid-ui --format '{{json .Config.Cmd}}' 2>&1 || true
  exit 1
fi
if command -v jq >/dev/null; then
  echo "$ui_json" | jq .
  if jq -e '.errors | length > 0' <<<"$ui_json" >/dev/null 2>&1; then
    echo "FAIL: selenoid-ui cannot reach hub (see errors above)" >&2
    docker logs --tail 40 selenoid-ui 2>&1 || true
    docker inspect selenoid-ui --format '{{json .Config.Cmd}}' 2>&1 || true
    exit 1
  fi
  if ! jq -e '.state.total != null' <<<"$ui_json" >/dev/null 2>&1; then
    echo "FAIL: selenoid-ui /status missing .state — check --selenoid-uri" >&2
    docker logs --tail 40 selenoid-ui 2>&1 || true
    docker inspect selenoid-ui --format '{{json .Config.Cmd}}' 2>&1 || true
    exit 1
  fi
else
  echo "$ui_json"
fi

ui_body="$(curl -sS "http://127.0.0.1:8080/" 2>/dev/null || true)"
ui_code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:8080/" 2>/dev/null || echo "000")"
if [[ "$ui_code" == "200" ]] && [[ "$ui_body" == *app-header* || "$ui_body" == *'data-testid="stats-bar"'* || "$ui_body" == *'id="root"'* ]]; then
  echo "OK  UI is public (HTTP 200, frontend shell present)"
elif [[ "$ui_code" == "200" ]]; then
  echo "FAIL: selenoid-ui returned HTTP 200 but frontend is missing (broken statik build?)" >&2
  echo "      Response starts with: ${ui_body:0:120}" >&2
  docker logs --tail 40 selenoid-ui 2>&1 || true
  docker inspect selenoid-ui --format '{{json .Config.Cmd}}' 2>&1 || true
  exit 1
else
  echo "FAIL: selenoid-ui returned HTTP ${ui_code} (expected 200)" >&2
  docker logs --tail 40 selenoid-ui 2>&1 || true
  docker inspect selenoid-ui --format '{{json .Config.Cmd}}' 2>&1 || true
  exit 1
fi
echo

echo "=== smoke: create chrome session ==="
session_json="$(curl -sS -m 120 -X POST "http://127.0.0.1:4444/wd/hub/session" \
  -H 'Content-Type: application/json' \
  -d '{"capabilities":{"alwaysMatch":{"browserName":"chrome","browserVersion":"149.0","selenoid:options":{"sessionTimeout":"30s","name":"deploy-smoke","enableVNC":true,"enableVideo":true}}}}' || true)"
if command -v jq >/dev/null; then
  session_id="$(jq -r '.value.sessionId // .sessionId // empty' <<<"$session_json")"
  if [[ -z "$session_id" ]]; then
    echo "FAIL: could not create chrome session: $session_json" >&2
    tail -30 "${CONFIG_DIR}/logs/selenoid.log" 2>&1 || true
    exit 1
  fi
  echo "OK  session ${session_id}"
  curl -sS -X DELETE "http://127.0.0.1:4444/wd/hub/session/${session_id}" >/dev/null || true
else
  echo "$session_json"
fi

echo "=== smoke: create firefox session ==="
session_json="$(curl -sS -m 120 -X POST "http://127.0.0.1:4444/wd/hub/session" \
  -H 'Content-Type: application/json' \
  -d '{"capabilities":{"alwaysMatch":{"browserName":"firefox","browserVersion":"151.0","selenoid:options":{"sessionTimeout":"30s","name":"deploy-smoke","enableVNC":true}}}}' || true)"
if command -v jq >/dev/null; then
  session_id="$(jq -r '.value.sessionId // .sessionId // empty' <<<"$session_json")"
  if [[ -z "$session_id" ]]; then
    echo "FAIL: could not create firefox session: $session_json" >&2
    tail -30 "${CONFIG_DIR}/logs/selenoid.log" 2>&1 || true
    exit 1
  fi
  echo "OK  session ${session_id}"
  curl -sS -X DELETE "http://127.0.0.1:4444/wd/hub/session/${session_id}" >/dev/null || true
else
  echo "$session_json"
fi

echo "=== smoke: create firefox-min session ==="
session_json="$(curl -sS -m 120 -X POST "http://127.0.0.1:4444/wd/hub/session" \
  -H 'Content-Type: application/json' \
  -d '{"capabilities":{"alwaysMatch":{"browserName":"firefox","browserVersion":"151.0-min","selenoid:options":{"sessionTimeout":"30s","name":"deploy-smoke","enableVNC":false,"enableVideo":false}}}}' || true)"
if command -v jq >/dev/null; then
  session_id="$(jq -r '.value.sessionId // .sessionId // empty' <<<"$session_json")"
  if [[ -z "$session_id" ]]; then
    echo "FAIL: could not create firefox-min session: $session_json" >&2
    tail -30 "${CONFIG_DIR}/logs/selenoid.log" 2>&1 || true
    exit 1
  fi
  echo "OK  session ${session_id}"
  curl -sS -X DELETE "http://127.0.0.1:4444/wd/hub/session/${session_id}" >/dev/null || true
else
  echo "$session_json"
fi

echo "=== smoke: create msedge session ==="
session_json="$(curl -sS -m 120 -X POST "http://127.0.0.1:4444/wd/hub/session" \
  -H 'Content-Type: application/json' \
  -d '{"capabilities":{"alwaysMatch":{"browserName":"MicrosoftEdge","browserVersion":"145.0","selenoid:options":{"sessionTimeout":"30s","name":"deploy-smoke","enableVNC":true}}}}' || true)"
if command -v jq >/dev/null; then
  session_id="$(jq -r '.value.sessionId // .sessionId // empty' <<<"$session_json")"
  if [[ -z "$session_id" ]]; then
    echo "FAIL: could not create msedge session: $session_json" >&2
    tail -30 "${CONFIG_DIR}/logs/selenoid.log" 2>&1 || true
    exit 1
  fi
  echo "OK  session ${session_id}"
  curl -sS -X DELETE "http://127.0.0.1:4444/wd/hub/session/${session_id}" >/dev/null || true
else
  echo "$session_json"
fi
echo
docker ps --filter name=selenoid --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
pgrep -af "${CONFIG_DIR}/bin/selenoid" || true

echo "=== nginx (basic auth on /wd/hub; /playwright/ public for UI WebSocket) ==="
NGINX_CONF="${NGINX_CONF_SRC:-/tmp/nginx-selenoid.conf}"
NGINX_SYNC="${NGINX_SYNC_SCRIPT:-/tmp/sync-nginx.sh}"
if [[ ! -f "$NGINX_CONF" || ! -f "$NGINX_SYNC" ]]; then
  echo "WARN: nginx config not found ($NGINX_CONF / $NGINX_SYNC) — skip"
elif timeout 60 env NGINX_CONF_SRC="$NGINX_CONF" sudo -n "$NGINX_SYNC"; then
  echo "OK  nginx config applied"
else
  echo "WARN: nginx sync failed or timed out — run on server as root:" >&2
  echo "  sudo ./deploy/bootstrap.sh   # once, installs NOPASSWD for sync-nginx.sh" >&2
  echo "  sudo NGINX_CONF_SRC=$NGINX_CONF $NGINX_SYNC" >&2
fi

exit 0
