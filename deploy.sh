#!/bin/bash
# ============================================================
#  deploy.sh — Runs ON THE APP SERVER (called by Jenkins / GitLab CI)
#
#  Required env:
#    DOCKER_USERNAME   Docker Hub username (images: $DOCKER_USERNAME/qualibytes-*)
#  Optional env:
#    IMAGE_TAG         Image tag to deploy (default: latest)
#
#  The Docker Hub password is read from STDIN (never from argv/env),
#  only needed if the images are private:
#    echo "$PASSWORD" | DOCKER_USERNAME=me ./deploy.sh
# ============================================================

set -euo pipefail

: "${DOCKER_USERNAME:?DOCKER_USERNAME must be set}"
export DOCKER_USERNAME
export IMAGE_TAG="${IMAGE_TAG:-latest}"

cd "$(dirname "$0")"

# Log in only if a password was piped in
if [ ! -t 0 ]; then
  PASSWORD="$(cat)"
  if [ -n "$PASSWORD" ]; then
    printf '%s' "$PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
    trap 'docker logout > /dev/null 2>&1 || true' EXIT
  fi
fi

echo "=== Pulling images (tag: $IMAGE_TAG) ==="
docker compose pull

echo "=== Starting all services ==="
# No --no-deps: on a fresh server this also starts Ollama
docker compose up -d --remove-orphans

echo "=== Waiting for Ollama ==="
for i in $(seq 1 40); do
  docker exec qualibytes-ollama ollama list > /dev/null 2>&1 && break
  if [ "$i" -eq 40 ]; then
    echo "Ollama did not become ready"
    docker compose logs --tail 50 ollama
    exit 1
  fi
  sleep 3
done

if ! docker exec qualibytes-ollama ollama list | grep -q tinyllama; then
  echo "=== Pulling tinyllama model (first deploy only) ==="
  docker exec qualibytes-ollama ollama pull tinyllama
fi

docker image prune -f > /dev/null
docker compose ps
