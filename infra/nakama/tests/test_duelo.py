#!/usr/bin/env python3
"""Duelo entre jugadores: el servidor lleva la vida, valida cada impacto y cuenta las bajas."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_match_coop as T

OP_HIT_PLAYER, OP_DUEL_EVENT, OP_STATE = 95, 96, 70
fallos = 0
def check(nombre, ok, det=""):
    global fallos
    print(("  ok   " if ok else "  FALLA ") + nombre + ("" if ok else f"  [{det}]"))
    if not ok: fallos += 1

def pos(x, z): return {"pos": {"x": x, "y": 1.0, "z": z}}

def sala(mapa="space_arena", modo="duelo"):
    h = T.Harness()
    h.init(modo)
    h.state["map"] = mapa
    a, b = h.presence("ua", "Ana"), h.presence("ub", "Beto")
    h.join(a, b)
    return h, a, b

def poner(h, a, b, pa, pb, t=3):
    h.tick(t, msgs=[(OP_STATE, a, pos(*pa)), (OP_STATE, b, pos(*pb))])

def golpe(h, de, a_quien, dano, t):
    h.sent.clear()
    h.clock += 1
    h.tick(t, msgs=[(OP_HIT_PLAYER, de, {"target_id": a_quien, "damage": dano})])
    return [e for e in h.ops(OP_DUEL_EVENT)]

def hp(h, uid): return h.py(h.state)["players"][uid].get("duel_hp")

def main():
    print("\n[duelo: sala]")
    h, a, b = sala()
    h.tick(5)
    est = h.py(h.state)
    bots = [u for u, p in est["players"].items() if p.get("bot")]
    check("en el duelo no hay ni un bot (ni companeros ni calle)", len(bots) == 0, str(len(bots)))
    check("no arrancan oleadas ni monstruos", est.get("phase") == "free" and not est.get("wave_active"), str(est.get("phase")))
    check("el modo se llama Duelo", T.MODES_LABEL("duelo") == "Duelo" if hasattr(T, "MODES_LABEL") else True)

    print("\n[duelo: impactos]")
    h, a, b = sala()
    poner(h, a, b, (-52, -52), (-44, -52))     
    ev = golpe(h, a, "ub", 30, 4)
    check("un impacto valido llega a todos como golpe", len(ev) >= 1, str(ev))
    check("el servidor resta la vida (100 -> 70)", hp(h, "ub") == 70, str(hp(h, "ub")))
    ev = golpe(h, a, "ua", 50, 5)
    check("no hay autodano", hp(h, "ua") in (None, 100), str(hp(h, "ua")))
    golpe(h, a, "ub", 5000, 6)
    check("el dano esta acotado por impacto (max 60)", hp(h, "ub") == 10, str(hp(h, "ub")))

    print("\n[duelo: baja y reaparicion]")
    h, a, b = sala()
    poner(h, a, b, (-52, -52), (-44, -52))
    golpe(h, a, "ub", 60, 4); ev = golpe(h, a, "ub", 60, 5)
    kill = [e for e in ev if e.get("kind") == "kill"]
    check("al caer a 0 se anuncia la baja", len(kill) == 1, str(ev))
    check("la baja dice quien mato a quien", bool(kill) and kill[0].get("killer") == "Ana" and kill[0].get("victim") == "Beto", str(kill))
    est = h.py(h.state)["players"]
    check("el que mata suma 1 baja y el caido 1 muerte", est["ua"].get("duel_kills") == 1 and est["ub"].get("duel_deaths") == 1, str((est["ua"].get("duel_kills"), est["ub"].get("duel_deaths"))))
    check("el marcador viene ordenado (el que mas mata primero)", bool(kill) and kill[0]["board"][0]["user_id"] == "ua", str(kill and kill[0].get("board")))
    ev = golpe(h, a, "ub", 30, 6)
    check("un caido no puede recibir mas dano", ev == [] and hp(h, "ub") == 0, str((ev, hp(h, "ub"))))
    for t in range(7, 62):
        h.clock += 1; h.tick(t)
    est = h.py(h.state)["players"]["ub"]
    check("a los 5 s reaparece con la vida llena", est.get("dead") is False and est.get("duel_hp") == 100, str((est.get("dead"), est.get("duel_hp"))))
    ev = golpe(h, a, "ub", 40, 62)
    check("recien reaparecido tiene 2 s de proteccion", ev == [] and hp(h, "ub") == 100, str((ev, hp(h, "ub"))))
    for t in range(63, 90):
        h.clock += 1; h.tick(t)
    golpe(h, a, "ub", 40, 90)
    check("pasada la proteccion vuelve a recibir dano", hp(h, "ub") == 60, str(hp(h, "ub")))

    print("\n[duelo: reglas del servidor]")
    h, a, b = sala()
    poner(h, a, b, (-52, -52), (-10, -8))     # 42 m en diagonal pasando por la roca central: no hay suelo medido en medio
    ev = golpe(h, a, "ub", 30, 4)
    check("sin vista (pared o vacio en medio) NO hace dano", hp(h, "ub") in (None, 100) and ev == [], str((ev, hp(h, "ub"))))
    h, a, b = sala()
    poner(h, a, b, (-52, -52), (-34, -52))
    ev = golpe(h, a, "ub", 30, 4)
    check("con vista limpia a 18 m si hace dano", hp(h, "ub") == 70, str(hp(h, "ub")))
    # ritmo: 40 impactos en el mismo segundo -> solo pasan los permitidos (20)
    h, a, b = sala()
    poner(h, a, b, (-52, -52), (-44, -52))
    h.sent.clear()
    h.tick(4, msgs=[(OP_HIT_PLAYER, a, {"target_id": "ub", "damage": 1}) for _ in range(40)])
    check("el ritmo esta limitado (40 impactos en un tick -> 20)", hp(h, "ub") == 80, str(hp(h, "ub")))

    print("\n[duelo: solo en el duelo]")
    for modo in ("coop_waves", "freestylers", "survival"):
        h, a, b = sala(modo=modo)
        poner(h, a, b, (-52, -52), (-44, -52))
        ev = golpe(h, a, "ub", 50, 4)
        check(f"en {modo} NO se puede danar a otro jugador", ev == [] and hp(h, "ub") is None, str((ev, hp(h, "ub"))))

    print(f"\n{'TODO BIEN' if fallos == 0 else str(fallos) + ' FALLOS'}")
    sys.exit(1 if fallos else 0)

main()
