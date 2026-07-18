#!/usr/bin/env bash
# Deploy Selenoid 3 to RU hub from laptop. Reads IP from state.json or HUB_IP.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
STATE="$REPO_ROOT/docs/hetzner-infra-audit/selectel-ru-stand/state.json"
DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RU_DIR="$(dirname "${BASH_SOURCE[0]}")"

HUB_IP="${HUB_IP:-}"
if [[ -z "$HUB_IP" && -f "$STATE" ]]; then
  HUB_IP="$(python -c "import json; print(json.load(open('$STATE')).get('hub',{}).get('ip',''))")"
fi
if [[ -z "$HUB_IP" ]]; then
  echo "Set HUB_IP or provision hub first (selectel_audit.py provision-hub)" >&2
  exit 1
fi

SSH_KEY="${SSH_KEY:-$HOME/.ssh/qa_guru_prod_ed25519}"
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new ubuntu@$HUB_IP"
SCP="scp -i $SSH_KEY -o StrictHostKeyChecking=accept-new"

python "$RU_DIR/build-browsers-warm.py"

echo "=== bootstrap host (docker + nginx) ==="
$SCP "$RU_DIR/bootstrap-host.sh" "ubuntu@${HUB_IP}:/tmp/bootstrap-host.sh"
$SSH "sudo bash /tmp/bootstrap-host.sh"

echo "=== selenoid user + cm bootstrap ==="
$SCP "$DEPLOY_DIR/bootstrap.sh" "ubuntu@${HUB_IP}:/tmp/bootstrap.sh"
$SCP "$RU_DIR/browsers-ru-warm.json" "ubuntu@${HUB_IP}:/tmp/browsers-production.json"
$SSH "sudo DEPLOY_USER=selenoid bash /tmp/bootstrap.sh"

echo "=== deploy stack ==="
$SCP "$DEPLOY_DIR/deploy.sh" "$DEPLOY_DIR/selenoid-hub.service" "selenoid@${HUB_IP}:/tmp/"
$SSH "sudo cp /tmp/browsers-production.json /opt/selenoid/browsers.json && sudo chown selenoid:docker /opt/selenoid/browsers.json"
$SSH "cp /tmp/deploy.sh /tmp/selenoid-hub.service ~selenoid/ && sudo -u selenoid bash -lc 'cd ~selenoid && ./deploy.sh'"

echo "=== nginx + TLS ==="
$SCP "$RU_DIR/nginx-selenoid-qa-guru.conf" "ubuntu@${HUB_IP}:/tmp/selenoid.qa.guru.conf"
$SSH "sudo htpasswd -cb /etc/nginx/selenoid.htpasswd user1 1234 && sudo chmod 640 /etc/nginx/selenoid.htpasswd"
$SSH "sudo install -m 644 /tmp/selenoid.qa.guru.conf /etc/nginx/sites-available/selenoid.qa.guru"
$SSH "sudo ln -sf /etc/nginx/sites-available/selenoid.qa.guru /etc/nginx/sites-enabled/"
$SSH "sudo mkdir -p /var/www/certbot && sudo nginx -t && sudo systemctl reload nginx"
$SSH "sudo certbot --nginx -d selenoid.qa.guru --non-interactive --agree-tos -m qa.guru.team@gmail.com || true"

echo "Deploy complete. Hub IP=$HUB_IP"
echo "Next: python scripts/infra-dns/dns_audit.py cutover-selenoid-qa-guru"
