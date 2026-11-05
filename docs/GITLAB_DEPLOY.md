# GitLab, Vercel y builds oficiales

> Seguridad y estadisticas: el pipeline valida el proyecto, descarga las export
> templates de Godot 4.7 de forma reproducible y escanea secretos. Mantén GitLab
> Pages desactivado: Vercel es la web oficial y una Pages pública duplicaría el
> sitio. Para estadísticas privadas usa **Build > Pipelines**, **Analyze > CI/CD
> analytics** y los reportes de artefactos de GitLab.

## 1. GitLab CI/CD

El archivo `.gitlab-ci.yml` crea artefactos de Windows y Linux en cada push a `main`. Para crear un Release, crea y sube una etiqueta, por ejemplo `v1.0.3`. La tarea `release_desktop` enlaza los archivos del pipeline a ese Release.

El proyecto debe tener Git LFS activado si se suben modelos o audios grandes.

## 2. Vercel

Conecta el proyecto de Vercel al repositorio de GitLab y selecciona `site` como directorio de salida si esa es la configuración actual del sitio. Vercel desplegará cada push a `main`.

Configura estas variables en **Vercel → Project Settings → Environment Variables** cuando haya una ubicación pública para los instaladores:

- `WINDOWS_DOWNLOAD_URL`: URL HTTPS pública del `BoomerShooter.exe`.
- `LINUX_DOWNLOAD_URL`: URL HTTPS pública del paquete Linux.

Las rutas `/api/download/windows` y `/api/download/linux` redirigen a esas variables. Si todavía no están definidas, responderán que la descarga se publicará pronto, en vez de un 404 o un enlace a otro proveedor.

Un repositorio privado de GitLab no puede servir instaladores públicos sin autenticación. Para descargas públicas manteniendo el código privado, usa almacenamiento público independiente o un proyecto de distribución separado que sólo contenga los binarios, nunca el código fuente.

## 3. Render + Nakama

Render sólo necesita estas variables, configuradas como secretos:

- `DATABASE_URL`
- `NAKAMA_SERVER_KEY`
- `NAKAMA_CONSOLE_USERNAME`
- `NAKAMA_CONSOLE_PASSWORD`

No añadas `NAKAMA_HOST`, `NAKAMA_PORT` ni `NAKAMA_CONSOLE_PORT` al servicio actual: el script usa el `PORT` que asigna Render para el socket público y mantiene la consola fuera de la interfaz de jugadores. No uses el valor por defecto de la clave de servidor ni credenciales de consola en producción.

## 4. IPA desde GitLab

`build_ios_ipa` es manual y sólo corre con una etiqueta en un runner macOS etiquetado `macos`, Xcode, Godot y export templates instalados. Configura estas variables **masked y protected** en GitLab CI/CD:

- `GODOT_BIN` (ruta al ejecutable de Godot en el Mac)
- `IOS_CERTIFICATE_BASE64`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE_BASE64`
- `IOS_KEYCHAIN_PASSWORD`

No subas certificados ni provisioning profiles como artifacts ni los imprimas en logs. Antes de ejecutar la tarea debes crear el preset `iOS` desde Godot en el Mac, con Team ID, bundle identifier y perfil de aprovisionamiento válidos.

La distribución directa OTA sólo es posible con una IPA firmada y una URL HTTPS pública de la IPA/manifiesto. Para App Store, TestFlight o Ad Hoc se aplican las reglas de Apple y los dispositivos registrados.
