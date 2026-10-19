#!/bin/bash
# ============================================================
#  setup.sh — First-time local setup
#  Builds & starts all containers, then pulls the tinyllama model
# ============================================================

set -euo pipefail

echo "============================================"
echo "  Qualibytes GPT — First Time Setup"
echo "============================================"

# Docker Compose v2 is required (`docker compose`, not `docker-compose`)
if ! docker compose version > /dev/null 2>&1; then
  echo "ERROR: Docker Compose v2 not found. Install it with:"
  echo "  sudo apt install docker-compose-v2 -y"
  exit 1
fi

# Step 1: Build & start all containers from local source
echo "[1/3] Building and starting all containers..."
docker compose up -d --build

# Step 2: Wait for Ollama to be ready (max ~2 minutes)
echo "[2/3] Waiting for Ollama to be ready..."
for i in $(seq 1 40); do
  if docker exec qualibytes-ollama ollama list > /dev/null 2>&1; then
    echo "  Ollama is ready!"
    break
  fi
  if [ "$i" -eq 40 ]; then
    echo "ERROR: Ollama did not become ready. Check: docker compose logs ollama"
    exit 1
  fi
  echo "  Ollama starting... waiting 3s"
  sleep 3
done

# Step 3: Pull tinyllama (only downloads once — stored in volume)
if docker exec qualibytes-ollama ollama list | grep -q tinyllama; then
  echo "[3/3] tinyllama already downloaded — skipping."
else
  echo "[3/3] Pulling tinyllama model (~637MB)..."
  echo "  This will take a few minutes on first run."
  docker exec qualibytes-ollama ollama pull tinyllama
fi

echo ""
echo "============================================"
echo "  Setup Complete!"
echo "  Open: http://$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo 'YOUR-SERVER-IP')"
echo "============================================"
