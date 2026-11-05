#!/usr/bin/env python3
"""Sistema de salas: CREAR y UNIRSE son dos cosas distintas, cada sala tiene un codigo corto,
y puede ser publica o privada. Un mini-Nakama guarda las salas creadas y las devuelve en match_list."""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_match_coop as T

fallos = 0
def check(n, ok, det=""):
    global fallos
    print(("  ok   " if ok else "  FALLA ") + n + ("" if ok else f"  [{det}]"))
    if not ok: fallos += 1

def mundo():
    """Harness con salas reales: match_create corre match_init y match_list las devuelve con su etiqueta."""
    h = T.Harness(); h.lua.execute("math.randomseed(11)")
    salas = {}
    def match_create(nombre, setup):
        mid = "sala-%d.nakama" % (len(salas) + 1)
        st, _, label = h.M.match_init(h.lua.table(), setup)
        salas[mid] = {"state": st, "label": label, "size": 0}
        return mid
    def match_list(*a):
        return h.lua.table_from([{"match_id": k, "label": v["label"], "size": v["size"], "authoritative": True}
                                 for k, v in salas.items()], recursive=True)
    nk = h.lua.globals().nk
    nk.match_create = match_create
    nk.match_list = match_list
    nk.account_get_id = lambda uid: h.lua.table(user=h.lua.table(username="Ana"))
    return h, salas

def crear(h, **kw):
    return json.loads(h.M.rpc_create_room(h.lua.table(user_id="u1"), json.dumps(kw)))
def unir(h, codigo):
    return json.loads(h.M.rpc_join_room(h.lua.table(user_id="u2"), json.dumps({"code": codigo})))
def listar(h):
    return json.loads(h.M.rpc_list_rooms(h.lua.table(user_id="u2"), "{}"))

print("[crear]")
h, salas = mundo()
a = crear(h, mode="coop_waves", map="storm_village", name="Los Panas")
check("create_room devuelve match_id y codigo", bool(a.get("match_id")) and bool(a.get("code")), str(a))
check("el codigo tiene 5 caracteres legibles (sin 0/O/1/I/L)", re.fullmatch(r"[A-HJKMNP-Z2-9]{5}", a["code"]) is not None, a["code"])
check("respeta el mapa y el nombre elegidos", a["map"] == "storm_village" and a["name"] == "Los Panas", str(a))
check("por defecto la sala es publica", a["private"] is False, str(a))
b = crear(h, mode="coop_waves", map="storm_village")
check("crear dos veces NUNCA reutiliza la sala (aunque sea el mismo modo y mapa)", a["match_id"] != b["match_id"], str(b))
check("cada sala tiene un codigo distinto", a["code"] != b["code"], f'{a["code"]} {b["code"]}')
check("modo desconocido cae a oleadas, mapa desconocido al de por defecto",
      crear(h, mode="xx", map="yy")["mode"] == "coop_waves")
nombre = crear(h)["name"]
check("sin nombre usa 'Sala de <usuario>'", nombre == "Sala de Ana", nombre)

print("[unirse por codigo]")
r = unir(h, a["code"])
check("join_room entra a la sala correcta por su codigo", r.get("match_id") == a["match_id"], str(r))
check("el codigo vale en minusculas", unir(h, a["code"].lower()).get("match_id") == a["match_id"])
check("el codigo vale con guion y espacios", unir(h, " " + a["code"][:3] + "-" + a["code"][3:] + " ").get("match_id") == a["match_id"])
check("codigo que no existe -> code_not_found", unir(h, "ZZZZZ").get("error") == "code_not_found")
check("codigo demasiado corto -> code_invalid", unir(h, "AB").get("error") == "code_invalid")
check("codigo vacio -> code_invalid", unir(h, "").get("error") == "code_invalid")
n = len(salas)
unir(h, "ZZZZZ")
check("join_room nunca crea salas", len(salas) == n)

print("[publica / privada]")
h, salas = mundo()
pub = crear(h, mode="coop_waves", map="recycling_plant", name="Abierta", private=False)
pri = crear(h, mode="coop_waves", map="recycling_plant", name="Secreta", private=True)
check("la privada lo declara", pri["private"] is True and pub["private"] is False, str(pri))
ids = [x["match_id"] for x in listar(h)["rooms"]]
check("la publica sale en la lista", pub["match_id"] in ids, str(ids))
check("la privada NO sale en la lista", pri["match_id"] not in ids, str(ids))
check("la lista incluye el codigo de cada sala publica", all(x.get("code") for x in listar(h)["rooms"] if x["match_id"] == pub["match_id"]))
check("la privada SI se puede entrar con su codigo", unir(h, pri["code"]).get("match_id") == pri["match_id"])
check("la publica tambien se puede entrar por codigo", unir(h, pub["code"]).get("match_id") == pub["match_id"])
check("el codigo de la privada no se filtra en la lista", all(x.get("code") != pri["code"] for x in listar(h)["rooms"]))
st = salas[pri["match_id"]]["state"]
check("el estado interno de la privada esta cerrado al publico", st["private"] is True)

print("[salas llenas o cerradas]")
h, salas = mundo()
x = crear(h, mode="coop_waves", map="recycling_plant")
salas[x["match_id"]]["size"] = 20
check("sala llena -> match_full", unir(h, x["code"]).get("error") == "match_full", str(unir(h, x["code"])))
y = crear(h, mode="coop_waves", map="recycling_plant")
lab = json.loads(salas[y["match_id"]]["label"]); lab["phase"] = "closed"
salas[y["match_id"]]["label"] = json.dumps(lab)
check("sala cerrada -> match_closed", unir(h, y["code"]).get("error") == "match_closed")

print("[compatibilidad]")
h, salas = mundo()
old = json.loads(h.M.rpc_join_or_create(h.lua.table(user_id="u1"), json.dumps({"mode": "coop_waves", "map": "storm_village"})))
check("join_or_create (clientes viejos) sigue funcionando", bool(old.get("match_id")), str(old))

print("\nTODO OK" if fallos == 0 else f"\n{fallos} FALLOS"); sys.exit(1 if fallos else 0)
