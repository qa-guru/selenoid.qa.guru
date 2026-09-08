#!/usr/bin/env bash
# Apply nginx-selenoid.conf on the server (requires sudo).
# Preserves ssl_certificate* lines from the existing site config when present.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_LIB="${SCRIPT_DIR}/lib/require-public-auth.sh"
if [[ ! -f "$AUTH_LIB" ]]; then
  AUTH_LIB="${SCRIPT_DIR}/../lib/require-public-auth.sh"
fi
# shellcheck source=lib/require-public-auth.sh
source "$AUTH_LIB"
CONF_SRC="${NGINX_CONF_SRC:-${SCRIPT_DIR}/nginx-selenoid.conf}"
SITE_NAME="${NGINX_SITE_NAME:-selenoid}"
SITE_PATH="/etc/nginx/sites-available/${SITE_NAME}"
TMP="/tmp/nginx-selenoid.generated"
SSL_SNIPPET="/tmp/nginx-selenoid.ssl-snippet"

if [[ ! -f "$CONF_SRC" ]]; then
  echo "Missing $CONF_SRC (set NGINX_CONF_SRC or place nginx-selenoid.conf next to this script)" >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  if sudo -n true 2>/dev/null; then
    exec sudo env NGINX_CONF_SRC="$CONF_SRC" NGINX_SITE_NAME="$SITE_NAME" "$0" "$@"
  fi
  echo "Run as root or with passwordless sudo: sudo $0" >&2
  exit 1
fi

require_public_auth

HTPASSWD="/etc/nginx/selenoid.htpasswd"
# WebDriver Basic Auth: students (user1) + public guest (SELENOID_PUBLIC_* from env).
STUDENT_USER="${SELENOID_STUDENT_USER:-user1}"
STUDENT_PASSWORD="${SELENOID_STUDENT_PASSWORD:-1234}"
PUBLIC_USER="$SELENOID_PUBLIC_USER"
PUBLIC_PASSWORD="$SELENOID_PUBLIC_PASSWORD"
# Optional account for one CI consumer, so a pipeline never carries the public guest
# credential that is published to students and can be revoked on its own.
CI_USER="${SELENOID_CI_USER:-}"
CI_PASSWORD="${SELENOID_CI_PASSWORD:-}"

htpasswd_set() {
  local user="$1" password="$2"
  if command -v htpasswd >/dev/null 2>&1; then
    if [[ -f "$HTPASSWD" ]]; then
      htpasswd -b "$HTPASSWD" "$user" "$password"
    else
      htpasswd -cb "$HTPASSWD" "$user" "$password"
    fi
  elif command -v openssl >/dev/null 2>&1; then
    local hash
    hash="$(openssl passwd -apr1 "$password")"
    touch "$HTPASSWD"
    sed -i "\|^${user}:|d" "$HTPASSWD"
    printf '%s:%s\n' "$user" "$hash" >>"$HTPASSWD"
  else
    echo "Missing $HTPASSWD and neither htpasswd nor openssl is available" >&2
    exit 1
  fi
}

htpasswd_set "$STUDENT_USER" "$STUDENT_PASSWORD"
htpasswd_set "$PUBLIC_USER" "$PUBLIC_PASSWORD"
if [[ -n "$CI_USER" && -n "$CI_PASSWORD" ]]; then
  htpasswd_set "$CI_USER" "$CI_PASSWORD"
fi
chmod 640 "$HTPASSWD"
chown root:www-data "$HTPASSWD" 2>/dev/null || chmod 644 "$HTPASSWD"

cp "$CONF_SRC" "$TMP"
patch_nginx_public_access_keys "$TMP"

: >"$SSL_SNIPPET"
if [[ -f "$SITE_PATH" ]]; then
  grep -E '^\s*ssl_certificate(_key)? ' "$SITE_PATH" | awk '!seen[$0]++' >>"$SSL_SNIPPET" || true
fi
if [[ ! -s "$SSL_SNIPPET" ]]; then
  for domain in selenoid.qa.guru autotests.cloud api.autotests.cloud; do
    if [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
      {
        echo "    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;"
        echo "    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;"
      } >>"$SSL_SNIPPET"
      break
    fi
  done
fi
if [[ -s "$SSL_SNIPPET" ]]; then
  awk -v sslfile="$SSL_SNIPPET" '
    /# ssl_certificate \.\.\.;/ {
      while ((getline line < sslfile) > 0) print line
      close(sslfile)
      next
    }
    { print }
  ' "$TMP" >"${TMP}.patched"
  mv "${TMP}.patched" "$TMP"
else
  echo "WARN: no ssl_certificate lines found; HTTPS will not work until certs are configured" >&2
fi

if command -v certbot >/dev/null 2>&1; then
  certbot renew --quiet 2>/dev/null || true
fi

cp "$TMP" "$SITE_PATH"
ln -sf "$SITE_PATH" "/etc/nginx/sites-enabled/${SITE_NAME}"
nginx -t
systemctl reload nginx
echo "OK: nginx reloaded ($SITE_PATH)"
