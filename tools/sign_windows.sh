#!/bin/sh
# Firma el .exe con Authenticode si hay certificado; si no, avisa y sigue.
# Variables (GitLab > Settings > CI/CD > Variables, enmascaradas):
#   SIGN_CERT_PFX_BASE64  certificado .pfx codificado en base64
#   SIGN_CERT_PASSWORD    contrasena del .pfx
# Sin firma, Windows SmartScreen mostrara "Windows protegio su PC".
set -eu
EXE="${1:?uso: sign_windows.sh archivo.exe}"
if [ -z "${SIGN_CERT_PFX_BASE64:-}" ] || [ -z "${SIGN_CERT_PASSWORD:-}" ]; then
  echo "AVISO: sin certificado de firma; el .exe NO esta firmado (SmartScreen avisara)."
  exit 0
fi
umask 077
PFX="$(mktemp)"
trap 'rm -f "$PFX" "$EXE.signed"' EXIT
printf '%s' "$SIGN_CERT_PFX_BASE64" | base64 -d > "$PFX"
osslsigncode sign -pkcs12 "$PFX" -pass "$SIGN_CERT_PASSWORD" \
  -n "Boomer Shooter" -i "https://boomershooter.vercel.app" \
  -h sha256 -t http://timestamp.digicert.com \
  -in "$EXE" -out "$EXE.signed"
mv "$EXE.signed" "$EXE"
osslsigncode verify -in "$EXE" >/dev/null 2>&1 && echo "Firma aplicada y verificada." || { echo "ERROR: la firma no verifica"; exit 1; }
