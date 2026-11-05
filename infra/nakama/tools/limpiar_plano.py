#!/usr/bin/env python3
"""Limpia el plano de suelo medido (infra/nakama/modules/map_floor.lua).

El plano se mide con rayos cada 2 m en el juego (tools/tests/medir_mapas). La medicion trae
tres clases de ruido que rompen el movimiento de los bots:

  1. Celdas FUERA de los muros: el rayo cae en el borde del plano de suelo del nivel
     (la Aldea medía hasta ±36 con los muros en ±34). Los bots aparecian fuera de la arena.
  2. ISLAS: celdas suelta(s) sin vecinas, casi siempre dentro de un obstaculo cerrado.
     Un bot que cae ahi no puede salir: se queda clavado (paso_hacia no encuentra vecina).
  3. AGUJEROS de una celda entre cuatro celdas buenas y a la misma altura: fallo de
     medicion (el rayo pego en un borde o en una viga). El bot pasa de una celda a otra y
     de golpe su celda "no existe": se queda flotando o hundido.

Uso:  python3 infra/nakama/tools/limpiar_plano.py [--check]
      --check  solo informa, no escribe (codigo de salida 1 si habria cambios)
"""
import os
import re
import sys
from collections import deque

AQUI = os.path.dirname(os.path.abspath(__file__))
PLANO = os.path.join(AQUI, "..", "modules", "map_floor.lua")

# Limite interior de cada mapa: hasta donde puede estar un bot sin salir de los muros.
LIMITE = {"recycling_plant": 28, "storm_village": 32, "space_arena": 52}
ORDEN = ("recycling_plant", "storm_village", "space_arena")
TOL_AGUJERO = 0.30   # dos celdas a menos de 30 cm se consideran el mismo suelo
CELDA = re.compile(r"\{(-?\d+),(-?\d+),(-?[\d.]+)\}")


def leer(src):
    planos = {}
    for mapa in ORDEN:
        bloque = src.split("M." + mapa + " = {")[1].split("\n}")[0]
        planos[mapa] = {(int(x), int(z)): float(y) for x, z, y in CELDA.findall(bloque)}
    return planos


def componentes(celdas):
    """Grupos de celdas conectadas en 8 direcciones (un bot anda en diagonal)."""
    vistos = set()
    grupos = []
    for c in sorted(celdas):
        if c in vistos:
            continue
        cola, grupo = deque([c]), []
        vistos.add(c)
        while cola:
            x, z = cola.popleft()
            grupo.append((x, z))
            for dx in (-2, 0, 2):
                for dz in (-2, 0, 2):
                    v = (x + dx, z + dz)
                    if v in celdas and v not in vistos:
                        vistos.add(v)
                        cola.append(v)
        grupos.append(grupo)
    grupos.sort(key=len, reverse=True)
    return grupos


def agujeros(celdas):
    """Celdas ausentes rodeadas por las 4 ortogonales, todas a la misma altura."""
    if not celdas:
        return {}
    xs = range(min(c[0] for c in celdas), max(c[0] for c in celdas) + 1, 2)
    zs = range(min(c[1] for c in celdas), max(c[1] for c in celdas) + 1, 2)
    relleno = {}
    for x in xs:
        for z in zs:
            if (x, z) in celdas:
                continue
            ort = [celdas.get((x + 2, z)), celdas.get((x - 2, z)),
                   celdas.get((x, z + 2)), celdas.get((x, z - 2))]
            if any(v is None for v in ort):
                continue
            if max(ort) - min(ort) <= TOL_AGUJERO:
                relleno[(x, z)] = round(sum(ort) / 4.0, 2)
    return relleno


def limpiar(mapa, celdas):
    lim = LIMITE[mapa]
    fuera = [c for c in celdas if abs(c[0]) > lim or abs(c[1]) > lim]
    for c in fuera:
        del celdas[c]
    islas = 0
    while True:
        grupos = componentes(celdas)
        if len(grupos) <= 1:
            break
        for grupo in grupos[1:]:
            islas += len(grupo)
            for c in grupo:
                del celdas[c]
    rellenos = {}
    while True:
        nuevos = agujeros(celdas)
        if not nuevos:
            break
        celdas.update(nuevos)
        rellenos.update(nuevos)
    return len(fuera), islas, rellenos


def escribir(planos, src):
    salida = src
    for mapa in ORDEN:
        celdas = planos[mapa]
        filas, fila = [], []
        for c in sorted(celdas):  # mismo orden que la medicion: por x y luego z
            fila.append("{%d,%d,%s}" % (c[0], c[1], ("%.1f" % cels_y) if (cels_y := celdas[c]) else "0.0"))
            if len(fila) == 12:
                filas.append(",".join(fila) + ",")
                fila = []
        if fila:
            filas.append(",".join(fila) + ",")
        cuerpo = "\n  ".join(filas).rstrip(",")
        bloque_viejo = src.split("M." + mapa + " = {")[1].split("\n}")[0]
        salida = salida.replace("M." + mapa + " = {" + bloque_viejo + "\n}",
                                "M." + mapa + " = {\n  " + cuerpo + "\n}", 1)
        salida = re.sub(r"-- " + mapa + r": \d+ celdas", "-- %s: %d celdas" % (mapa, len(celdas)), salida)
    return salida


def main():
    check = "--check" in sys.argv
    src = open(PLANO, encoding="utf-8").read()
    planos = leer(src)
    cambios = False
    for mapa in ORDEN:
        antes = len(planos[mapa])
        fuera, islas, rellenos = limpiar(mapa, planos[mapa])
        print("%-16s %4d -> %4d celdas | fuera de muro %3d | islas %3d | agujeros rellenos %2d"
              % (mapa, antes, len(planos[mapa]), fuera, islas, len(rellenos)))
        if fuera or islas or rellenos:
            cambios = True
    if not cambios:
        print("El plano ya esta limpio.")
        return 0
    if check:
        print("Habria cambios (--check).")
        return 1
    nuevo = escribir(planos, src)
    open(PLANO, "w", encoding="utf-8").write(nuevo)
    print("Escrito", os.path.relpath(PLANO))
    return 0


if __name__ == "__main__":
    sys.exit(main())
