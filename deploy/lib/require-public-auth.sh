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
  python -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$(public_access_key)"
}

patch_nginx_public_access_keys() {
  local conf_file="$1"
  require_public_auth
  local key encoded_key
  key="$(public_access_key)"
  encoded_key="$(public_access_key_urlenc)"
  python - "$conf_file" "$key" "$encoded_key" <<'PY'
import sys

path, key, encoded = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
replacements = {
    "__SELENOID_PUBLIC_ACCESS_KEY__": key,
    "__SELENOID_PUBLIC_ACCESS_KEY_URLENC__": encoded,
}
for placeholder, value in replacements.items():
    if placeholder not in text:
        print(f"Missing nginx placeholder {placeholder} in {path}", file=sys.stderr)
        sys.exit(1)
    text = text.replace(placeholder, value)
open(path, "w", encoding="utf-8").write(text)
PY
}
