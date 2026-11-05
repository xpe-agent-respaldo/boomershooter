#!/bin/sh
# Genera res://online_defaults.cfg con el servidor y la clave publica de Nakama.
# Variables (en GitLab: Settings > CI/CD > Variables, enmascaradas):
#   NAKAMA_HOST        p. ej. boomershooter.onrender.com
#   NAKAMA_SERVER_KEY  clave publica del cliente (la misma que el servidor)
# El archivo esta en .gitignore: nunca se versiona.
set -eu
: "${NAKAMA_HOST:?falta NAKAMA_HOST}"
: "${NAKAMA_SERVER_KEY:?falta NAKAMA_SERVER_KEY}"
OUT="${1:-online_defaults.cfg}"
umask 077
cat > "$OUT" <<EOF
[nakama]
host="${NAKAMA_HOST}"
port=443
scheme="https"
server_key="${NAKAMA_SERVER_KEY}"
EOF
echo "online_defaults.cfg generado ($(wc -c < "$OUT") bytes)"
