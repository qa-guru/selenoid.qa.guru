#!/usr/bin/env bash
# Bootstrap ollama + open-webui on GL10-1-T4 dedicated GPU host (24/7).
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run on GPU host as root" >&2
  exit 1
fi

curl -fsSL https://ollama.com/install.sh | sh
systemctl enable ollama
systemctl start ollama

docker run -d --restart unless-stopped --gpus all \
  -v ollama:/root/.ollama \
  -p 11434:11434 \
  --name ollama \
  ollama/ollama

docker run -d --restart unless-stopped \
  -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
  -p 8088:8080 \
  --name open-webui \
  ghcr.io/open-webui/open-webui:main

echo "ollama :11434, open-webui :8088 — point ml.qa.guru A record to this host"
