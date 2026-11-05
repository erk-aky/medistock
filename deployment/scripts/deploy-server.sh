#!/usr/bin/env bash
# Backend imajını sunucuda derleyip konteyneri yeniler ve ayağa kalktığını doğrular.
set -euo pipefail

cd "$(dirname "$0")/../config"

if [ ! -f .env.production ]; then
  echo "❌ Missing config/.env.production"; exit 1
fi

COMPOSE="docker compose -f docker-compose.production.yml --env-file .env.production"
API_PORT=$(grep -E '^API_PORT=' .env.production | cut -d= -f2 | tr -d '[:space:]' || true)
API_PORT=${API_PORT:-5289}

echo "🔨 Building image..."
$COMPOSE build api

echo "🚀 Starting container..."
$COMPOSE up -d --remove-orphans api

echo "⏳ Waiting for API on port $API_PORT..."
for attempt in $(seq 1 30); do
  if curl -fsS "http://localhost:${API_PORT}/" >/dev/null 2>&1; then
    echo "✅ API is up (attempt $attempt)"
    docker image prune -f >/dev/null
    exit 0
  fi
  sleep 2
done

echo "❌ API did not respond"
$COMPOSE logs --tail 50 api
exit 1
