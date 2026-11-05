#!/usr/bin/env python3
"""Cada modo tiene su poblacion y todos los bots pisan suelo REAL del mapa (no vacio, no paredes)."""
import os, sys, re, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_match_coop as T

MODS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "modules")
SUELO = open(os.path.join(MODS, "map_floor.lua"), encoding="utf-8").read()

def celdas(mapa):
    bloque = SUELO.split(f"M.{mapa} = {{")[1].split("\n}")[0]
    return {(int(a), int(b)) for a, b in re.findall(r"\{(-?\d+),(-?\d+),-?[\d.]+\}", bloque)}

def alturas(mapa):
    """Altura MEDIDA del suelo por celda (los escalones son reales: el bot debe pisarlos, no flotar sobre ellos)."""
    bloque = SUELO.split(f"M.{mapa} = {{")[1].split("\n}")[0]
    return {(int(a), int(b)): float(y) for a, b, y in re.findall(r"\{(-?\d+),(-?\d+),(-?[\d.]+)\}", bloque)}

ESPERADO = {  # companeros, pandilleros, solitarios, amigos
    "coop_waves":  (3, 3, 1, 1),
    "survival":    (0, 0, 1, 0),
    "horde":       (4, 0, 0, 0),
    "boss_rush":   (2, 0, 0, 0),
    "freestylers": (6, 0, 0, 0),
}
fallos = 0
def check(nombre, ok, det=""):
    global fallos
    print(("  ok   " if ok else "  FALLA ") + nombre + ("" if ok else f"  [{det}]"))
    if not ok: fallos += 1

for mapa in ("recycling_plant", "storm_village", "space_arena"):
    suelo = celdas(mapa); ALT = alturas(mapa)
    print(f"\n[{mapa}: {len(suelo)} celdas de suelo]")
    for modo, (comp, pand, solo, ami) in ESPERADO.items():
        h = T.Harness()
        a = h.presence("u1", "Ana")
        h.M_map = mapa
        st = h.M.match_init(h.lua.table(), h.lua.table(mode=modo, map=mapa))[0]
        h.state = st
        h.join(a)
        h.tick(2)
        est = h.py(h.state)
        cuenta = {"bot": 0, "pandilla": 0, "solo": 0, "amigo": 0}
        for p in est["players"].values():
            if not p.get("bot"): continue
            lado = p.get("side")
            cuenta["bot" if lado in (None, "entrenado") else lado] += 1
        check(f"{modo}: companeros={comp} pandilla={pand} solitarios={solo} amigos={ami}",
              (cuenta["bot"], cuenta["pandilla"], cuenta["solo"], cuenta["amigo"]) == (comp, pand, solo, ami), str(cuenta))
        # 60 s simulados: ningun bot sale de las celdas medidas ni sube de y=0.5
        fuera = 0; altos = 0; total = 0
        for t in range(3, 3 + 600):
            h.tick(t)
            if t % 20 == 0:
                for p in h.py(h.state)["players"].values():
                    if not p.get("bot"): continue
                    total += 1
                    x, z = p["pos"]["x"], p["pos"]["z"]
                    cx, cz = round(x / 2) * 2, round(z / 2) * 2
                    # tolerancia: la celda mas cercana (medio paso) debe existir
                    if not any((cx + dx, cz + dz) in suelo for dx in (-2, 0, 2) for dz in (-2, 0, 2)): fuera += 1
                    # la Y debe ser la del suelo medido bajo el bot (+-15 cm): ni flota ni se hunde
                    c0 = (math.floor(x / 2 + 0.5) * 2, math.floor(z / 2 + 0.5) * 2)
                    if c0 in ALT and abs(p["pos"]["y"] - ALT[c0]) > 0.15: altos += 1
        check(f"{modo}: {total} muestras de bots, 0 fuera del mapa, 0 en el aire", fuera == 0 and altos == 0, f"fuera={fuera} altos={altos}")
print(f"\n{'TODO OK' if not fallos else str(fallos) + ' FALLOS'}")
sys.exit(1 if fallos else 0)
