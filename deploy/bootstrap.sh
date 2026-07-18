#!/usr/bin/env bash
# One-time server bootstrap for selenoid.qa.guru.
# Run with sudo on a fresh Ubuntu host with Docker installed.
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-selenoid}"
CONFIG_DIR="${SELENOID_CONFIG_DIR:-/opt/selenoid}"
CM_BIN="/home/${DEPLOY_USER}/cm"

if [[ "$DEPLOY_USER" == "root" ]]; then
  echo "DEPLOY_USER must not be root (default: selenoid)" >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo ./deploy/bootstrap.sh" >&2
  exit 1
fi

if ! id "$DEPLOY_USER" &>/dev/null; then
  echo "=== create user $DEPLOY_USER ==="
  useradd -m -s /bin/bash "$DEPLOY_USER"
fi

echo "=== docker group for $DEPLOY_USER ==="
usermod -aG docker "$DEPLOY_USER"

echo "=== config dir $CONFIG_DIR ==="
mkdir -p "$CONFIG_DIR"/{video,logs,bin}
chown -R "$DEPLOY_USER:docker" "$CONFIG_DIR"
chmod 775 "$CONFIG_DIR" "$CONFIG_DIR"/video "$CONFIG_DIR"/logs "$CONFIG_DIR"/bin

echo "=== cm binary at $CM_BIN ==="
sudo -u "$DEPLOY_USER" bash -c "
  curl -fsSL https://github.com/qa-guru/cm/releases/latest/download/cm_linux_amd64 -o '$CM_BIN'
  chmod +x '$CM_BIN'
"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/browsers-production.json" && ! -f "$CONFIG_DIR/browsers.json" ]]; then
  echo "=== install browsers.json from browsers-production.json ==="
  cp "$SCRIPT_DIR/browsers-production.json" "$CONFIG_DIR/browsers.json"
  chown "$DEPLOY_USER:docker" "$CONFIG_DIR/browsers.json"
  chmod 664 "$CONFIG_DIR/browsers.json"
fi

echo "=== docker network selenoid (if missing) ==="
docker network inspect selenoid >/dev/null 2>&1 || docker network create selenoid

echo "=== passwordless sudo for nginx deploy ==="
SUDOERS="/etc/sudoers.d/${DEPLOY_USER}-selenoid-nginx"
cat >"$SUDOERS" <<EOF
${DEPLOY_USER} ALL=(ALL) NOPASSWD: SETENV: /opt/selenoid/bin/sync-nginx.sh
${DEPLOY_USER} ALL=(ALL) NOPASSWD: SETENV: /tmp/sync-nginx.sh
EOF
chmod 440 "$SUDOERS"
visudo -cf "$SUDOERS"

echo "=== passwordless sudo for systemd-managed hub ==="
HUB_SUDOERS="/etc/sudoers.d/${DEPLOY_USER}-selenoid-hub"
cat >"$HUB_SUDOERS" <<EOF
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/install -m 644 /tmp/selenoid-hub.service /etc/systemd/system/selenoid-hub.service
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl daemon-reload
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl enable selenoid-hub.service
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl disable selenoid-hub.service
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl start selenoid-hub.service
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop selenoid-hub.service
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart selenoid-hub.service
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl status selenoid-hub.service
EOF
chmod 440 "$HUB_SUDOERS"
visudo -cf "$HUB_SUDOERS"

if [[ -f "$SCRIPT_DIR/selenoid-hub.service" ]]; then
  echo "=== install + enable systemd unit selenoid-hub.service (autostart on reboot) ==="
  install -m 644 "$SCRIPT_DIR/selenoid-hub.service" /etc/systemd/system/selenoid-hub.service
  systemctl daemon-reload
  systemctl enable selenoid-hub.service
fi

echo "Bootstrap complete."
echo "  user:   $DEPLOY_USER"
echo "  cm:     $CM_BIN"
echo "  config: $CONFIG_DIR"
echo "Next (as $DEPLOY_USER, new login shell for docker group):"
echo "  ./deploy/deploy.sh"
