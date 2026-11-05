#!/bin/sh
set -eu
: "${DATABASE_URL:?DATABASE_URL is required}"
: "${NAKAMA_SERVER_KEY:?NAKAMA_SERVER_KEY is required}"
: "${PORT:=7350}"
: "${NAKAMA_CONSOLE_USERNAME:=admin}"
: "${NAKAMA_CONSOLE_PASSWORD:?NAKAMA_CONSOLE_PASSWORD is required}"
/nakama/nakama migrate up --database.address "$DATABASE_URL"
exec /nakama/nakama \
  --database.address "$DATABASE_URL" \
  --socket.server_key "$NAKAMA_SERVER_KEY" \
  --socket.port "$PORT" \
  --console.username "$NAKAMA_CONSOLE_USERNAME" \
  --console.password "$NAKAMA_CONSOLE_PASSWORD" \
  --runtime.path /nakama/data/modules \
  --logger.level INFO
