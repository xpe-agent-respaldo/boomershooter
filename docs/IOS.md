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


## Firmar la IPA (herramientas open source y de la comunidad)

La IPA que sale de GitHub va **sin firmar** y validada (`tools/validar_ipa.py`: estructura
`Payload/*.app`, Info.plist, ejecutable arm64, permiso de microfono). Cada jugador la firma
con lo que prefiera:

| Herramienta | Donde corre | Licencia | Notas |
|---|---|---|---|
| **zsign** (zhlynn/zsign) | Linux, Windows, macOS | MIT | Linea de comandos. Es la que usa el workflow para comprobar que la IPA se puede firmar. `zsign -k cert.p12 -p CLAVE -m perfil.mobileprovision -o BoomerShooter.ipa original.ipa` |
| **SideStore** (SideStore/SideStore) | iPhone | AGPLv3 | Firma con el Apple ID del jugador y renueva cada 7 dias sin PC. |
| **AltStore** (altstoreio/AltStore) | iPhone + PC | AGPLv3 | Igual, necesita AltServer en un ordenador. |
| **cyan / pyzule-rw** (asdfzxcvbn/pyzule-rw) | Linux, macOS, WSL | sin licencia declarada | Modifica la IPA (nombre, bundle id, icono) y la "fakesigna" para TrollStore. |
| **Gbox / ESign / Feather / Filza** | iPhone | cerradas o mixtas | Las que ya usan tus jugadores: aceptan esta IPA tal cual. |

### Comprobar una IPA a mano

```bash
python3 tools/validar_ipa.py BoomerShooter-1.2.9-unsigned.ipa
```

### Pantalla y controles en iPhone

* Solo horizontal (izquierda o derecha); nunca vertical.
* Los botones respetan la muesca / Dynamic Island y la barra de inicio.
* Si se conecta un mando, los botones tactiles se esconden solos.
* Micrófono: el sistema pide permiso la primera vez que se entra a una partida con voz.
