#!/usr/bin/env python3
"""Los bots se ven ANDAR: el servidor manda sus posiciones a 10 Hz (OP_BOT_POS=94), no a 1 Hz.
Con el snapshot completo cada segundo, un bot a 2,2 m/s daba un salto y se quedaba quieto ("estatuas")."""
import json, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_match_coop as T

fallos = 0
def check(n, ok, det=""):
    global fallos
    print(("  ok   " if ok else "  FALLA ") + n + ("" if ok else f"  [{det}]"))
    if not ok: fallos += 1

OP_BOT_POS = 94
for modo in ("coop_waves", "freestylers", "horde"):
    h = T.Harness(); h.lua.execute("math.randomseed(3)")
    a = h.presence("u1", "Ana")
    h.state = h.M.match_init(h.lua.table(), h.lua.table(mode=modo, map="storm_village"))[0]
    h.join(a); h.tick(2)
    h.sent.clear()
    TICKS = 100  # 10 s de partida
    for t in range(3, 3 + TICKS):
        h.clock += 0.1; h.tick(t)
    msgs = [p for o, p, _ in h.sent if o == OP_BOT_POS]
    check(f"{modo}: llega un OP_BOT_POS en cada tick ({len(msgs)}/{TICKS})", len(msgs) == TICKS, f"{len(msgs)}")
    e = msgs[-1]["b"][0]
    check(f"{modo}: cada bot lleva id, x, y, z, yaw y vivo", all(k in e for k in ("id", "x", "y", "z", "yaw", "a")), str(e))
    # el movimiento entre mensajes consecutivos es pequeno y continuo (no un salto por segundo)
    por_bot = {}
    for m in msgs:
        for b in m["b"]: por_bot.setdefault(b["id"], []).append((b["x"], b["z"]))
    saltos = []; movs = 0
    for i, pts in por_bot.items():
        for p0, p1 in zip(pts, pts[1:]):
            d = math.dist(p0, p1)
            if d > 0.01: movs += 1
            saltos.append(d)
    check(f"{modo}: ningun salto de mas de 1 m entre mensajes (peor {max(saltos):.2f} m)", max(saltos) <= 1.0, f"{max(saltos):.2f}")
    if modo != "freestylers" or True:
        check(f"{modo}: algun bot se mueve de verdad ({movs} pasos)", movs > 0, "ninguno se mueve")
    kb = sum(len(json.dumps(m)) for m in msgs) / 1024 / (TICKS / 10)
    check(f"{modo}: coste de red razonable ({kb:.1f} KB/s por jugador)", kb < 12, f"{kb:.1f}")
# si el humano se va, la sala vacia no emite posiciones de bots
h = T.Harness(); h.lua.execute("math.randomseed(3)")
a = h.presence("u1", "Ana")
h.state = h.M.match_init(h.lua.table(), h.lua.table(mode="coop_waves", map="storm_village"))[0]
h.join(a); h.tick(2)
h.state.presences["u1"] = None
h.sent.clear()
for t in range(3, 20): h.clock += 0.1; h.tick(t)
check("sin jugadores no se emite posicion de bots", not [1 for o, _, _ in h.sent if o == OP_BOT_POS])
print("\nTODO OK" if fallos == 0 else f"\n{fallos} FALLOS"); sys.exit(1 if fallos else 0)
