#!/usr/bin/env python3
"""Modos de equipos: duelo por equipos, dominar el punto y punto caliente.

Comprueba lo que da sentido a un modo de equipos: reparto equilibrado, sin fuego amigo,
puntos por baja, captura (en solitario, no si esta disputado), rotacion del punto caliente
y un ganador. Todo lo decide el servidor.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_match_coop as T

OP_HIT_PLAYER, OP_DUEL_EVENT, OP_STATE, OP_RESULT = 95, 96, 70, 91
fallos = 0
def check(nombre, ok, det=""):
    global fallos
    print(("  ok   " if ok else "  FALLA ") + nombre + ("" if ok else f"  [{det}]"))
    if not ok: fallos += 1

def pos(x, z): return {"pos": {"x": x, "y": 1.0, "z": z}}

def sala(modo, n=4, mapa="space_arena"):
    h = T.Harness(); h.init(modo); h.state["map"] = mapa
    ps = [h.presence(f"u{i}", f"J{i}") for i in range(n)]
    h.join(*ps)
    return h, ps

def est(h): return h.py(h.state)
def equipo(h, uid): return est(h)["players"][uid].get("team")
def puntos(h): return est(h)["eq"]["puntos"]
def resultado(h):
    r = h.ops(OP_RESULT)
    return h.py(r[-1]) if r else None

def avanzar(h, ps, segundos, posiciones, t0):
    """Avanza `segundos` s (10 ticks/s) con cada jugador en su sitio. Devuelve el tick final."""
    t = t0
    for _ in range(int(segundos * 10)):
        if h.state is None: return t
        h.clock += 0.1; t += 1
        msgs = [(OP_STATE, p, pos(*posiciones[p.user_id if hasattr(p, 'user_id') else p['user_id']])) for p in ps] if t % 5 == 0 else []
        h.tick(t, msgs=msgs)
    return t

def puntos_sobre_suelo():
    """Ningun punto de captura puede caer dentro de una pared: se comprueba contra el suelo medido."""
    import re
    base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "modules")
    suelo = {}
    for m in re.finditer(r"M\.(\w+) = \{(.*?)\n\}", open(os.path.join(base, "map_floor.lua")).read(), re.S):
        suelo[m.group(1)] = {(int(a), int(b)): float(c) for a, b, c in re.findall(r"\{(-?\d+),(-?\d+),(-?[\d.]+)\}", m.group(2))}
    src = open(os.path.join(base, "match_coop.lua")).read()
    bloque = re.search(r"PUNTOS = \{(.*?)\n  \},\n\}", src, re.S).group(1)
    import math
    for mapa, pts in re.findall(r"(\w+)\s*=\s*\{ (\{.*?\}) \},", bloque):
        P = [(int(a), int(b)) for a, b in re.findall(r"\{(-?\d+), (-?\d+)\}", pts)]
        S = suelo[mapa]
        peor = 1.0
        for x, z in P:
            n = sum(1 for a in range(-8, 9, 2) for b in range(-8, 9, 2) if a*a + b*b <= 49 and (x + a, z + b) in S)
            tot = sum(1 for a in range(-8, 9, 2) for b in range(-8, 9, 2) if a*a + b*b <= 49)
            peor = min(peor, n / tot)
        check(f"{mapa}: 5 puntos distintos", len(set(P)) == 5, str(P))
        check(f"{mapa}: todos con >=85 % de suelo caminable en su radio (peor {peor:.0%})", peor >= 0.85, f"{peor:.2f}")
        check(f"{mapa}: centro de cada punto es caminable", all((round(x/2)*2, round(z/2)*2) in S for x, z in P), str(P))

def main():
    print("\n[puntos de captura sobre suelo real]")
    puntos_sobre_suelo()
    print("\n[reparto de equipos]")
    for modo in ("tdm", "dominio", "caliente"):
        h, ps = sala(modo, 6)
        h.tick(3)
        eqs = [equipo(h, p["user_id"] if isinstance(p, dict) else p.user_id) for p in ps] if False else [equipo(h, f"u{i}") for i in range(6)]
        check(f"{modo}: 6 jugadores -> 3 rojo y 3 azul", eqs.count("rojo") == 3 and eqs.count("azul") == 3, str(eqs))
        check(f"{modo}: sin bots ni monstruos", not any(p.get("bot") for p in est(h)["players"].values()) and est(h).get("phase") == "free", str(est(h).get("phase")))
    h, ps = sala("tdm", 5); h.tick(3)
    eqs = [equipo(h, f"u{i}") for i in range(5)]
    check("5 jugadores: reparto 3-2 (nunca 4-1)", sorted([eqs.count("rojo"), eqs.count("azul")]) == [2, 3], str(eqs))

    print("\n[no hay fuego amigo, si hay dano al rival]")
    h, ps = sala("tdm", 4); h.tick(3)
    rojos = [f"u{i}" for i in range(4) if equipo(h, f"u{i}") == "rojo"]
    azules = [f"u{i}" for i in range(4) if equipo(h, f"u{i}") == "azul"]
    P = {p.user_id if hasattr(p, "user_id") else p["user_id"]: p for p in ps}
    h.tick(4, msgs=[(OP_STATE, P[u], pos(-52 + 2 * i, -52)) for i, u in enumerate(rojos + azules)])
    h.sent.clear(); h.clock += 1
    h.tick(5, msgs=[(OP_HIT_PLAYER, P[rojos[0]], {"target_id": rojos[1], "damage": 30})])
    check("un rojo NO daña a su companero rojo", est(h)["players"][rojos[1]].get("duel_hp", 100) == 100, str(est(h)["players"][rojos[1]].get("duel_hp")))
    h.clock += 1
    h.tick(6, msgs=[(OP_HIT_PLAYER, P[rojos[0]], {"target_id": azules[0], "damage": 30})])
    check("un rojo SI daña a un azul", est(h)["players"][azules[0]].get("duel_hp") == 70, str(est(h)["players"][azules[0]].get("duel_hp")))

    print("\n[duelo por equipos: gana el equipo con 50 bajas]")
    h, ps = sala("tdm", 2); h.tick(3)
    a, b = ("u0", "u1") if equipo(h, "u0") != equipo(h, "u1") else ("u0", "u1")
    P = {"u0": ps[0], "u1": ps[1]}
    eq_a = equipo(h, a)
    t = 3
    h.tick(4, msgs=[(OP_STATE, P[a], pos(-52, -52)), (OP_STATE, P[b], pos(-44, -52))]); t = 4
    for baja in range(1, 51):
        for _ in range(3):
            h.clock += 1; t += 1
            h.tick(t, msgs=[(OP_HIT_PLAYER, P[a], {"target_id": b, "damage": 40})])
            if h.state is None: break
        if h.state is None: break
        if baja == 49:
            check("a las 49 bajas la partida sigue", h.state is not None and est(h).get("phase") != "closed")
        if baja < 50:
            for _ in range(90):
                h.clock += 1; t += 1; h.tick(t)
    r = resultado(h)
    check("a las 50 bajas termina por equipo", r is not None and r.get("reason") == "team_won", str(r and r.get("reason")))
    check("gana el equipo del tirador", r is not None and r.get("winner_team") == eq_a, str(r and r.get("winner_team")))
    check("el resultado trae los puntos de cada equipo", r is not None and r.get("team_points", {}).get(eq_a) == 50, str(r and r.get("team_points")))

    print("\n[dominar el punto: capturar, sumar, disputar]")
    h, ps = sala("dominio", 2, "snow_fields"); h.tick(3)
    P = {"u0": ps[0], "u1": ps[1]}
    e0, e1 = equipo(h, "u0"), equipo(h, "u1")
    check("los dos jugadores estan en equipos distintos", e0 != e1, f"{e0} {e1}")
    objs = est(h)["eq"]["objetivos"] if est(h).get("eq") else []
    h.tick(4)
    objs = est(h)["eq"]["objetivos"]
    check("hay 3 puntos de captura", len(objs) == 3, str(len(objs)))
    A = objs[0]; lejos = (45, 45)
    t = avanzar(h, [P["u0"], P["u1"]], 2, {"u0": (A["x"], A["z"]), "u1": lejos}, 4)
    check("2 s en el punto aun NO lo captura (hacen falta 4)", est(h)["eq"]["objetivos"][0].get("dueno") is None, str(est(h)["eq"]["objetivos"][0]))
    t = avanzar(h, [P["u0"], P["u1"]], 3, {"u0": (A["x"], A["z"]), "u1": lejos}, t)
    check("tras 4+ s en solitario lo captura", est(h)["eq"]["objetivos"][0].get("dueno") == e0, str(est(h)["eq"]["objetivos"][0]))
    p0 = puntos(h)[e0]
    t = avanzar(h, [P["u0"], P["u1"]], 5, {"u0": (A["x"], A["z"]), "u1": lejos}, t)
    check("un punto en poder suma ~1 por segundo", 4 <= puntos(h)[e0] - p0 <= 6, str(puntos(h)[e0] - p0))
    check("el rival no suma", puntos(h)[e1] == 0, str(puntos(h)))
    # disputado: el rival entra en el punto
    antes = dict(puntos(h))
    B = est(h)["eq"]["objetivos"][1]
    t = avanzar(h, [P["u0"], P["u1"]], 6, {"u0": (B["x"], B["z"]), "u1": (B["x"] + 1, B["z"])}, t)
    check("un punto DISPUTADO (los dos dentro) no se captura", est(h)["eq"]["objetivos"][1].get("dueno") is None, str(est(h)["eq"]["objetivos"][1]))

    print("\n[dominar el punto: gana quien llega a 200]")
    h, ps = sala("dominio", 2, "snow_fields"); h.tick(3); h.tick(4)
    P = {"u0": ps[0], "u1": ps[1]}
    e0 = equipo(h, "u0")
    for o in h.state.eq.objetivos.values() if hasattr(h.state.eq.objetivos, "values") else []: pass
    h.state.eq.puntos[e0] = 197
    for k in range(1, 4):
        o = h.state.eq.objetivos[k]; o.dueno = e0
    t = avanzar(h, [P["u0"], P["u1"]], 3, {"u0": (45, 45), "u1": (-45, -45)}, 4)
    r = resultado(h)
    check("al pasar de 200 termina", r is not None and r.get("reason") == "team_won", str(r and r.get("reason")))
    check("gana el equipo que domina los puntos", r is not None and r.get("winner_team") == e0, str(r and r.get("winner_team")))

    print("\n[punto caliente: solo puntua quien lo ocupa solo, y se mueve]")
    h, ps = sala("caliente", 2, "snow_fields"); h.tick(3); h.tick(4)
    P = {"u0": ps[0], "u1": ps[1]}
    e0, e1 = equipo(h, "u0"), equipo(h, "u1")
    O = est(h)["eq"]["objetivos"]
    check("hay un unico punto activo", len(O) == 1, str(len(O)))
    ox, oz = O[0]["x"], O[0]["z"]
    t = avanzar(h, [P["u0"], P["u1"]], 5, {"u0": (ox, oz), "u1": (45, 45)}, 4)
    check("ocuparlo en solitario puntua (~5 en 5 s)", 4 <= puntos(h)[e0] <= 6, str(puntos(h)))
    antes = puntos(h)[e0]
    t = avanzar(h, [P["u0"], P["u1"]], 5, {"u0": (ox, oz), "u1": (ox + 1, oz)}, t)
    check("disputado (los dos dentro): NADIE puntua", puntos(h)[e0] == antes and puntos(h)[e1] == 0, str(puntos(h)))
    t = avanzar(h, [P["u0"], P["u1"]], 40, {"u0": (45, 45), "u1": (-45, -45)}, t)
    O2 = est(h)["eq"]["objetivos"][0]
    check("a los 45 s el punto cambia de sitio", (O2["x"], O2["z"]) != (ox, oz), f"{(ox, oz)} -> {(O2['x'], O2['z'])}")

    print("\n[equipos: reconexion y salidas]")
    h, ps = sala("tdm", 4); h.tick(3)
    e_antes = equipo(h, "u1")
    h.leave(ps[1]); h.join(ps[1]); h.tick(4)
    check("quien reconecta conserva su equipo", equipo(h, "u1") == e_antes, f"{e_antes} -> {equipo(h, 'u1')}")
    h2, ps2 = sala("tdm", 4); h2.tick(3)
    quitar = [p for p in ps2 if equipo(h2, p["user_id"] if isinstance(p, dict) else p.user_id) == "rojo"]
    h2.leave(*quitar); h2.tick(4)
    quedan = [p for p in ps2 if p not in quitar]
    h2.join(h2.presence("nuevo", "Nuevo")); h2.tick(5)
    check("tras irse un equipo entero, el recien llegado va al equipo vacio", equipo(h2, "nuevo") == "rojo", str(equipo(h2, "nuevo")))

    print("\n" + ("TODO OK" if fallos == 0 else f"{fallos} FALLOS"))
    sys.exit(1 if fallos else 0)

if __name__ == "__main__":
    main()
