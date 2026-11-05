# Sistema multijugador

## Objetivo del primer modo

**Online → Cooperativo** será una defensa de 1 a 4 jugadores. El equipo resiste rondas de enemigos en la Planta de Reciclaje sin economía, compras ni ventajas de pago.

## Diseño de partida

| Elemento | Diseño |
| --- | --- |
| Inicio | Cuenta atrás breve y aviso audiovisual. |
| Escalada | Aumentan cantidad, velocidad y variedad en cada ronda. |
| Élite | Una amenaza élite cada tercera ronda. |
| Mapa | Patio expuesto, pasarela alta de dos accesos, compactadoras, túneles y cuatro zonas de aparición alejadas del refugio. |
| Pickups | En rutas expuestas: el equipo debe salir de una posición cómoda para obtenerlos. |
| Caída | Revivir exige permanecer junto al compañero durante unos segundos; recibir daño o alejarse cancela la acción. |
| Fin | Cuando no queda ningún jugador en pie, el servidor guarda el resultado y el cliente muestra las estadísticas. |

## Arquitectura objetivo

```text
Cliente Godot
  └─ Nakama SDK: identidad, socket y matchmaking
      └─ Match de Nakama: autoridad de oleadas, daño, revivir y resultado
          └─ PostgreSQL/Supabase: datos persistentes de perfil y partidas
```

## Estado actual del repositorio

- SDK oficial de Nakama registrado como Autoload global `Nakama`.
- `OnlineManager` autentica por dispositivo, abre socket y busca una sala de 2 a 4 jugadores.
- La prueba LAN permite verificar dos clientes en la misma red.
- La escena reproduce presencia, movimiento y plataforma de entrada del otro cliente.
- El sistema de oleadas de Arena funciona localmente.

## Requisito pendiente antes de abrir el modo público

Falta el módulo de runtime de Nakama que ejecute la partida en el servidor. Hasta que exista, el cliente no debe considerarse una fuente confiable para daño, enemigos, reanimación, premios ni estadísticas.

El plan de implementación está en [docs/ONLINE_ROADMAP.md](docs/ONLINE_ROADMAP.md) y la prueba de dos clientes está en [ONLINE_TEST.md](ONLINE_TEST.md).
