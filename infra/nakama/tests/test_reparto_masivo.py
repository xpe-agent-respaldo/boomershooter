#!/usr/bin/env python3
"""Reparto masivo: 120 jugadores piden sala a la vez, ninguno conectado aun (size=0 en todas las salas).
Antes del arreglo, el emparejador veia todas vacias y desbordaba el aforo (match_full en produccion)."""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_match_coop as T

fallos = 0
def check(n, ok, det=""):
    global fallos
    print(("  ok   " if ok else "  FALLA ") + n + ("" if ok else f"  [{det}]"))
    if not ok: fallos += 1

def reparto(n_jugadores, modo="coop_waves", mapa="space_arena"):
    h = T.Harness()
    salas = {}   # match_id -> label vivo (size siempre 0: nadie conecta en esta ventana)
    def crear(name, setup):
        mid = f"sala-{len(salas)+1}"
        s = h.py(setup)
        salas[mid] = {"mode": s["mode"], "max": 20, "map": s["map"]}
        return mid
    h.lua.globals().nk.match_create = crear
    def listar(*a):
        ahora = int(h.lua.eval("os.time")())
        out = []
        for mid, l in salas.items():
            label = json.dumps({"mode": l["mode"], "open": True, "max": l["max"], "players": 0, "map": l["map"], "t": ahora})
            out.append(h.lua.table(match_id=mid, size=0, label=label))
        return h.lua.table_from(out, recursive=True)
    h.lua.globals().nk.match_list = listar
    asignados = {}
    for i in range(n_jugadores):
        r = json.loads(h.M.rpc_join_or_create(h.lua.table(), json.dumps({"mode": modo, "map": mapa})))
        if "error" in r: return None, r
        asignados[r["match_id"]] = asignados.get(r["match_id"], 0) + 1
    return asignados, None

for n in (20, 21, 60, 120, 400):
    a, err = reparto(n)
    check(f"{n} jugadores: sin errores de reparto", err is None, err)
    if a is None: continue
    mx = max(a.values())
    print(f"       {len(a)} salas, mayor ocupacion {mx}/20")
    check(f"{n} jugadores: ninguna sala pasa de 20", mx <= 20, a)
    check(f"{n} jugadores: salas necesarias = {-(-n//20)} (sin crear de mas)", len(a) == -(-n // 20), len(a))

print("\nTODO OK" if fallos == 0 else f"\n{fallos} FALLOS")
sys.exit(1 if fallos else 0)
