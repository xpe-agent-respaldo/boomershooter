# BOOMER SHOOTER

FPS arcade de alta movilidad creado por **Stealth Proyects**. Corre, apunta, deslízate, rota y resiste. Las arenas premian tomar riesgos, no quedarse en una esquina.

Copyright © 2026 Stealth Proyects. Todos los derechos reservados.

## Contenido actual

- Menú principal: **Online**, **Arena** y **Ajustes**.
- **Arena** es el modo local. Incluye selector de Planta de Reciclaje, Distrito de Tormenta y Puesto Lunar.
- **Online** no muestra IP, puertos ni datos de infraestructura al jugador. Un nombre de combate y el botón **Iniciar partida** bastan para entrar a la cola.
- Oleadas con cuenta atrás, aviso visual, dificultad creciente, amenaza élite cada tercera ronda, rutas expuestas y reutilización de pickups.
- Armas actuales: bláster, SMG, escopeta, lanzacohetes y francotirador. Los sonidos disponibles están organizados bajo `Assets/Sounds`.
- Música de lobby aleatoria; la música se detiene al abandonar el lobby.
- Teclado, mouse, Xbox, PlayStation y mandos genéricos mediante el mapeo de Godot.
- Controles configurables: volumen, sensibilidad, pantalla completa exclusiva, resolución, límite de FPS, posición del contador, perfil de rendimiento, auto-sprint, doble toque para correr y reasignación de teclas/botones.
- Perfil Bajo diseñado para equipos de 4 GB: escala 3D reducida, sombras desactivadas y límite de enemigos concurrentes menor.
- Contador de FPS permanente, configurable en las cuatro esquinas.
- Actualización obligatoria: el manifiesto de la web puede bloquear la entrada online y mostrar notas de la versión nueva.
- Chat de partida en pantalla: tecla **Enter** para abrirlo. Su transporte entre jugadores se activa junto con el módulo autoritativo de Nakama.

## Controles predeterminados

| Acción | Teclado / mouse | Mando |
| --- | --- | --- |
| Mover | WASD | Stick izquierdo |
| Mirar | Mouse | Stick derecho |
| Disparar / apuntar | Click izq. / der. | RT / LT |
| Saltar | Espacio | A / Cruz |
| Correr | Shift o doble toque W | Stick izquierdo pulsado |
| Agacharse | C o Ctrl | B / Círculo |
| Deslizarse | C mientras corres | B / Círculo mientras corres |
| Recargar | R | X / Cuadrado |
| Armas | 1, 2, 3, 4 | D-pad |
| Chat | Enter | Pendiente de asignación de mando |

Cada acción de juego se puede reasignar desde **Ajustes → Cambiar teclas y botones**.

## Enemigos

| Amenaza | Comportamiento | Aparición |
| --- | --- | --- |
| Acechador | Persigue al jugador, fuerza movimiento y emite un aviso al acercarse. | Oleadas iniciales |
| Reptil Élite | Variante más resistente preparada para romper posiciones fijas. | Cada tercera oleada |
| Amenazas futuras | Diseños de la carpeta de nuevos monstruos: cada uno debe tener modelo 3D, colisiones, audio, daño y presupuesto de rendimiento antes de añadirse. | Próximas actualizaciones |

## Online: estado real

Nakama está integrado para identidad por dispositivo, conexión y cola de matchmaking. Consulta [ONLINE_TEST.md](ONLINE_TEST.md) para validar dos clientes sin compartir direcciones técnicas.

El servidor aún necesita un módulo de runtime autoritativo para decidir spawn, daño, muertes, revivir, recompensas, oleadas y resultado. Sin ello el cooperativo no debe anunciarse como lanzamiento público terminado. El plan técnico está en [docs/ONLINE_ROADMAP.md](docs/ONLINE_ROADMAP.md).

No se requieren nuevas tablas de Supabase para la prueba de Nakama. Las tablas de perfiles, estadísticas o analíticas se incorporan cuando el modo tenga autoridad de servidor.

## Voz y plataformas

El chat de voz de proximidad requiere consentimiento de micrófono, moderación y un transporte de voz (por ejemplo, WebRTC con SFU o un proveedor de voz). No está habilitado todavía porque Nakama no transmite audio por sí solo.

Una IPA no se puede compilar ni firmar desde Windows: el export de iOS necesita macOS, Xcode, una cuenta de Apple Developer, Team ID y un bundle ID único. No se ha creado una IPA falsa.

## Compilación y distribución

GitLab CI/CD exporta Windows y Linux. El Release adjunta `BoomerShooter.exe` directamente y una copia empaquetada. El PCK queda integrado en el ejecutable de Windows.

El enlace de la página `/api/download/windows` funcionará al existir un Release publicado que contenga exactamente el archivo `BoomerShooter.exe`. Si devuelve 404, la compilación o la publicación del release aún no ha terminado correctamente.

## Créditos de recursos

Los recursos de terceros conservan sus atribuciones y términos originales. Antes de una publicación comercial, verifica que cada recurso tenga licencia compatible con ese uso.


## Licencia

El codigo es MIT (ver [LICENSE](LICENSE)). Los recursos de `Assets/` conservan la licencia
de su autor: ver [CREDITS.md](CREDITS.md). Los secretos (clave del servidor online,
Supabase, certificados) nunca van en el repositorio: ver [SECURITY.md](SECURITY.md).
