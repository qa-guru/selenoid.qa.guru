#!/usr/bin/env bash
# Remote update for selenoid.qa.guru (run as selenoid over SSH, not root).
set -euo pipefail
LOG=/tmp/selenoid-deploy.log
exec > >(tee -a "$LOG") 2>&1

echo "DEPLOY_START $(date -Is)"

CONFIG_DIR="${SELENOID_CONFIG_DIR:-/opt/selenoid}"
CM_BIN="${CM_BIN:-$HOME/cm}"

if ! groups | grep -qw docker; then
  echo "Current user is not in the docker group. Run deploy/bootstrap.sh first." >&2
  exit 1
fi

if [[ ! -x "$CM_BIN" ]]; then
  curl -fsSL https://github.com/qa-guru/cm/releases/latest/download/cm_linux_amd64 -o "$CM_BIN"
  chmod +x "$CM_BIN"
fi

"$CM_BIN" selenoid stop -c "$CONFIG_DIR" || true
"$CM_BIN" selenoid-ui stop -c "$CONFIG_DIR" || true

"$CM_BIN" selenoid update -c "$CONFIG_DIR"
"$CM_BIN" selenoid-ui update -c "$CONFIG_DIR"

echo "=== status ==="
curl -sf http://127.0.0.1:4444/status || true
echo
docker ps --filter name=selenoid --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
ls -la "$CONFIG_DIR/bin" 2>/dev/null || true

echo "DEPLOY_DONE $(date -Is)"
