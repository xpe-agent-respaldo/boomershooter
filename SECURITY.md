# Seguridad de Boomer Shooter

No subas contraseñas, tokens, claves privadas, archivos `.env`, certificados de
iOS ni perfiles de aprovisionamiento al repositorio. Las credenciales de
Render, Nakama, Supabase y GitLab se guardan exclusivamente como variables
protegidas y enmascaradas del proveedor correspondiente.

Si una credencial llega a un commit, historial, captura o conversación, se debe
revocar y regenerar de inmediato. Después actualiza el secreto en el servicio
correspondiente y vuelve a desplegar. No basta con eliminar el texto del archivo.

El pipeline ejecuta un escaneo de secretos sobre los archivos de cada pipeline.
Un resultado bloqueante se corrige antes de publicar una Release.
