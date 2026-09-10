#!/usr/bin/env bash
# Install loopback token validator on Box1. Does not touch selenoid-hub.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_SRC="${SCRIPT_DIR}/selenoid-token-validator.service"
BIN_SRC="${SCRIPT_DIR}/token-validator.py"
ENV_SRC="${TOKEN_VALIDATOR_ENV:-}"
CONFIG_DIR="${SELENOID_CONFIG_DIR:-/opt/selenoid}"
CACHE_DIR="${SELENOID_TOKEN_CACHE_DIR:-/var/cache/nginx/selenoid-token}"

if [[ "$(id -u)" -ne 0 ]]; then
  if sudo -n true 2>/dev/null; then
    exec sudo env \
      TOKEN_VALIDATOR_ENV="${ENV_SRC}" \
      SELENOID_CONFIG_DIR="${CONFIG_DIR}" \
      SELENOID_TOKEN_CACHE_DIR="${CACHE_DIR}" \
      "$0" "$@"
  fi
  echo "Run as root or with passwordless sudo: sudo $0" >&2
  exit 1
fi

if [[ ! -f "$BIN_SRC" || ! -f "$UNIT_SRC" ]]; then
  echo "Missing $BIN_SRC or $UNIT_SRC" >&2
  exit 1
fi
if [[ -z "$ENV_SRC" || ! -f "$ENV_SRC" ]]; then
  echo "Set TOKEN_VALIDATOR_ENV to a 600 env file with KEYCLOAK_CLIENT_SECRET" >&2
  exit 1
fi
if ! grep -q '^KEYCLOAK_CLIENT_SECRET=' "$ENV_SRC" || ! grep -q '^KEYCLOAK_BASE_URL=' "$ENV_SRC"; then
  echo "TOKEN_VALIDATOR_ENV must set KEYCLOAK_BASE_URL and KEYCLOAK_CLIENT_SECRET" >&2
  exit 1
fi

install -d -m 755 -o selenoid -g selenoid "${CONFIG_DIR}/bin"
install -m 755 "$BIN_SRC" "${CONFIG_DIR}/bin/token-validator.py"
install -d -m 750 /etc/selenoid
install -m 600 "$ENV_SRC" /etc/selenoid/token-validator.env
chown selenoid:selenoid /etc/selenoid/token-validator.env
install -d -m 750 -o www-data -g www-data "$CACHE_DIR" 2>/dev/null \
  || install -d -m 750 "$CACHE_DIR"
install -m 644 "$UNIT_SRC" /etc/systemd/system/selenoid-token-validator.service
systemctl daemon-reload
systemctl enable selenoid-token-validator.service
systemctl restart selenoid-token-validator.service
sleep 1
systemctl --no-pager --full status selenoid-token-validator.service | head -n 20
curl -fsS -o /dev/null -w "health %{http_code}\n" http://127.0.0.1:9082/health
echo "OK: token validator on 127.0.0.1:9082 (hub not restarted)"
