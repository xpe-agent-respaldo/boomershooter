#!/bin/sh
# Genera una IPA SIN FIRMAR de Boomer Shooter (para instalar con Sideloadly,
# AltStore, Scarlet... que la firman con la cuenta Apple del jugador).
#
# Necesita macOS con Xcode (en GitHub Actions: runner macos-14, ya trae Xcode).
# Uso:  APPLE_TEAM_ID=XXXXXXXXXX sh tools/build_ios_unsigned.sh
#       (el team id puede ser cualquiera: sin firma no se usa)
set -eu

AQUI=$(cd "$(dirname "$0")/.." && pwd)
cd "$AQUI"

GODOT=${GODOT:-Godot}
VERSION=$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot | head -1)
VERSION=${VERSION:-0.0.0}
TEAM=${APPLE_TEAM_ID:-ABCDE12345}

echo "[ios] version $VERSION | equipo $TEAM"

# El preset exige un Team ID no vacio para exportar; con firma desactivada luego no se usa.
python3 - "$TEAM" "$VERSION" <<'PY'
import re, sys
team, version = sys.argv[1], sys.argv[2]
ruta = "export_presets.cfg"
s = open(ruta, encoding="utf-8").read()
s = re.sub(r'application/app_store_team_id="[^"]*"', f'application/app_store_team_id="{team}"', s)
s = re.sub(r'application/short_version="[^"]*"', f'application/short_version="{version}"', s)
open(ruta, "w", encoding="utf-8").write(s)
print(f"preset iOS: equipo {team}, version {version}")
PY

find Build/iOS -mindepth 1 -delete 2>/dev/null || true
mkdir -p Build/iOS

echo "[ios] importando el proyecto..."
"$GODOT" --headless --path . --editor --quit >/dev/null 2>&1 || true

echo "[ios] exportando el proyecto Xcode..."
: > Build/iOS/export.log
"$GODOT" --headless --path . --export-release "iOS" "Build/iOS/BoomerShooter.ipa" >>Build/iOS/export.log 2>&1 || true
tail -20 Build/iOS/export.log

PROYECTO=$(find Build/iOS -maxdepth 2 -name "*.xcodeproj" | head -1)
if [ -z "$PROYECTO" ]; then
  echo "[ios] ERROR: Godot no genero el proyecto Xcode. Revisa que exista la plantilla ios.zip"
  echo "      en ~/Library/Application Support/Godot/export_templates/ y el preset iOS."
  echo "[ios] --- ultimas lineas del export ---"
  tail -40 Build/iOS/export.log 2>/dev/null || true
  ls -la Build/iOS || true
  exit 1
fi

ESQUEMA=$(basename "$PROYECTO" .xcodeproj)
echo "[ios] compilando $ESQUEMA sin firma..."
xcodebuild -project "$PROYECTO" -scheme "$ESQUEMA" -configuration Release -sdk iphoneos \
  -derivedDataPath Build/iOS/dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build | tail -15

APP=$(find Build/iOS/dd/Build/Products/Release-iphoneos -maxdepth 1 -name "*.app" | head -1)
if [ -z "$APP" ]; then
  echo "[ios] ERROR: xcodebuild no dejo ninguna .app"
  exit 1
fi

find Build/iOS/Payload -mindepth 1 -delete 2>/dev/null || true
mkdir -p Build/iOS/Payload
cp -R "$APP" Build/iOS/Payload/
IPA="BoomerShooter-$VERSION-unsigned.ipa"
find Build/iOS -maxdepth 1 -name "*.ipa" -delete 2>/dev/null || true
( cd Build/iOS && zip -qr "$IPA" Payload )

echo "[ios] listo: Build/iOS/$IPA"
ls -la "Build/iOS/$IPA"
