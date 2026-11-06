#!/bin/sh
# Compila el APK de Android (instalable fuera de Google Play) y lo firma con una clave propia.
# Necesita: Godot 4.7 con plantillas de exportacion, JDK 17 y el SDK de Android (cmdline-tools).
# Entorno: GODOT (ruta del ejecutable), ANDROID_SDK_ROOT. Genera Build/Android/BoomerShooter.apk
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
: "${ANDROID_SDK_ROOT:?falta ANDROID_SDK_ROOT}"
VERSION="$(grep -m1 '^config/version=' project.godot | sed 's/.*="\(.*\)"/\1/')"
CODIGO="$(echo "$VERSION" | awk -F. '{ printf "%d", $1*10000 + $2*100 + $3 }')"
echo "Android: version $VERSION (codigo $CODIGO)"

# Clave de firma. Se reutiliza la del secreto si existe (asi las actualizaciones se instalan encima);
# si no, se crea una en el momento (el APK se instala igual, pero no se actualiza sobre otro firmado distinto).
mkdir -p Build/Android
LLAVERO="Build/Android/boomershooter.keystore"
if [ -n "${ANDROID_KEYSTORE_B64:-}" ]; then
  echo "$ANDROID_KEYSTORE_B64" | base64 -d > "$LLAVERO"
  CLAVE="${ANDROID_KEYSTORE_PASSWORD:?falta ANDROID_KEYSTORE_PASSWORD}"
else
  CLAVE="boomershooter-$(date +%Y)"
  rm -f "$LLAVERO"
  keytool -genkeypair -v -keystore "$LLAVERO" -storepass "$CLAVE" -keypass "$CLAVE" \
    -alias boomershooter -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Boomer Shooter, O=Boomer Shooter, C=DO" >/dev/null
fi

# Godot lee el SDK, el JDK y la firma del entorno (no del archivo de presets, que va al repositorio).
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$PWD/$LLAVERO"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="boomershooter"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$CLAVE"
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$PWD/$LLAVERO"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="boomershooter"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="$CLAVE"

# Version del APK segun el proyecto (el preset trae un valor de partida).
sed -i.bak "s|^version/name=.*|version/name=\"$VERSION\"|; s|^version/code=.*|version/code=$CODIGO|" export_presets.cfg
rm -f export_presets.cfg.bak

"$GODOT" --headless --path . --export-release "Android" "Build/Android/BoomerShooter.apk"
test -s Build/Android/BoomerShooter.apk
ls -la Build/Android/BoomerShooter.apk
