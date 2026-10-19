#!/bin/bash
# ============================================================
#  healthcheck.sh — Runs ON THE APP SERVER after a deploy
#  Checks backend, model availability, the frontend proxy,
#  and one real chat round-trip.
# ============================================================

set -euo pipefail

echo "--- Backend /health"
curl -fsS --retry 10 --retry-delay 3 --retry-all-errors http://localhost:5000/health
echo

echo "--- tinyllama present in Ollama"
docker exec qualibytes-ollama ollama list | grep -q tinyllama
echo "OK"

echo "--- Frontend on port 80"
curl -fsS -o /dev/null -w "HTTP %{http_code}\n" http://localhost/

echo "--- Chat smoke test through Nginx (can take ~60s on first call)"
curl -fsS --max-time 120 -X POST http://localhost/api/chat \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Say hello in one word."}]}' \
  | grep -q '"reply"'
echo "OK"

echo "=== All checks passed: HEALTHY ==="
