# Voz, móvil e iOS

## Voz de proximidad

Nakama se usa para identidad, presencia y matchmaking; no es un servicio de audio en tiempo real. Para hablar entre jugadores se necesita una capa adicional que haga tres cosas:

1. Pedir permiso explícito de micrófono y permitir silenciar, volumen individual, bloqueo y reporte.
2. Enviar audio cifrado mediante WebRTC y mezclarlo por distancia en el cliente.
3. Usar un SFU/servidor de voz o un proveedor compatible para que el audio no dependa del PC de un jugador.

No se activa el micrófono automáticamente ni se simula una función de voz que no tiene transporte. El chat de texto ya está presentado en el cliente; su réplica entre jugadores se conecta al módulo de partida autoritativo.

## iOS

La exportación de iOS no se puede compilar ni firmar desde Windows. Antes de crear la IPA hacen falta un Mac con Xcode, export templates de Godot, una cuenta Apple Developer, Team ID, Bundle ID único y certificados/profiles válidos. Cuando exista ese entorno, se crea el preset iOS, se agregan los permisos de micrófono solo si la voz ya está lista y se compila desde macOS.

El juego conserva base de controles táctiles para la futura versión móvil, pero Windows/Linux son las plataformas de la primera prueba online.
