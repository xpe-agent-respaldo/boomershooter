#!/usr/bin/env python3
"""Los bots solo hacen dano si VEN al jugador, estan a tiro y aciertan. Y nunca hay mas de 5.

Cubre las quejas de "me quitan vida estando lejos / sin disparar / a traves de paredes".
"""
import os, sys, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_match_coop as T

MODS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "modules")
SUELO = open(os.path.join(MODS, "map_floor.lua"), encoding="utf-8").read()
OP_BOT_HIT, OP_BOT_SHOT = 83, 84

# (mapa, bot, jugador con vista limpia a 10 m, bot2, jugador con 3-5 celdas de VACIO en medio)
CASOS = {
    "recycling_plant": ((-28, -28), (-18, -28), (-28, -8),  (-12, -8)),
    "storm_village":   ((-32, -32), (-22, -32), (-32, -18), (-12, -18)),
    "space_arena":     ((-52, -52), (-42, -52), (-52, -46), (-34, -46)),
}
fallos = 0
def check(nombre, ok, det=""):
    global fallos
    print(("  ok   " if ok else "  FALLA ") + nombre + ("" if ok else f"  [{det}]"))
    if not ok: fallos += 1


def altura(mapa, celda):
    bloque = SUELO.split(f"M.{mapa} = {{")[1].split("\n}")[0]
    for x, z, y in re.findall(r"\{(-?\d+),(-?\d+),(-?[\d.]+)\}", bloque):
        if (int(x), int(z)) == celda:
            return float(y)
    raise KeyError(celda)


def escenario(mapa, bot_celda, jug_celda, modo="freestylers", ticks=60, semilla=7):
    """Un bot hostil y un jugador quieto en celdas concretas. Devuelve (disparos, danos)."""
    h = T.Harness()
    h.lua.execute(f"math.randomseed({semilla})")
    h.init(modo)
    h.state["map"] = mapa
    h.state["bots_wanted"] = 1
    u = h.presence("u1", "Ana")
    h.join(u)
    h.tick(2, msgs=[(1, u, {"pos": {"x": jug_celda[0], "y": altura(mapa, jug_celda) + 1.0, "z": jug_celda[1]}})])
    est = h.py(h.state)
    bots = [uid for uid, p in est["players"].items() if p.get("bot")]
    if not bots:
        return None
    # En Freestylers `bots_wanted` no limita: el modo manda. Se fijan TODOS los bots en la
    # misma celda (si no, los que no se recolocan disparan libres y falsean la medida).
    h.sent.clear()
    for t in range(3, 3 + ticks):
        for k in bots:
            b = h.state["players"][k]
            b["pos"] = h.lua.table(x=float(bot_celda[0]), y=altura(mapa, bot_celda) + 0.0, z=float(bot_celda[1]))
            b["next_fire"] = 0
        h.clock += 1
        h.tick(t, msgs=[(1, u, {"pos": {"x": jug_celda[0], "y": altura(mapa, jug_celda) + 1.0, "z": jug_celda[1]}})])
    return len(h.ops(OP_BOT_SHOT)), len(h.ops(OP_BOT_HIT)), h


def escondite():
    """El escondite del mapa espacial (-18,-32): la pared tapa la vista, la puerta no."""
    print("\n[space_arena: escondite]")
    mapa = "space_arena"
    # jugador dentro, al fondo. Bot A al norte, fuera, con el MURO en medio. Bot B al sur, frente a la puerta.
    dentro = (-18, -32)
    tras_muro = (-18, -42)       # 10 m al norte; el muro norte (z=-35.75) esta en medio
    frente_puerta = (-18, -22)   # 10 m al sur, en linea con la puerta (z=-28)
    lado = (-26, -32)            # 8 m al oeste; muro oeste (x=-21.75) en medio
    for nombre, celda in (("tras el muro norte", tras_muro), ("tras el muro oeste", lado)):
        r = escenario(mapa, celda, dentro)
        check(f"bot {nombre}: NO dispara a quien se esconde", r is not None and r[0] == 0, str(r and r[:2]))
        check(f"bot {nombre}: NO hace dano", r is not None and r[1] == 0, str(r and r[:2]))
    r = escenario(mapa, frente_puerta, dentro)
    check("bot frente a la puerta: SI ve y dispara (la puerta no es pared)", r is not None and r[0] > 0, str(r and r[:2]))
    # el suelo del plano: la pared no es caminable, el interior y la puerta si
    src = open(os.path.join(MODS, "map_floor.lua"), encoding="utf-8").read()
    bloque = src.split("M.space_arena = {")[1].split("\n}")[0]
    celdas = {(int(x), int(z)) for x, z, _ in re.findall(r"\{(-?\d+),(-?\d+),(-?[\d.]+)\}", bloque)}
    check("las celdas bajo los muros ya no son suelo", all(c not in celdas for c in [(-18, -36), (-22, -32), (-14, -32), (-20, -28)]))
    check("el interior sigue siendo suelo", all(c in celdas for c in [(-18, -32), (-16, -32), (-20, -30)]))
    check("la puerta sigue siendo suelo", (-18, -28) in celdas)
    # un bot dentro del plano puede ir de la puerta al centro (el interior no quedo aislado)
    from collections import deque
    cola, vistos = deque([(-18, -28)]), {(-18, -28)}
    while cola:
        x, z = cola.popleft()
        for dx in (-2, 0, 2):
            for dz in (-2, 0, 2):
                v = (x + dx, z + dz)
                if v in celdas and v not in vistos:
                    vistos.add(v); cola.append(v)
    check("desde la puerta se llega al centro del escondite", (-18, -32) in vistos)
    check("y desde ahi se alcanza TODO el mapa (ninguna celda queda aislada)", vistos == celdas, f"{len(vistos)}/{len(celdas)}")


def main():
    global fallos
    for mapa, (bot, limpio, bot2, hueco) in CASOS.items():
        print(f"\n[{mapa}]")
        # 1) vista limpia y a 10 m: dispara y alguna bala da
        r = escenario(mapa, bot, limpio)
        check("con vista limpia el bot dispara", r is not None and r[0] > 0, str(r and r[:2]))
        check("con vista limpia alguna bala da", r is not None and r[1] > 0, str(r and r[:2]))
        check("nunca da mas veces de las que dispara", r is not None and r[1] <= r[0], str(r and r[:2]))

        # 2) hueco en medio: no dispara ni hace dano
        r = escenario(mapa, bot2, hueco)
        check("sin vision (hueco en medio) NO dispara", r is not None and r[0] == 0, str(r and r[:2]))
        check("sin vision NO hace dano", r is not None and r[1] == 0, str(r and r[:2]))

        # 3) lejos (fuera de alcance de 28 m): no dispara ni hace dano
        lejos = (bot[0] + 40, bot[1])
        try:
            altura(mapa, lejos)
            r = escenario(mapa, bot, lejos)
            check("fuera de alcance NO dispara", r is not None and r[0] == 0, str(r and r[:2]))
            check("fuera de alcance NO hace dano", r is not None and r[1] == 0, str(r and r[:2]))
        except KeyError:
            print("  --   (no hay celda a 40 m en linea recta: el alcance se prueba en otro mapa)")

    # 4) el aviso de disparo lleva hit=True solo cuando de verdad hubo dano
    print("\n[coherencia aviso/dano]")
    mapa = "recycling_plant"
    bot, limpio = CASOS[mapa][0], CASOS[mapa][1]
    r = escenario(mapa, bot, limpio, ticks=120)
    h = r[2]
    avisos_hit = sum(1 for o, p, _ in h.sent if o == OP_BOT_SHOT and p.get("hit") is True)
    check("hit=True en el aviso == danos reales", avisos_hit == r[1], f"avisos_hit={avisos_hit} danos={r[1]}")
    check("hay disparos que fallan (hit=False): no es un aimbot",
          any(o == OP_BOT_SHOT and p.get("hit") is False for o, p, _ in h.sent))

    # 5) ningun modo pasa de 5 bots, en ningun mapa
    print("\n[tope de 5 bots por sala]")
    for mapa in CASOS:
        for modo in ("coop_waves", "survival", "horde", "boss_rush", "freestylers"):
            h = T.Harness()
            h.init(modo)
            h.state["map"] = mapa
            a = h.presence("u1", "Ana")
            h.join(a)
            h.tick(2)
            n = sum(1 for p in h.py(h.state)["players"].values() if p.get("bot"))
            check(f"{mapa}/{modo}: {n} bots (max 5)", n <= 5, str(n))

    escondite()
    print(f"\n{'TODO BIEN' if fallos == 0 else str(fallos) + ' FALLOS'}")
    sys.exit(1 if fallos else 0)


if __name__ == "__main__":
    main()
