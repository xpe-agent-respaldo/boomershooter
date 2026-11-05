# Cierre del cooperativo online

## Fase 1: vertical slice jugable

- Identidad por dispositivo, matchmaking y conexión Nakama: integrado.
- Mapas, oleadas, élite de cada tercera ronda, armas y HUD: integrado en Arena.
- Prueba LAN y presencia de dos clientes: integrada.

## Fase 2: autoridad Nakama (requisito de lanzamiento)

1. Crear un módulo runtime de Nakama que cree y mantenga el match de 1 a 4 jugadores.
2. El servidor genera las cuatro zonas de aparición, nunca dentro del refugio del equipo.
3. El servidor valida disparos, daño, muerte, pickups, temporizador, élite y estadísticas finales.
4. Implementar estado de caída y reanimación con tiempo fijo y cancelación al recibir daño.
5. Replicar al cliente solo el estado necesario, con interpolación y límites de frecuencia.
6. Añadir reconexión, abandono, host migration cuando aplique y registros de error.

## Fase 3: rendimiento y publicación

- Perfilado con Godot Profiler en una máquina objetivo; 120 FPS es una meta, no una garantía en cualquier hardware.
- Sustituir CSGBox3D de prototipo por mallas estáticas con colisión combinada antes de mapas grandes.
- Generar LODs, occlusion culling y presupuesto de luces/sombras por mapa.
- Probar cuatro clientes, latencia simulada y oleada élite antes de activar descargas públicas.
