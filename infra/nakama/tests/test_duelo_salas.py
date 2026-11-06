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
        nk.match_get = lambda mid, *a: (h.lua.table(match_id=mid, label=salas[mid]["label"], size=salas[mid]["size"], authoritative=True) if mid in salas else None)
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

print("\n== Indexado lento: el amigo entra AL INSTANTE de crear la sala ==")
for privada in (False, True):
    h, salas = S.mundo()
    c = S.crear(h, mode="duelo", map="space_arena", private=privada, max_players=4, name="Rapida")
    # Nakama aun no indexo la sala: match_list devuelve vacio, pero match_get la conoce.
    h.lua.globals().nk.match_list = lambda *a: h.lua.table()
    j = unir(h, c["code"])
    check(("privada" if privada else "publica") + ": entra aunque el listado aun no la vea", j.get("match_id") == c["match_id"], str(j))
    j2 = unir(h, c["code"].lower())
    check("  y tambien con el codigo en minusculas", j2.get("match_id") == c["match_id"], str(j2))
h, salas = S.mundo()
check("un codigo inexistente sigue dando code_not_found", unir(h, "ZZZZZ").get("error") == "code_not_found")

print("\n== Casos limite de la logica de salas ==")
h, salas = S.mundo()
c = S.crear(h, mode="duelo", map="space_arena", max_players=2, name="Pequena")
check("aforo 2 respetado", c.get("max_players") == 2, str(c.get("max_players")))
salas[c["match_id"]]["size"] = 2
check("sala llena -> match_full", unir(h, c["code"]).get("error") == "match_full")
h, salas = S.mundo()
c = S.crear(h, mode="duelo", map="space_arena", max_players=999)
check("aforo enorme se recorta al techo duro (40)", c.get("max_players") == 40, str(c.get("max_players")))
c = S.crear(h, mode="duelo", map="space_arena", max_players=0)
check("aforo 0 sube a 1", c.get("max_players") == 1, str(c.get("max_players")))
c = S.crear(h, mode="duelo", map="space_arena", max_players=-5)
check("aforo negativo sube a 1", c.get("max_players") == 1, str(c.get("max_players")))
c = S.crear(h, mode="inventado", map="no_existe", name="x" * 200)
check("modo y mapa desconocidos caen a un valor valido", c.get("mode") and c.get("map"), str(c))
check("nombre largo se recorta a 24", len(c.get("name", "")) <= 24, str(len(c.get("name", ""))))
c = S.crear(h, mode="duelo", map="space_arena", name="Hola\x01\x02mundo")
check("el nombre no admite caracteres de control", "\x01" not in c.get("name", ""), repr(c.get("name")))
codigos = set()
for _ in range(40):
    codigos.add(S.crear(h, mode="duelo", map="space_arena")["code"])
check("40 salas seguidas -> 40 codigos distintos", len(codigos) == 40, str(len(codigos)))
check("todos tienen 5 caracteres validos", all(len(x) == 5 and all(ch in "ABCDEFGHJKMNPQRSTUVWXYZ23456789" for ch in x) for x in codigos))
for raro in ("", "abc", "K7M2Q99", "!!!!!", None):
    r = unir(h, raro if raro is not None else "")
    check("codigo %r -> error controlado" % (raro,), r.get("error") in ("code_invalid", "code_not_found"), str(r))
cod = next(iter(codigos))
check("codigo con guion y minusculas se acepta", unir(h, cod[:2].lower() + "-" + cod[2:].lower()).get("match_id") is not None)
sid = next(k for k, v in salas.items() if json.loads(v["label"]).get("code") == cod)
lab = json.loads(salas[sid]["label"]); lab["phase"] = "closed"; salas[sid]["label"] = json.dumps(lab)
check("sala cerrada -> match_closed", unir(h, cod).get("error") == "match_closed")

print("\n== Sala de guardia (lista vacia) ==")
h, salas = S.mundo()
h.lua.globals().nk.storage_read = lambda *a: h.lua.table()
h.lua.globals().nk.storage_write = lambda *a: None
l = json.loads(h.M.rpc_list_rooms(h.lua.table(user_id="amigo"), "{}"))
check("con la lista vacia se abre UNA sala de guardia", l.get("count") == 1, str(l)[:200])
if l.get("rooms"):
    g = l["rooms"][0]
    check("la de guardia no lleva bots", g.get("bots") == 0, str(g.get("bots")))
    check("tiene codigo (se puede unir desde la lista)", len(str(g.get("code", ""))) == 5, str(g.get("code")))
    lab = json.loads(salas[g["match_id"]]["label"]) if g.get("match_id") in salas else {}
    check("el servidor la crea con 0 bots", lab.get("bots", 0) == 0, str(lab))
    j = unir(h, g["code"])
    check("y el amigo entra con ese codigo", j.get("match_id") == g["match_id"], str(j))

print("\nDUELO_SALAS:", "TODO BIEN" if fallos == 0 else f"{fallos} FALLOS")
sys.exit(1 if fallos else 0)
