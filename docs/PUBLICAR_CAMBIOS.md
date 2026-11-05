# Publicar cambios locales

1. Cierra Godot antes de publicar para que no cambie archivos mientras Git los revisa.
2. Haz doble clic en `sync_project.cmd` desde el Explorador de Windows. No lo ejecutes desde Git Bash.
3. El script detecta archivos nuevos, modificados, renombrados y eliminados; no vuelve a subir lo que no ha cambiado.
4. `sync_project.cmd`, las carpetas `Build/` y el ZIP de recursos están excluidos por `.gitignore`.

El script no borra cambios remotos ni fuerza la subida. Si GitLab pide autenticación, inicia sesión en Git Credential Manager y ejecuta el archivo de nuevo.
