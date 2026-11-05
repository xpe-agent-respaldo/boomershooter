#!/usr/bin/env python3
"""Los bots PISAN el suelo: ni flotan, ni se hunden, ni salen del mapa. Compara la Y y la celda de cada bot,
tick a tick, con el plano MEDIDO del juego (map_floor.lua) en los 3 mapas y todos los modos."""
import os, sys, re, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_match_coop as T

# El plano medido, leido directo del .lua (la fuente de verdad que usa el servidor)
SRC = open(os.path.join(os.path.dirname(__file__), "..", "modules", "map_floor.lua"), encoding="utf-8").read()
PLANO = {}
for mapa in ("recycling_plant", "storm_village", "space_arena"):
    bloque = SRC.split("M." + mapa + " = {")[1].split("\n}")[0]
    PLANO[mapa] = {(int(x), int(z)): float(y) for x, z, y in re.findall(r"\{(-?\d+),(-?\d+),(-?[\d.]+)\}", bloque)}

fallos = 0
def check(n, ok, det=""):
    global fallos
    print(("  ok   " if ok else "  FALLA ") + n + ("" if ok else f"  [{det}]"))
    if not ok: fallos += 1

def celda(v): return (int(math.floor(v / 2.0 + 0.5)) * 2, int(math.floor(v / 2.0 + 0.5)) * 2)

def barrido_semillas(mapa, modo, semillas, ticks=900):
    """Regresion del Matadero: varias semillas, un solo dueno por bot. Cuenta muestras malas."""
    malas = 0; total = 0
    plano = PLANO[mapa]
    for seed in semillas:
        h = T.Harness()
        h.lua.execute("math.randomseed(%d)" % seed)
        a = h.presence("u1", "Ana")
        h.state = h.M.match_init(h.lua.table(), h.lua.table(mode=modo, map=mapa))[0]
        h.join(a); h.tick(2)
        for t in range(3, ticks):
            h.clock += 0.1; h.tick(t)
            for p in h.py(h.state)["players"].values():
                if not p.get("bot"): continue
                x, y, z = p["pos"]["x"], p["pos"]["y"], p["pos"]["z"]
                c = (int(math.floor(x / 2.0 + 0.5)) * 2, int(math.floor(z / 2.0 + 0.5)) * 2)
                total += 1
                if c not in plano or abs(y - plano[c]) > 0.15: malas += 1
    return total, malas

def medir(mapa, modo, ticks=1800):
    h = T.Harness()
    a = h.presence("u1", "Ana")
    h.state = h.M.match_init(h.lua.table(), h.lua.table(mode=modo, map=mapa))[0]
    h.join(a); h.tick(2)
    plano = PLANO[mapa]
    muestras = 0; fuera = 0; flota = 0; hunde = 0; peor = 0.0; ejemplo = None; ys = set()
    for t in range(3, ticks):
        h.clock += 0.1; h.tick(t)
        for p in h.py(h.state)["players"].values():
            if not p.get("bot"): continue
            x, y, z = p["pos"]["x"], p["pos"]["y"], p["pos"]["z"]
            cx = int(math.floor(x / 2.0 + 0.5)) * 2; cz = int(math.floor(z / 2.0 + 0.5)) * 2
            muestras += 1; ys.add(round(y, 1))
            if (cx, cz) not in plano:
                fuera += 1; ejemplo = ejemplo or (round(x,1), round(z,1)); continue
            d = y - plano[(cx, cz)]
            peor = max(peor, abs(d))
            if d > 0.15: flota += 1
            elif d < -0.15: hunde += 1
    return muestras, fuera, flota, hunde, peor, ejemplo, ys

total_esc = 0; con_altura = 0
for mapa in ("recycling_plant", "storm_village", "space_arena"):
    print(f"\n[{mapa}] celdas medidas: {len(PLANO[mapa])}, con escalon (>15 cm): {sum(1 for v in PLANO[mapa].values() if abs(v) > 0.15)}")
    for modo in ("coop_waves", "survival", "horde", "boss_rush", "freestylers"):
        m, fu, fl, hu, peor, ej, ys = medir(mapa, modo)
        check(f"{modo}: {m} muestras, 0 fuera del mapa", m > 0 and fu == 0, f"fuera={fu} ej={ej}")
        check(f"{modo}: 0 flotando y 0 hundidos (peor desvio {peor:.2f} m)", fl == 0 and hu == 0, f"flota={fl} hunde={hu}")
        if any(abs(y) > 0.15 for y in ys): con_altura += 1
print("\n[regresion Matadero: 20 semillas, semillas 4, 7 y 8 reproducian el fallo]")
for mapa in ("recycling_plant", "storm_village", "space_arena"):
    tot, malas = barrido_semillas(mapa, "freestylers", range(1, 21))
    check(f"{mapa} freestylers x20 semillas: {tot} muestras, 0 fuera de suelo", malas == 0, f"malas={malas}")
print(f"\nEscenarios donde algun bot pisa un escalon real: {con_altura}")
check("los bots SI llegan a pisar escalones (el test ejercita la altura, no solo suelo plano)", con_altura > 0)
print("\nTODO OK" if fallos == 0 else f"\n{fallos} FALLOS"); sys.exit(1 if fallos else 0)
