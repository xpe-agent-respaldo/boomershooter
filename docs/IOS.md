# Jugar en iPhone / iPad

Hay dos caminos y **ninguno necesita un Mac en tu casa**: GitHub presta runners macOS
con Xcode ya instalados y son gratis para repositorios públicos (y con minutos de
sobra para uno privado).

## 1. Lo más rápido: jugar ahora en Safari

`https://boomershooter.vercel.app/play`

Es la misma versión web (controles en pantalla y detección de mando funcionando). En
Safari: Compartir → "Añadir a pantalla de inicio" y se abre a pantalla completa.

## 2. La app de verdad: IPA construida en GitHub

El repositorio ya trae el flujo listo:

- `.github/workflows/ios-ipa.yml` — compila en `macos-14` (Xcode incluido), exporta el
  proyecto iOS de Godot, compila sin firma y deja la IPA como *artifact*.
- `tools/build_ios_unsigned.sh` — el mismo proceso en un script, por si lo lanzas a
  mano en un Mac o en otro sitio.

### Pasos (una sola vez)

1. Crea un repositorio en GitHub y sube este proyecto (espejo del de GitLab).
2. Entra en **Actions → IPA de Boomer Shooter → Run workflow**.
3. Cuando acabe (unos 10-15 minutos), descarga el artifact
   `BoomerShooter-ipa-sin-firmar`.
4. Instálala con **Sideloadly** o **AltStore** usando tu cuenta Apple: es gratis, la
   app queda firmada 7 días y se renueva volviendo a firmar.

Con la etiqueta `v*` el flujo también se lanza solo: cada versión publicada deja su IPA.

### Qué es "sin firmar" y qué no

| Uso | Qué hace falta |
|---|---|
| Probar en tu iPhone | IPA sin firmar + Sideloadly/AltStore con tu Apple ID (gratis, 7 días) |
| TestFlight / App Store | Cuenta Apple Developer de pago, certificado y perfil; luego se firma con `xcodebuild` |

Si algún día tienes cuenta de pago, añade el secreto `APPLE_TEAM_ID` en GitHub y se
puede cambiar el flujo para firmar en vez de compilar sin firma.

### Si el flujo se queja

El script dice exactamente qué falta. Los dos fallos típicos:

- **"no generó el proyecto Xcode"**: falta la plantilla `ios.zip` en
  `~/Library/Application Support/Godot/export_templates/4.7.stable/`.
- **`xcodebuild` no encuentra el esquema**: abre `Build/iOS/BoomerShooter.xcodeproj` y
  mira el nombre del esquema; el script coge el nombre del proyecto automáticamente.

## Mando y controles táctiles

- **Mando**: cualquier mando Bluetooth (Xbox, DualSense, 8BitDo…) funciona sin
  configurar nada; se detecta al conectarlo y aparece el aviso en pantalla.
- **Táctil**: joystick a la izquierda, disparo/salto/agacharse a la derecha, y
  arrastrar en la mitad derecha para apuntar.
