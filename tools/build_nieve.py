#!/usr/bin/env python3
"""Genera el cuarto mapa: CAMPOS DE NIEVE (referencia: 3_frozen_snow_fields.png).

Se genera APARTE de build_arenas.py a proposito: ese script reescribe los otros tres mapas y
el espacial lleva retoques a mano. Reutiliza sus piezas (escaleras, rampas, casa enterable).

Puntos estrategicos (a proposito, no cajas sueltas):
  - REFUGIO central enterable, dos puertas opuestas, desvan con escalera y azotea.
  - TORRE DE VIGIA al norte, con escalera: mejor vista, pero expuesta desde el lago.
  - LAGO HELADO al sur: plano abierto sin cobertura. Cruzarlo es una decision de riesgo.
  - MUROS DE HIELO en diagonal: cobertura para rotar entre refugio, torre y cabana.
  - CABANAS esquineras enterables, y PINOS / ROCAS como obstaculos que cortan la linea de vision.
Reglas de verticalidad del motor: escalon <= 0.45 m, cornisa <= 1.2 m (ver build_arenas.py).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_arenas as B

LEVELS = B.LEVELS


def build_nieve():
    sc = B.Scene("SnowFields")
    snow = sc.material("snow", (0.86, 0.92, 0.97), 0.95)
    snow_d = sc.material("snowDark", (0.62, 0.72, 0.82), 0.95)
    ice = sc.material("ice", (0.55, 0.78, 0.92), 0.12, 0.15)
    rock = sc.material("rockSnow", (0.34, 0.37, 0.43), 1.0)
    wood = sc.material("woodCold", (0.30, 0.20, 0.14), 0.9)
    roof = sc.material("roofSnow", (0.92, 0.95, 0.98), 0.9)
    pine = sc.material("pine", (0.07, 0.22, 0.16), 0.95)
    warm = sc.material("warmLight", (0.20, 0.12, 0.04), 0.5, emission=(1.0, 0.72, 0.30), emit_energy=2.0)

    H = 34  # medio lado del campo (el resto de mapas rondan 28 a 36)
    sc.box("Ground", (0, -0.5, 0), (H * 2 + 8, 1, H * 2 + 8), snow)

    # lago helado al sur: plano y abierto, nada tapa la vista
    sc.box("FrozenLake", (0, 0.02, 20), (30, 0.12, 20), ice)

    # colinas bajas de nieve alrededor (relieve suave, saltables como cornisa < 1.2 m)
    for i, (x, z, r) in enumerate([(-24, -14, 4.0), (25, -10, 4.4), (-27, 6, 3.4), (27, 12, 3.6), (-12, -27, 3.8), (14, -26, 3.6)]):
        sc.sphere(f"Drift{i}", (x, 0.2, z), r, snow_d, squash=0.30)

    # murallas del campo: cordillera de rocas nevadas (silueta de la referencia)
    random.seed(7)
    for i in range(30):
        a = i / 30 * math.tau
        # Cuadrado, no circulo: el campo es de lado 2H, asi que en las esquinas un radio H se metia
        # DENTRO de la zona jugable (spawns encima de rocas). Se proyecta al borde del cuadrado + margen.
        k = 1.0 / max(abs(math.cos(a)), abs(math.sin(a)))
        r = (H + 5.5 + random.random() * 2.0) * k
        x, z = round(math.cos(a) * r, 2), round(math.sin(a) * r, 2)
        h = random.randint(7, 17)
        w = random.randint(4, 8)
        sc.box(f"Ridge{i}", (x, h / 2, z), (w, h, w), rock if i % 3 else snow_d, rot_y=random.randint(0, 90))
        sc.box(f"RidgeCap{i}", (x, h + 1.2, z), (w * 0.6, 2.4, w * 0.6), roof, rot_y=random.randint(0, 90))
    B.perimeter(sc, H + 1, 5, rock, thick=2.5)

    # REFUGIO central: dos puertas opuestas (+z y -z), desvan con escalera, azotea transitable
    B.enterable_house(sc, "Refugio", 0, -4, 12, 10, 4.4, wood, roof, wood, door_side="+z", with_loft=True, stair_mat=wood)
    sc.box("RefugioPuertaTrasera", (0, 1.2, -9.05), (2.4, 2.4, 0.5), warm, collide=False)
    sc.light("RefugioCalido", (0, 2.6, -4), (1.0, 0.72, 0.4), 2.2, 14)

    # TORRE DE VIGIA al norte: patas, plataforma a 4.2 m con barandilla, escalera
    for i, (dx, dz) in enumerate([(-1.6, -1.6), (1.6, -1.6), (-1.6, 1.6), (1.6, 1.6)]):
        sc.box(f"TorrePata{i}", (-4 + dx, 2.1, -24 + dz), (0.5, 4.2, 0.5), wood)
    sc.box("TorrePlataforma", (-4, 4.35, -24), (4.4, 0.3, 4.4), wood)
    for tag, (px, pz, sx, sz) in {"N": (-4, -26.1, 4.4, 0.25), "S": (-4, -21.9, 4.4, 0.25),
                                  "E": (-1.9, -24, 0.25, 4.4), "W": (-6.1, -24, 0.25, 4.4)}.items():
        sc.box(f"TorreBarandilla{tag}", (px, 4.5 + 0.55, pz), (sx, 1.1, sz), wood)
    B.stairs(sc, "TorreEscalera", -4, -21.0, 4.2, direction="-z", width=2.4, run=0.9, mat=wood)

    # CABANAS esquineras enterables (sin desvan): refugio rapido en cada flanco
    B.enterable_house(sc, "CabanaO", -23, 20, 7, 6, 3.4, wood, roof, wood, door_side="+x", with_loft=False)
    B.enterable_house(sc, "CabanaE", 23, 20, 7, 6, 3.4, wood, roof, wood, door_side="-x", with_loft=False)

    # MUROS DE HIELO: cobertura en diagonal para rotar sin cruzar el lago
    for i, (x, z, giro) in enumerate([(-13, 4, 35), (13, 4, -35), (-9, -12, -30), (9, -12, 30), (0, 9, 0)]):
        sc.box(f"MuroHielo{i}", (x, 1.3, z), (6.0, 2.6, 0.9), ice, rot_y=giro)

    SPAWNS = [(-28, 1, -6), (28, 1, -6), (-17, 1, 30), (17, 1, 30), (6, 1, -29), (-28, 1, 8)]

    def libre_de_spawn(x, z, radio=5.0):
        return all(math.hypot(x - sx, z - sz) > radio for sx, _, sz in SPAWNS)

    # PINOS: obstaculos que cortan la linea de vision (tronco + dos copas)
    random.seed(52)
    puestos = []
    while len(puestos) < 22:
        x, z = random.uniform(-30, 30), random.uniform(-30, 30)
        if abs(x) < 9 and -10 < z < 4:        # no dentro del refugio
            continue
        if -16 < x < -1 and -28 < z < -19:    # no sobre la torre
            continue
        if abs(x) < 16 and 9 < z < 30:        # no sobre el lago
            continue
        if abs(x) > 19 and z > 15:            # no dentro de las cabanas
            continue
        if not libre_de_spawn(x, z):          # ni un pino sobre donde aparece un jugador
            continue
        if any(math.hypot(x - a, z - b) < 5 for a, b in puestos):
            continue
        puestos.append((round(x, 1), round(z, 1)))
    for i, (x, z) in enumerate(puestos):
        s = random.uniform(0.9, 1.3)
        sc.cyl(f"PinoTronco{i}", (x, 1.2, z), 0.28 * s, 2.4, wood, sides=8)
        sc.cyl(f"PinoCopaA{i}", (x, 3.2 * s, z), 1.5 * s, 2.6 * s, pine, sides=8)
        sc.cyl(f"PinoCopaB{i}", (x, 4.9 * s, z), 0.95 * s, 2.2 * s, pine, sides=8)

    # rocas nevadas sueltas
    random.seed(88)
    for i in range(8):
        x, z = random.uniform(-26, 26), random.uniform(-26, 6)
        if (abs(x) < 9 and -10 < z < 4) or not libre_de_spawn(x, z):
            continue
        sc.sphere(f"Roca{i}", (round(x, 1), 0.7, round(z, 1)), random.uniform(1.1, 2.0), rock, squash=0.7)

    sc.light("Aurora", (0, 12, 0), (0.6, 0.85, 1.0), 1.4, 40)
    sc.sign("NieveSign", (0, 9, 26), "CAMPOS DE NIEVE", (0.8, 0.92, 1.0), 64)

    # cielo blanco azulado, niebla densa y fria (la referencia es casi toda bruma)
    env = B.make_env("Snow", (0.55, 0.70, 0.86), (0.86, 0.93, 0.98), (0.80, 0.88, 0.94),
                     (0.84, 0.91, 0.97), 0.014, ambient=(0.70, 0.80, 0.92), ambient_energy=1.05)
    sun = {"transform": B.sun_transform(-48, 30), "color": (0.92, 0.96, 1.0), "energy": 1.1}
    spawns = SPAWNS
    return B.render_scene(sc, env, sun, spawns, script_path="res://Scripts/snow_fields.gd")


if __name__ == "__main__":
    text = build_nieve()
    with open(os.path.join(LEVELS, "SnowFields.tscn"), "w") as f:
        f.write(text)
    print(f"SnowFields.tscn: {len(text)//1024} KB, {text.count('[node')} nodos")
