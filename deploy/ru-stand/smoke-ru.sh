#!/usr/bin/env bash
# Smoke RU stand — hub status + optional remote e2e tag.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
STATE="$REPO_ROOT/docs/hetzner-infra-audit/selectel-ru-stand/state.json"
BASE_URL="${SELENOID_RU_URL:-https://selenoid.qa.guru}"

if [[ "${1:-}" == "--local-hub" ]]; then
  HUB_IP="${HUB_IP:-}"
  [[ -z "$HUB_IP" && -f "$STATE" ]] && HUB_IP="$(python -c "import json; print(json.load(open('$STATE')).get('hub',{}).get('ip',''))")"
  BASE_URL="http://${HUB_IP}:4444"
fi

echo "=== GET $BASE_URL/wd/hub/status ==="
code="$(curl -sS -o /tmp/selenoid-ru-status.json -w '%{http_code}' -u user1:1234 "$BASE_URL/wd/hub/status" --max-time 30 || echo 000)"
cat /tmp/selenoid-ru-status.json | head -c 500
echo
echo "HTTP $code"
[[ "$code" == "200" ]] || exit 1

echo "=== warm/min catalog check ==="
python -c "
import json
b=json.load(open('$REPO_ROOT/projects/services-home/selenoid-qa-guru-home/selenoid-qa-guru/deploy/ru-stand/browsers-ru-warm.json'))
assert 'chrome' in b and 'firefox' in b
for name, sec in b.items():
    assert any(k.endswith('-min') or '.0-min' in k for k in sec['versions']), name
print('warm/min catalog OK')
"

if [[ -d "$REPO_ROOT/projects/selenoid-home/selenoid-tests" ]]; then
  echo "=== optional e2e smoke (remote) ==="
  (cd "$REPO_ROOT/projects/selenoid-home/selenoid-tests" && \
    ./gradlew test -Dremote.url="$BASE_URL/wd/hub" -Dgroups=smoke --no-daemon -q) || \
    echo "e2e smoke skipped or failed (hub may need DNS first)"
fi

echo "Smoke OK"
