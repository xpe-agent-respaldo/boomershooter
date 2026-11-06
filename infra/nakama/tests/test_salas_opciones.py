#!/usr/bin/env python3
"""Opciones de sala: monstruos si/no, aforo, bots. Una sala sin monstruos no genera oleadas."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_match_coop as T

class S:
    @staticmethod
    def mundo():
        h = T.Harness(); h.lua.execute("math.randomseed(11)")
        salas = {}
        def match_create(nombre, setup):
            mid = "sala-%d.nakama" % (len(salas) + 1)
            st, _, label = h.M.match_init(h.lua.table(), setup)
            salas[mid] = {"state": st, "label": label, "size": 0}
            return mid
        nk = h.lua.globals().nk
        nk.match_create = match_create
        nk.match_list = lambda *a: h.lua.table_from([{"match_id": k, "label": v["label"], "size": v["size"], "authoritative": True} for k, v in salas.items()], recursive=True)
        nk.account_get_id = lambda uid: h.lua.table(user=h.lua.table(username="Ana"))
        return h, salas
    @staticmethod
    def crear(h, **kw):
        return json.loads(h.M.rpc_create_room(h.lua.table(user_id="u1"), json.dumps(kw)))

fallos = 0
def check(n, ok, det=""):
    global fallos
    print(("  ok   " if ok else "  FALLA ") + n + ("" if ok else f"  [{det}]"))
    if not ok: fallos += 1

def sala(**setup):
    h = T.Harness()
    st, _, label = h.M.match_init(h.lua.table(), h.lua.table(mode="coop_waves", **setup))
    h.state = st
    h.join(h.presence("u1"), h.presence("u2"))
    return h, json.loads(label)

def avanzar(h, veces=6):
    for _ in range(veces):
        h.clock += 10
        h.tick()
    return h.state

print("\n[opciones de sala: monstruos]")
h, lab = sala()
check("por defecto la sala tiene monstruos", lab.get("monsters") is True, str(lab))
st = avanzar(h)
check("con monstruos arranca la oleada y aparecen enemigos", st.wave >= 1 and st.enemies_total_wave > 0,
      f"wave={st.wave} total={st.enemies_total_wave}")

h, lab = sala(monsters=False)
check("la etiqueta anuncia sala sin monstruos", lab.get("monsters") is False, str(lab))
st = avanzar(h, 10)
check("sin monstruos NO se genera ni un enemigo", (st.enemies_total_wave or 0) == 0 and (st.enemies_alive or 0) == 0,
      f"total={st.enemies_total_wave} vivos={st.enemies_alive}")
check("sin monstruos NO cuenta oleadas", (st.wave or 0) == 0, f"wave={st.wave}")
check("la sala queda en fase libre y abierta", st.phase == "free", str(st.phase))
st = avanzar(h, 10)
check("sigue estable pasado el tiempo (sin bucle de oleadas)", (st.wave or 0) == 0 and st.phase == "free")

print("\n[opciones de sala: aforo y bots]")
h, lab = sala(max_players=4)
check("aforo de 4 reflejado en la etiqueta", lab.get("max") == 4, str(lab))
h, lab = sala(bots=0)
st = avanzar(h, 3)
bots = sum(1 for _, p in st.players.items() if p.bot)
check("bots=0 -> sala sin bots", bots == 0, f"bots={bots}")
h, lab = sala(bots=99)
st = avanzar(h, 3)
bots = sum(1 for _, p in st.players.items() if p.bot)
check("bots=99 se recorta al tope (max 5)", bots <= 5, f"bots={bots}")

print("\n[RPC create_room con opciones]")
h, salas = S.mundo()
a = S.crear(h, mode="coop_waves", map="storm_village", monsters=False, max_players=6, bots=2, private=True, name="Privada")
check("devuelve monsters=false", a.get("monsters") is False, str(a))
check("devuelve el aforo pedido", a.get("max_players") == 6, str(a))
check("devuelve los bots pedidos", a.get("bots") == 2, str(a))
lab = json.loads(salas[a["match_id"]]["label"])
check("la sala creada guarda monsters=false, aforo 6 y privada", lab["monsters"] is False and lab["max"] == 6 and lab["private"] is True, str(lab))
b = S.crear(h, max_players=999, bots=-4)
check("aforo absurdo se recorta a 40 y bots negativos a 0", b.get("max_players") == 40 and b.get("bots") == 0, str(b))
c = S.crear(h)
check("sin opciones: monstruos si, aforo 20", c.get("monsters") is True and c.get("max_players") == 20, str(c))

print("\n[listado de salas]")
h, salas = S.mundo()
S.crear(h, name="Con bichos")
S.crear(h, name="Tranquila", monsters=False)
lista = json.loads(h.M.rpc_list_rooms(h.lua.table(user_id="u2"), "{}"))
por_nombre = {r["name"]: r for r in lista.get("rooms", lista if isinstance(lista, list) else [])}
check("el listado dice que 'Con bichos' tiene monstruos", por_nombre.get("Con bichos", {}).get("monsters") is True, str(por_nombre))
check("el listado dice que 'Tranquila' NO tiene monstruos", por_nombre.get("Tranquila", {}).get("monsters") is False, str(por_nombre))

print("\nSALAS_OPCIONES:", "TODO BIEN" if fallos == 0 else f"{fallos} FALLOS")
sys.exit(1 if fallos else 0)
