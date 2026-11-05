#!/usr/bin/env python3
"""Prueba de carga del bucle autoritativo: bytes por tick y CPU segun el tamano de la sala.

Mide lo que el servidor emite por tick (OP_MATCH_STATE) y cuanto tarda match_loop, para
decidir limites de sala con datos y no a ojo. Uso:
    python3 infra/nakama/tests/load_match_coop.py
"""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_match_coop as T

OP_MATCH_STATE = 60
TICK_RATE = 10


def run(players):
    """Mide dos momentos caros: la entrada de la sala y el inicio de una oleada grande."""
    h = T.Harness()
    h.init("horde")
    pres = [h.presence(f"u{i}", f"Jugador{i}") for i in range(players)]
    # 1) entrada: un join por jugador, cada uno difunde el snapshot completo a TODOS
    t0 = time.perf_counter()
    for p in pres:
        h.join(p)
    join_ms = (time.perf_counter() - t0) * 1000
    join_msgs = [(pl, tg) for o, pl, tg in h.sent if o == OP_MATCH_STATE]
    join_bytes = sum(len(json.dumps(pl)) for pl, _ in join_msgs)
    for i, p in enumerate(pres):
        h.tick(msgs=[(1, p, {"pos": {"x": (i * 7) % 100 - 50, "y": 1, "z": (i * 11) % 90 - 45}})])
    # 2) oleada: snapshot con todos los enemigos
    h.sent.clear()
    h.start_wave()
    waves = [(pl, tg) for o, pl, tg in h.sent if o == OP_MATCH_STATE]
    wave_bytes = max((len(json.dumps(pl)) for pl, _ in waves), default=0)
    enemies = max((len(pl.get("enemies", [])) for pl, _ in waves), default=0)
    return dict(players=players, enemies=enemies, join_ms=join_ms, join_total_kb=join_bytes / 1024,
                wave_msg_kb=wave_bytes / 1024)


if __name__ == "__main__":
    print(f"{'jug':>4} {'enem':>5} {'entrada: ms':>12} {'entrada: KB totales difundidos':>32} {'snapshot oleada KB':>19} {'x jugadores KB':>15}")
    for n in (1, 5, 10, 20, 40, 60, 100):
        r = run(n)
        print(f"{r['players']:>4} {r['enemies']:>5} {r['join_ms']:>12.1f} {r['join_total_kb']:>32.1f} "
              f"{r['wave_msg_kb']:>19.1f} {r['wave_msg_kb'] * n:>15.0f}")
