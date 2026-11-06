#!/bin/sh
# Genera el parche de contenido de iPhone (content.pck) de la version actual.
#
# iOS no puede reemplazar la app, pero si montar un .pck desde user://. El parche contiene solo
# lo que cambio respecto a la IPA BASE (la instalada en el movil). Como siempre se calcula contra
# la misma base, sirve desde cualquier version intermedia (1.3.0 -> 1.3.5 directo).
#
# Uso: GODOT=... sh tools/build_ios_patch.sh <base.pck> <salida.pck>
set -eu
AQUI=$(cd "$(dirname "$0")/.." && pwd)
cd "$AQUI"
BASE=${1:?falta la base (.pck de la IPA instalada)}
SALIDA=${2:?falta el archivo de salida}
GODOT=${GODOT:-godot}

test -f "$BASE" || { echo "[parche] ERROR: no existe la base $BASE"; exit 1; }
rm -f "$SALIDA"
"$GODOT" --headless --path . --export-patch "iOS" "$SALIDA" --patches "$BASE" >/tmp/parche_ios.log 2>&1 || true
if [ ! -s "$SALIDA" ]; then
  echo "[parche] ERROR: Godot no genero el parche"; grep -E "ERROR" /tmp/parche_ios.log | head -5; exit 1
fi
echo "[parche] $(wc -c < "$SALIDA") bytes -> $SALIDA"
