#!/usr/bin/env bash
# Fail fast when production guest auth env is missing (no literal fallbacks).
require_public_auth() {
  local missing=()
  [[ -z "${SELENOID_PUBLIC_USER:-}" ]] && missing+=(SELENOID_PUBLIC_USER)
  [[ -z "${SELENOID_PUBLIC_PASSWORD:-}" ]] && missing+=(SELENOID_PUBLIC_PASSWORD)
  if ((${#missing[@]})); then
    echo "Missing required env: ${missing[*]}" >&2
    echo "Configure GitHub Environment selenoid-production:" >&2
    echo "  variable  SELENOID_PUBLIC_USER" >&2
    echo "  secret    SELENOID_PUBLIC_PASSWORD" >&2
    exit 1
  fi
}

public_access_key() {
  printf '%s:%s' "$SELENOID_PUBLIC_USER" "$SELENOID_PUBLIC_PASSWORD"
}

public_access_key_urlenc() {
  local key
  key="$(public_access_key)"
  printf '%s' "${key//:/%3A}"
}

patch_nginx_public_access_keys() {
  local conf_file="$1"
  require_public_auth
  local key encoded_key tmp
  key="$(public_access_key)"
  encoded_key="$(public_access_key_urlenc)"
  if ! grep -q '__SELENOID_PUBLIC_ACCESS_KEY__' "$conf_file"; then
    echo "Missing nginx placeholder __SELENOID_PUBLIC_ACCESS_KEY__ in $conf_file" >&2
    exit 1
  fi
  tmp="${conf_file}.patched"
  awk -v key="$key" -v enc="$encoded_key" '{
    gsub("__SELENOID_PUBLIC_ACCESS_KEY__", key)
    gsub("__SELENOID_PUBLIC_ACCESS_KEY_URLENC__", enc)
    print
  }' "$conf_file" >"$tmp"
  mv "$tmp" "$conf_file"
}
