#!/usr/bin/env python3
"""Recorrido del amigo: el anfitrion crea un DUELO en la arena espacial y el amigo lo encuentra y entra.
Tambien: las salas privadas NUNCA llevan bots."""
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

def lista(h):
    r = json.loads(h.M.rpc_list_rooms(h.lua.table(user_id="amigo"), ""))
    return r.get("rooms", r) if isinstance(r, dict) else r

def unir(h, codigo):
    return json.loads(h.M.rpc_join_room(h.lua.table(user_id="amigo"), json.dumps({"code": codigo})))

for privada in (False, True):
    etiqueta = "PRIVADA" if privada else "PUBLICA"
    print(f"\n== Duelo en SpaceArena, {etiqueta} ==")
    h, salas = S.mundo()
    c = S.crear(h, mode="duelo", map="space_arena", private=privada, bots=3, monsters=True, max_players=4, name="Duelo de amigos")
    check("se crea la sala", bool(c.get("match_id")), str(c))
    check("modo duelo y mapa espacial", c.get("mode") == "duelo" and c.get("map") == "space_arena", str(c))
    check("hay codigo de 5 caracteres", len(str(c.get("code", ""))) == 5, str(c))
    check("sin bots aunque el cliente pidiera 3", c.get("bots") == 0, str(c.get("bots")))
    lab = json.loads(salas[c["match_id"]]["label"])
    check("la etiqueta del servidor dice duelo/espacio", lab.get("mode") == "duelo" and lab.get("map") == "space_arena", str(lab))
    check("el aforo es el pedido (4)", lab.get("max") == 4, str(lab.get("max")))
    check("0 bots en la partida", lab.get("bots", 0) == 0, str(lab))
    # el amigo mira la lista
    l = lista(h)
    ids = [x.get("match_id") for x in l]
    if privada:
        check("la privada NO sale en la lista", c["match_id"] not in ids, str(ids))
    else:
        check("la publica SALE en la lista del amigo", c["match_id"] in ids, str(ids))
        fila = [x for x in l if x.get("match_id") == c["match_id"]][0]
        check("la fila dice duelo y mapa espacial", fila.get("mode") == "duelo" and fila.get("map") == "space_arena", str(fila))
    # entra con el codigo (sirve para ambas)
    j = unir(h, c["code"])
    check("el amigo entra con el codigo", j.get("match_id") == c["match_id"] and not j.get("error"), str(j))
    j2 = unir(h, c["code"].lower())
    check("el codigo vale en minusculas", j2.get("match_id") == c["match_id"], str(j2))

print("\n== Salas privadas de cualquier modo: 0 bots ==")
for modo in ("coop_waves", "survival", "horde", "boss_rush", "freestylers"):
    h, salas = S.mundo()
    c = S.crear(h, mode=modo, map="space_arena", private=True, bots=5, max_players=8)
    lab = json.loads(salas[c["match_id"]]["label"])
    check(f"{modo}: privada sin bots", c.get("bots") == 0 and lab.get("bots", 0) == 0, str(c.get("bots")) + " " + str(lab.get("bots")))
h, salas = S.mundo()
c = S.crear(h, mode="coop_waves", map="space_arena", private=False, bots=2, max_players=8)
check("una PUBLICA sigue respetando sus bots (2)", c.get("bots") == 2, str(c.get("bots")))
c = S.crear(h, mode="coop_waves", map="space_arena", private=True)
check("privada sin pedir bots: 0, no el defecto 3", c.get("bots") == 0, str(c.get("bots")))

print("\nDUELO_SALAS:", "TODO BIEN" if fallos == 0 else f"{fallos} FALLOS")
sys.exit(1 if fallos else 0)
