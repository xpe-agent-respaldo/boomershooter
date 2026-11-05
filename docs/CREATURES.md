# Bestiario de Boomer Shooter

## Acechador

La amenaza base. Persigue, presiona rutas cortas y castiga al jugador que se queda inmóvil. Su audio de proximidad sirve como advertencia: si se escucha, hay que rotar o preparar un choke point.

## Reptil Élite

Se introduce cada tercera oleada. Es la primera señal de que la partida no permite una defensa permanente: tiene más resistencia y debe forzar al equipo a usar rutas, explosivos y posiciones alternativas.

## Regla de integración para nuevos monstruos

Una imagen o sprite no basta para añadir un enemigo a una arena 3D. Cada criatura necesita:

1. Modelo o representación 3D, colisión y escala coherentes.
2. Máquina de estados: patrulla, persecución, ataque, aturdimiento y muerte.
3. Daño, salud, velocidad y sonido con presupuesto por oleada.
4. Spawn validado por el servidor cuando el cooperativo sea autoritativo.
5. Prueba de rendimiento en perfil Bajo antes de aparecer en partidas públicas.

## Larva Veloz (Wormbeak)

Variante ligera y rapida del Acechador: menos vida por golpe recibido, pero llega antes y pega mas fuerte. Se mezcla en las oleadas desde la ronda 2 (uno de cada tres apariciones) para romper el ritmo de quien solo mira al frente.

Implementada como escena heredada de `Scenes/Enemies/Beetle/Beetle.tscn` con estadisticas propias (`health 3`, `damage 14`, `speed 470`, escala 0.82): reutiliza modelo, esqueleto, colisiones y maquina de estados, sin coste extra de assets.
