#!/usr/bin/env python3
"""Skins en TODOS los bots del servidor y charla: se habla, no se inunda, nada roto ni repetido."""
import os, sys, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_match_coop as T

SKINS = {"neko_base","neko_fuego","neko_hielo","neko_toxica","neko_sombra","neko_oro","neko_sangre","neko_hueso"}
OP_BOT_SAY = 93
fallos = 0
def check(nombre, ok, det=""):
    global fallos
    print(("  ok   " if ok else "  FALLA ") + nombre + ("" if ok else f"  [{det}]"))
    if not ok: fallos += 1

def partida(modo, mapa="recycling_plant", ticks=900):
    h = T.Harness()
    a = h.presence("u1", "Ana")
    h.state = h.M.match_init(h.lua.table(), h.lua.table(mode=modo, map=mapa))[0]
    h.join(a)
    h.tick(2)
    return h, a

print("\n[1] skins: todos los bots llevan una skin VALIDA de la tienda y el rol importa")
por_rol = {}
for modo in ("coop_waves", "survival", "horde", "boss_rush", "freestylers"):
    h, a = partida(modo)
    for p in h.py(h.state)["players"].values():
        if not p.get("bot"): continue
        rol = p.get("side") or "entrenado"
        sk = p.get("skin", "")
        check(f"{modo}/{rol} {p.get('username')}: skin '{sk}'", sk in SKINS, sk)
        por_rol.setdefault(rol, set()).add(sk)
check("la pandilla NO viste skins amables (oro/hielo)", not (por_rol.get("pandilla", set()) & {"neko_oro", "neko_hielo"}), por_rol.get("pandilla"))
check("el amigo NO viste skins de pandilla (sangre/sombra/toxica)", not (por_rol.get("amigo", set()) & {"neko_sangre", "neko_sombra", "neko_toxica"}), por_rol.get("amigo"))

print("\n[2] la calle HABLA cuando el jugador se acerca, y el texto es correcto")
h, a = partida("coop_waves")
frases = []
for t in range(3, 1500):
    h.clock += 0.1
    h.tick(t)
    for op, payload, _ in h.sent:
        if op == OP_BOT_SAY: frases.append(payload)
    h.sent.clear()
    # el jugador camina hacia los bots para provocar avisos
    if t % 40 == 0:
        est = h.py(h.state)
        otros = [p for p in est["players"].values() if p.get("bot") and p.get("side") in ("pandilla", "solo", "amigo")]
        if otros: h.state["players"]["u1"]["pos"] = h.lua.table(x=otros[0]["pos"]["x"] + 3, y=0, z=otros[0]["pos"]["z"])
print("   frases recibidas:", len(frases))
check("los bots dijeron algo en 150 s de partida", len(frases) > 0, len(frases))
textos = [f["text"] for f in frases]
check("ninguna frase tiene huecos sin rellenar", all("{" not in x and "}" not in x for x in textos), [x for x in textos if "{" in x][:2])
check("ninguna frase esta vacia ni es de 1 palabra", all(len(x.split()) >= 3 for x in textos), [x for x in textos if len(x.split()) < 3][:2])
check("todas empiezan en mayuscula y acaban en signo", all(x[0].isupper() and x[-1] in ".!?" for x in textos), [x for x in textos if not (x[0].isupper() and x[-1] in '.!?')][:2])
check("no hay espacios dobles ni signos pegados raros", all("  " not in x and " ," not in x and " ." not in x for x in textos))
check("cada frase lleva el rol de quien habla", all(f.get("rol") in ("pandilla", "solo", "amigo", "entrenado") for f in frases))
for f in frases[:6]: print(f"   [{f['rol']}] {f['name']}: {f['text']}")

print("\n[3] presupuesto: con calle completa, 3 jugadores y mucha accion no se inunda")
por_seg = {}; total = 0; ult = {}
h = T.Harness()
js = [h.presence(f"u{i}", f"Jug{i}") for i in range(1, 4)]
h.state = h.M.match_init(h.lua.table(), h.lua.table(mode="coop_waves", map="recycling_plant"))[0]
h.join(*js); h.tick(2)
for t in range(3, 2400):
    h.clock += 0.1
    h.tick(t)
    # los jugadores se plantan encima de los bots para provocar aviso, disparo y heridas
    if t % 25 == 0:
        est = h.py(h.state)
        otros = [p for p in est["players"].values() if p.get("bot") and p.get("side") in ("pandilla", "solo", "amigo")]
        for j, uid in enumerate(("u1", "u2", "u3")):
            if otros: h.state["players"][uid]["pos"] = h.lua.table(x=otros[j % len(otros)]["pos"]["x"] + 2, y=0, z=otros[j % len(otros)]["pos"]["z"])
    if t % 60 == 0:
        est = h.py(h.state)
        bots = [uid for uid, p in est["players"].items() if p.get("bot") and not p.get("dead") is True]
        if bots: h.tick(t, msgs=[(85, js[0], {"user_id": bots[0], "damage": 20})])
    vistos_tick = set()
    for op, payload, targets in h.sent:
        if op == OP_BOT_SAY:
            clave = (payload["name"], payload["text"])
            if clave in vistos_tick: continue      # la misma frase enviada a otro jugador cercano
            vistos_tick.add(clave)
            total += 1
            seg = int(h.clock); por_seg[seg] = por_seg.get(seg, 0) + 1
            ult.setdefault(payload["name"], []).append(h.clock)
    h.sent.clear()
pico = max(por_seg.values()) if por_seg else 0
print(f"   frases emitidas: {total} en {int(h.clock)} s | pico por segundo (sala): {pico}")
check("la sala SI habla (el test no es vacio): mas de 15 frases", total > 15, total)
check("pico de la sala <= 3 frases/s", pico <= 3, pico)
huecos = [min(b - a for a, b in zip(v, v[1:])) for v in ult.values() if len(v) > 1]
check("ningun bot habla mas de 1 vez cada ~6 s", all(g >= 6.0 for g in huecos), min(huecos) if huecos else None)

print("\n[4] variedad: un bot no repite su ultima frase")
MODULES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "modules")
sys.path.insert(0, MODULES)
from lupa import LuaRuntime
L = LuaRuntime(unpack_returned_tuples=True)
with open(os.path.join(MODULES, "charla_bots.lua"), encoding="utf-8") as _f:
    _src = _f.read().replace("return M\n", "return M")
M = L.execute("local f=function() " + _src + " end return f()")
for rol in ("pandilla", "solo", "amigo", "entrenado"):
    mem = L.table(); ctx = L.table(nombre="Ana", gang="Los Oxido", mapa="Planta", vida=0.8, dist=15, oleada=2)
    seq = [str(M.decir(rol, "aviso", ctx, mem, None)) for _ in range(400)]
    seguidas = sum(1 for i in range(1, len(seq)) if seq[i] == seq[i-1])
    ult12 = sum(1 for i in range(12, len(seq)) if seq[i] in seq[i-12:i])
    check(f"{rol}: 400 frases, {len(set(seq))} distintas, 0 repetidas seguidas", seguidas == 0, seguidas)
    check(f"{rol}: no repite dentro de sus ultimas 12", ult12 == 0, ult12)

print("\nTODO OK" if fallos == 0 else f"\n{fallos} FALLOS")
sys.exit(1 if fallos else 0)
