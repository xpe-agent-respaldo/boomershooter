#!/usr/bin/env python3
"""Quita del plano de suelo del mapa espacial las celdas ocupadas por los MUROS del escondite.

El plano se midio con rayos al suelo: un obstaculo solido no tiene celda. El escondite (cabina en
(-18,-32), ver tools/anadir_escondite_espacial.py) se anadio despues, asi que sus muros siguen
figurando como suelo caminable: los bots entrarian por la pared y verian a traves de ella.

Se quitan las celdas cuyo CENTRO queda dentro de un muro (con 0.35 m de holgura por el cuerpo del
bot). El interior y la puerta se quedan: se puede entrar, pero no atravesar la pared.
Idempotente. Uso:  python3 infra/nakama/tools/escondite_plano.py [--check]
"""
import os, re, sys
AQUI = os.path.dirname(os.path.abspath(__file__))
PLANO = os.path.join(AQUI, "..", "modules", "map_floor.lua")
CX, CZ, L, G, PUERTA = -18.0, -32.0, 8.0, 0.5, 2.0
HOLGURA = 0.35
m = L / 2
# rectángulos (x0, x1, z0, z1) de los muros, en el plano
MUROS = [
    (CX - m, CX + m, CZ - m, CZ - m + G),                       # norte
    (CX - m, CX - m + G, CZ - m, CZ + m),                       # oeste
    (CX + m - G, CX + m, CZ - m, CZ + m),                       # este
    (CX - m, CX - PUERTA / 2, CZ + m - G, CZ + m),              # sur, tramo izquierdo
    (CX + PUERTA / 2, CX + m, CZ + m - G, CZ + m),              # sur, tramo derecho
    (CX - 2.4 - 0.7, CX - 2.4 + 0.7, CZ - 2.6 - 0.5, CZ - 2.6 + 0.5),  # caja de municion
]

def dentro(x, z):
    return any(x0 - HOLGURA <= x <= x1 + HOLGURA and z0 - HOLGURA <= z <= z1 + HOLGURA for x0, x1, z0, z1 in MUROS)

def main():
    src = open(PLANO, encoding="utf-8").read()
    ini = src.index("M.space_arena = {")
    fin = src.index("\n}", ini)
    bloque = src[ini:fin]
    celdas = re.findall(r"\{(-?\d+),(-?\d+),(-?[\d.]+)\}", bloque)
    quitar = [(x, z, y) for x, z, y in celdas if dentro(int(x), int(z))]
    print(f"celdas del mapa espacial: {len(celdas)}; bajo los muros del escondite: {len(quitar)}")
    for x, z, y in quitar:
        print(f"   quitar ({x},{z})")
    if "--check" in sys.argv:
        sys.exit(1 if quitar else 0)
    if not quitar:
        return
    nuevo = bloque
    for x, z, y in quitar:
        nuevo = nuevo.replace("{%s,%s,%s}," % (x, z, y), "", 1)
        nuevo = nuevo.replace("{%s,%s,%s}" % (x, z, y), "", 1)
    nuevo = nuevo.replace("M.space_arena = {,", "M.space_arena = {")
    open(PLANO, "w", encoding="utf-8").write(src[:ini] + nuevo + src[fin:])
    print("plano actualizado")
main()
