#!/bin/sh
# Genera la IPA de Boomer Shooter para iPhone/iPad.
#
# SOLO funciona en macOS con Xcode: Godot usa xcodebuild y la firma de Apple, y eso
# no existe en Linux ni en Windows. Este script se puede lanzar a mano o desde el
# trabajo manual build_ios de GitLab (runner macOS).
#
# Variables que hacen falta:
#   GODOT_BIN                 ruta al binario de Godot 4.7 (por defecto "godot")
#   APPLE_TEAM_ID             Team ID de 10 caracteres de tu cuenta Apple Developer
#   IOS_BUNDLE_ID             bundle id (por defecto com.xpe.nettt.boomershooter)
#   IOS_SIGN_IDENTITY         "iPhone Distribution: Tu Nombre (TEAMID)"
#   IOS_PROFILE_APPSTORE      UUID del provisioning profile de App Store
#   IOS_PROFILE_ADHOC         UUID del profile ad-hoc (para probar sin App Store)
#   IOS_EXPORT_METHOD         0 = App Store, 1 = ad-hoc (por defecto 1)
#
# Lo que NO se puede hacer desde aqui: crear la cuenta de Apple Developer, el
# certificado ni el provisioning profile. Eso se hace en developer.apple.com y en
# Xcode con tu cuenta.

set -e

raiz=$(cd "$(dirname "$0")/.." && pwd)
cd "$raiz"

GODOT_BIN="${GODOT_BIN:-godot}"
VERSION=$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot | head -1)
echo "[ios] version $VERSION"

if [ "$(uname -s)" != "Darwin" ]; then
  cat <<'AVISO'
[ios] Este equipo no es macOS: no se puede generar la IPA.
      Godot exporta iOS con xcodebuild y firma Apple, que solo existen en un Mac.
      Lo que si puedes hacer hoy:
        * jugar desde el iPhone en el navegador con la version web del juego,
        * compilar en Linux/Windows los ejecutables de escritorio (ya funciona),
        * lanzar este mismo script en un Mac (o en un runner macOS de GitLab).
      Pasos completos en docs/IOS.md.
AVISO
  exit 0
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "[ios] Falta Xcode. Instalalo desde el App Store y ejecuta: sudo xcodebuild -license accept"
  exit 1
fi

plantillas="$HOME/Library/Application Support/Godot/export_templates"
if ! ls "$plantillas" 2>/dev/null | grep -q "4.7"; then
  echo "[ios] Faltan los export templates de Godot 4.7 (Editor > Manage Export Templates)."
  exit 1
fi

if [ -z "${APPLE_TEAM_ID:-}" ]; then
  echo "[ios] Falta APPLE_TEAM_ID (10 caracteres, en developer.apple.com > Membership)."
  exit 1
fi

# El preset se ajusta con los datos del entorno para no guardar credenciales en el repo.
bundle="${IOS_BUNDLE_ID:-com.xpe.nettt.boomershooter}"
identidad="${IOS_SIGN_IDENTITY:-iPhone Distribution}"
metodo="${IOS_EXPORT_METHOD:-1}"
profile="${IOS_PROFILE_ADHOC:-}"
if [ "$metodo" = "0" ]; then
  profile="${IOS_PROFILE_APPSTORE:-}"
fi

python3 - "$APPLE_TEAM_ID" "$bundle" "$identidad" "$metodo" "$profile" "$VERSION" <<'PY'
import sys
team, bundle, identidad, metodo, profile, version = sys.argv[1:7]
ruta = "export_presets.cfg"
texto = open(ruta, encoding="utf-8").read()
inicio = texto.index('[preset.4.options]')
final = texto.find('\n[preset.', inicio + 1)
if final == -1:
    final = len(texto)
bloque = texto[inicio:final]
cambios = {
    'application/app_store_team_id': team,
    'application/bundle_identifier': bundle,
    'application/short_version': version,
    'application/export_method_release': metodo,
    'application/provisioning_profile_uuid_release': profile,
    'application/code_sign_identity_release': identidad,
}
for clave, valor in cambios.items():
    lineas = bloque.split('\n')
    for i, linea in enumerate(lineas):
        if linea.startswith(clave + '='):
            comillas = linea.split('=', 1)[1].startswith('"')
            lineas[i] = f'{clave}="{valor}"' if comillas or clave.startswith('application/bundle')
            lineas[i] = f'{clave}="{valor}"' if comillas else f'{clave}={valor}'
            break
    bloque = '\n'.join(lineas)
open(ruta, 'w', encoding="utf-8").write(texto[:inicio] + bloque + texto[final:])
print(f"[ios] preset ajustado: team={team} bundle={bundle} metodo={metodo}")
PY

mkdir -p Build/iOS
"$GODOT_BIN" --headless --path . --editor --quit
"$GODOT_BIN" --headless --path . --export-release "iOS" "Build/iOS/BoomerShooter.ipa"

if [ -f Build/iOS/BoomerShooter.ipa ]; then
  echo "[ios] IPA lista: $raiz/Build/iOS/BoomerShooter.ipa"
  ls -la Build/iOS/
else
  echo "[ios] Godot no genero la IPA. Revisa la cuenta Apple, el certificado y el profile."
  exit 1
fi
