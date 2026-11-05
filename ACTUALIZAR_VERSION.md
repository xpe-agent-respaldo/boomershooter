# Publicar una actualizacion

1. Antes de ejecutar `sync_project.cmd`, cambia solo el campo `version` de `site/update.json`. Ejemplo: `1.0.0` a `1.0.1`.
2. Ejecuta `sync_project.cmd` con doble clic desde el Explorador de Windows.
3. Espera a que finalice el flujo de compilacion. El lanzamiento incluira el `.exe` directo y los paquetes de Windows y Linux.

El juego compara la version incluida en el ejecutable con `https://boomer-shooter.vercel.app/update.json`. Cuando publiques una version mayor, las instalaciones anteriores mostraran el aviso de actualizacion al abrir el juego.

No guardes contrasenas de Supabase, tokens de GitLab ni secretos en el proyecto.
