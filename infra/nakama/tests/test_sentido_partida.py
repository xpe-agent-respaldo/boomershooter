#!/usr/bin/env python3
"""El sentido de la partida: se puede GANAR (meta por modo), perder, y el resultado dice cual de las dos.

Antes oleadas y supervivencia no tenian final posible (solo se acababan perdiendo) y el duelo
no tenia limite de bajas: la partida no tenia objetivo.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_match_coop as T

OP_HIT_PLAYER, OP_DUEL_EVENT, OP_STATE, OP_RESULT, OP_CLOSE = 95, 96, 70, 91, 90
fallos = 0
def check(nombre, ok, det=""):
    global fallos
    print(("  ok   " if ok else "  FALLA ") + nombre + ("" if ok else f"  [{det}]"))
    if not ok: fallos += 1

def ultimo_resultado(h):
    r = h.ops(OP_RESULT)
    return h.py(r[-1]) if r else None

def limpiar_oleada(h, a, t0):
    """Mata a todos los enemigos vivos de la oleada en curso."""
    for _ in range(80):
        vivos = [k for k, e in h.py(h.state)["enemies"].items() if not e.get("dead")] if h.state is not None else []
        if not vivos: return
        for k in vivos:
            for _ in range(12):
                h.clock += 3                    # respeta el ritmo maximo de disparo del servidor
                t0 += 1
                h.tick(t0, msgs=[(T.OP["DAMAGE"], a, {"enemy_id": k, "damage": 1000, "pos": {"x": 0, "y": 1, "z": 0}})])
                if h.state is None: return
                e = h.py(h.state)["enemies"].get(k)
                if e is None or e.get("dead"): break

def jugar_hasta(modo, oleada_meta_menos_1):
    h = T.Harness()
    h.init(modo)
    a = h.presence("ua", "Ana")
    h.join(a)
    h.tick(3, msgs=[(OP_STATE, a, {"pos": {"x": 0, "y": 1, "z": 0}})])
    h.state["wave"] = oleada_meta_menos_1 - 1      # salta a la oleada anterior a la meta
    h.start_wave()                                  # arranca la oleada meta
    return h, a

def main():
    print("\n[metas por modo]")
    # la meta no se lee de dentro del modulo: se comprueba jugando (limpiar la oleada meta = victoria)
    for modo, meta in {"survival": 15, "horde": 15, "boss_rush": 10}.items():
        h, a = jugar_hasta(modo, meta)
        limpiar_oleada(h, a, 10)
        r = ultimo_resultado(h)
        check(f"{modo}: superar la oleada {meta} es victoria", r is not None and r.get("won") is True and r.get("wave_goal") == meta, str(r and (r.get("won"), r.get("wave_goal"))))
    h = T.Harness(); h.init("freestylers")
    a = h.presence("ua", "Ana"); h.join(a)
    h.state["wave"] = 40
    h.tick(3)
    check("Matadero sigue siendo sala libre (no se cierra sola)", h.state is not None and h.py(h.state).get("phase") != "closed")

    print("\n[oleadas: ganar al superar la meta]")
    h, a = jugar_hasta("coop_waves", 20)
    check("estamos en la oleada 20", h.py(h.state)["wave"] == 20, str(h.py(h.state)["wave"]))
    limpiar_oleada(h, a, 10)
    r = ultimo_resultado(h)
    check("al limpiar la 20 se cierra la partida", h.state is None or h.py(h.state).get("phase") == "closed")
    check("el resultado dice VICTORIA (won=true)", r is not None and r.get("won") is True, str(r and r.get("won")))
    check("el motivo es 'victory'", r is not None and r.get("reason") == "victory", str(r and r.get("reason")))
    check("el resultado trae la meta y un texto", r is not None and r.get("wave_goal") == 20 and bool(r.get("winner_text")), str(r))
    check("las estadisticas guardan p_won = true", r is not None and all(s.get("p_won") is True for s in r["stats"]), str(r and r.get("stats")))

    print("\n[oleadas: antes de la meta NO se gana]")
    h, a = jugar_hasta("coop_waves", 7)
    limpiar_oleada(h, a, 10)
    check("limpiar la oleada 7 sigue la partida (no se cierra)", h.state is not None and h.py(h.state).get("phase") != "closed", str(h.state and h.py(h.state).get("phase")))
    check("pasa al descanso", h.py(h.state).get("phase") == "break", str(h.py(h.state).get("phase")))

    print("\n[perder no es ganar]")
    h = T.Harness(); h.init("coop_waves")
    a = h.presence("ua", "Ana"); h.join(a)
    h.tick(3, msgs=[(T.OP["SPAWN"], a, {"pos": {"x": 0, "y": 1, "z": 0}})])
    h.start_wave()
    h.clock += 3
    # el unico jugador cae y nadie puede levantarlo: es el final de la partida (como en una partida real)
    h.tick(30, msgs=[(T.OP["DEATH"], a, {"pos": {"x": 0, "y": 1, "z": 0}, "cause": "monster"})])
    for i in range(40):
        h.clock += 3
        if h.state is None: break
        h.tick(31 + i)
    r = ultimo_resultado(h)
    check("equipo caido: se cierra con resultado", r is not None, "sin resultado")
    check("equipo caido: won=false", r is not None and r.get("won") is False, str(r and r.get("won")))
    check("equipo caido: el motivo no es victoria", r is not None and r.get("reason") != "victory", str(r and r.get("reason")))

    print("\n[duelo: primero a 15 bajas]")
    h = T.Harness(); h.init("duelo"); h.state["map"] = "space_arena"
    a, b = h.presence("ua", "Ana"), h.presence("ub", "Beto")
    h.join(a, b)
    h.tick(3, msgs=[(OP_STATE, a, {"pos": {"x": -52, "y": 1, "z": -52}}), (OP_STATE, b, {"pos": {"x": -44, "y": 1, "z": -52}})])
    t = 3
    for baja in range(1, 16):
        for _ in range(3):                         # 3 impactos de 40 = baja
            h.clock += 1; t += 1
            h.tick(t, msgs=[(OP_HIT_PLAYER, a, {"target_id": "ub", "damage": 40})])
            if h.state is None: break
        if h.state is None: break
        if baja < 15:
            # el caido reaparece antes del siguiente
            for _ in range(60):
                h.clock += 1; t += 1; h.tick(t)
            for _ in range(25):
                h.clock += 1; t += 1; h.tick(t)
        if baja == 14:
            check("a las 14 bajas la partida sigue abierta", h.state is not None and h.py(h.state).get("phase") != "closed")
    r = ultimo_resultado(h)
    check("a las 15 bajas el duelo termina", r is not None and r.get("reason") == "duel_won", str(r and r.get("reason")))
    check("el ganador es Ana", r is not None and r.get("winner") == "ua", str(r and r.get("winner")))
    check("el texto dice quien gana", r is not None and "Ana" in str(r.get("winner_text")), str(r and r.get("winner_text")))

    print("\n" + ("TODO OK" if fallos == 0 else f"{fallos} FALLOS"))
    sys.exit(1 if fallos else 0)

if __name__ == "__main__":
    main()
