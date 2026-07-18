#!/usr/bin/env bash
# Co-locate GHA runner stub + tms-automator env + niffler-stage pointers on RU hub.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
STATE="$REPO_ROOT/docs/hetzner-infra-audit/selectel-ru-stand/state.json"
HUB_IP="${HUB_IP:-}"
[[ -z "$HUB_IP" && -f "$STATE" ]] && HUB_IP="$(python -c "import json; print(json.load(open('$STATE')).get('hub',{}).get('ip',''))")"
[[ -n "$HUB_IP" ]] || { echo "HUB_IP required" >&2; exit 1; }

SSH_KEY="${SSH_KEY:-$HOME/.ssh/qa_guru_prod_ed25519}"
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new ubuntu@$HUB_IP"

$SSH "sudo mkdir -p /opt/ru-stand/{tms-automator,niffler-stage,actions-runner} && sudo chown -R selenoid:docker /opt/ru-stand"

$SSH "cat > /opt/ru-stand/tms-automator.env <<EOF
SELENOID_HUB_URL=https://selenoid.qa.guru/wd/hub
SELENOID_USER=user1
SELENOID_PASSWORD=1234
EOF
sudo chown selenoid:docker /opt/ru-stand/tms-automator.env"

$SSH "cat > /opt/ru-stand/README-colocated.txt <<'EOF'
Co-located stacks (greenfield):
- Selenoid hub: /opt/selenoid
- tms-automator env: /opt/ru-stand/tms-automator.env
- GHA runner: install to /opt/ru-stand/actions-runner (manual token)
- Niffler stage: rsync from metal /opt/selenoid/niffler/stage when ready
- Jenkins optional: reuse jenkins-qa-guru deploy on port 8082
EOF"

echo "Colocated layout ready on $HUB_IP — see /opt/ru-stand/README-colocated.txt"
echo "Import tms-automator: CLONE=1 $REPO_ROOT/scripts/migrate/autotests-ai-tms-automator-rsync.sh"
