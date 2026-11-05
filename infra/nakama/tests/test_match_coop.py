#!/usr/bin/env python3
"""Pruebas del modulo autoritativo match_coop.lua con un Nakama simulado.

Ejecuta el Lua real (via lupa) contra un `nk` y un `dispatcher` falsos y
comprueba las reglas del servidor: spawn, dano, muerte, ayuda, revivir,
desangrado, modos de juego, oleadas fuertes y cierre de partida.

Uso:  python3 infra/nakama/tests/test_match_coop.py
"""
import json
import os
import sys

from lupa import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.join(HERE, "..", "modules", "match_coop.lua")

OP = dict(SPAWN=1, SPAWN_OK=2, SPAWN_REJECT=3, DAMAGE=10, ENEMY_HEALTH=11, ENEMY_DEATH=12,
          DEATH=20, PLAYER_DEATH=21, REVIVE=30, REVIVE_OK=31, REVIVE_REJECT=32, REWARD=40,
          WAVE_STATE=50, MATCH_STATE=60, PLAYER_STATE=70, HELP_CALL=80, TEAM_ALERT=81,
          PING=82, MATCH_CLOSE=90, MATCH_RESULT=91, ERROR=99)

passed = failed = 0


def check(name, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FALLA {name} {detail}")


class Harness:
    def __init__(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.sent = []          # (op, payload, targets)
        self.listed = {}        # salas que devuelve nk.match_list (simulado)
        self.clock = 1000
        g = self.lua.globals()

        def json_encode(t):
            return json.dumps(self._to_py(t))

        def json_decode(s):
            return self.lua.table_from(json.loads(s), recursive=True)

        nk = self.lua.table(
            json_encode=json_encode, json_decode=json_decode,
            logger_info=lambda *a: None, logger_warn=lambda *a: None,
            match_create=lambda *a: "match-1",
            register_matchmaker_matched=lambda *a: None,
            register_rpc=lambda *a: None,
            match_list=lambda *a: self._match_list(*a),
        )
        g.nk = nk
        # Nakama real inyecta el modulo "nakama" en require(); aqui se precarga el falso.
        self.lua.execute('package.preload["nakama"] = function() return nk end')
        # modulos hermanos de match_coop.lua (Nakama los resuelve desde la misma carpeta de modulos)
        _mods = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "modules")
        _suelo = open(os.path.join(_mods, "map_floor.lua"), encoding="utf-8").read()
        self.lua.globals()._src_suelo = _suelo
        self.lua.execute('package.preload["map_floor"] = function() return load(_src_suelo)() end')
        _charla = open(os.path.join(_mods, "charla_bots.lua"), encoding="utf-8").read()
        self.lua.globals()._src_charla = _charla
        self.lua.execute('package.preload["charla_bots"] = function() return load(_src_charla)() end')
        # os.time controlado para probar cooldowns y desangrado
        g.os.time = lambda *a: self.clock
        src = open(MODULE).read()
        # el modulo usa `nk` global y devuelve M
        self.M = self.lua.execute(src)
        self.dispatcher = self.lua.table(
            broadcast_message=lambda op, data, pres, sender, reliable: self.sent.append(
                (int(op), json.loads(data), pres)))

    def _match_list(self, limit=None, authoritative=None, label=None, min_size=None, max_size=None, query=None):
        # Igual que Nakama: solo devuelve salas con size >= min_size.
        rooms = [self.listed[k] for k in sorted(self.listed.keys())] if hasattr(self.listed, "keys") else []
        keep = [r for r in rooms if float(r["size"]) >= float(min_size or 0)]
        return self.lua.table_from(keep, recursive=True)

    def _to_py(self, t):
        if hasattr(t, "items"):
            keys = list(t.keys())
            if keys and all(isinstance(k, int) for k in keys):
                return [self._to_py(t[k]) for k in sorted(keys)]
            return {str(k): self._to_py(v) for k, v in t.items()}
        return t

    def presence(self, uid, name=None):
        return self.lua.table(user_id=uid, session_id="s-" + uid, username=name or uid)

    def init(self, mode="coop_waves"):
        state, _, _ = self.M.match_init(self.lua.table(), self.lua.table(mode=mode))
        self.state = state
        return state

    def join(self, *pres):
        self.state = self.M.match_join(self.lua.table(), self.dispatcher, 1, self.state,
                                       self.lua.table_from(list(pres)))

    def leave(self, *pres):
        self.state = self.M.match_leave(self.lua.table(), self.dispatcher, 1, self.state,
                                        self.lua.table_from(list(pres)))

    def tick(self, tick=2, msgs=()):
        messages = self.lua.table_from([
            self.lua.table(op_code=op, sender=pres, data=json.dumps(payload))
            for op, pres, payload in msgs])
        self.state = self.M.match_loop(self.lua.table(), self.dispatcher, tick, self.state, messages)
        return self.state

    def ops(self, op, clear=False):
        out = [p for o, p, _ in self.sent if o == op]
        if clear:
            self.sent.clear()
        return out

    def start_wave(self):
        self.clock += 10          # saltar el descanso inicial
        self.tick()

    def py(self, lua_obj):
        return self._to_py(lua_obj)


def scenario_freestylers():
    h = Harness()
    h.init("freestylers")
    h.state["bots_wanted"] = 2
    pres = h.presence("u-free", "Free")
    h.join(pres)
    h.start_wave() if False else None
    h.tick(2)
    h.tick(3)
    estado = h.py(h.state)
    bots = [uid for uid, p in estado["players"].items() if p.get("bot")]
    check("freestylers: hay jugadores entrenados", len(bots) >= 1, str(bots))
    # sin monstruos: el tick no genera enemigos
    h.tick(4, msgs=())
    estado = h.py(h.state)
    check("freestylers: ni un monstruo", int(estado.get("enemies_alive", 0)) == 0,
          "enemies_alive=%s" % estado.get("enemies_alive"))
    # dispararle a un entrenado lo derriba
    objetivo = bots[0]
    h.tick(5, msgs=[(85, pres, {"user_id": objetivo, "damage": 100})])
    estado = h.py(h.state)
    check("freestylers: el entrenado cae de un disparo certero",
          estado["players"][objetivo].get("dead") is True,
          str(estado["players"][objetivo].get("dead")))
    bajas = h.ops(86)
    check("freestylers: se avisa de la baja", len(bajas) >= 1, str(len(bajas)))
    check("freestylers: la baja da puntos", int(estado["players"]["u-free"].get("kills", 0)) >= 1,
          str(estado["players"]["u-free"].get("kills")))
    # reaparece a los pocos segundos
    for t in range(6, 60):
        h.tick(t)
        if h.py(h.state)["players"][objetivo].get("dead") is False:
            break
    check("freestylers: el entrenado vuelve al combate",
          h.py(h.state)["players"][objetivo].get("dead") is False, "sigue caido")


def scenario_calle():
    print("\n[la calle: pandillas, sueltos y amigos]")
    h = Harness()
    a = h.presence("u-calle", "Calle")
    h.init(); h.join(a)
    h.tick(2)
    estado = h.py(h.state)
    lados = {}
    for uid, p in estado["players"].items():
        if p.get("bot"):
            lados.setdefault(p.get("side"), []).append(uid)
    check("hay pandilla en cualquier sala", len(lados.get("pandilla", [])) >= 2, str(lados))
    check("hay uno que va por libre", len(lados.get("solo", [])) == 1, str(lados.get("solo")))
    check("hay buena gente reclutable para repartir", len(lados.get("amigo", [])) == 3,
          str(lados.get("amigo")))
    check("la pandilla tiene nombre propio", bool(estado.get("gang_name")), str(estado.get("gang_name")))
    check("salta el aviso de que se acercan", len(h.ops(87)) >= 1, str(len(h.ops(87))))
    # se les puede disparar
    objetivo = lados["pandilla"][0]
    h.tick(3, msgs=[(85, a, {"user_id": objetivo, "damage": 100})])
    estado = h.py(h.state)
    check("un pandillero cae de un disparo certero", estado["players"][objetivo].get("dead") is True)
    # y el amigo acepta la amistad si estas cerca
    amigo = lados["amigo"][0]
    estado = h.py(h.state)
    estado["players"]["u-calle"]["pos"] = dict(estado["players"][amigo]["pos"])
    h.state["players"]["u-calle"]["pos"] = h.lua.table(**estado["players"]["u-calle"]["pos"])
    h.tick(4, msgs=[(88, a, {"user_id": amigo})])
    estado = h.py(h.state)
    check("hacerte amigo funciona", estado["players"][amigo].get("friend") is True,
          str(estado["players"][amigo].get("friend")))
    check("se confirma la amistad", len(h.ops(89)) >= 1, str(len(h.ops(89))))


def destino(pres):
    """user_id del jugador que recibe el mensaje (send_one envia una lista de un elemento)."""
    try:
        if pres is None:
            return None
        if hasattr(pres, "keys") and 1 in list(pres.keys()):
            dentro = pres[1]
            if dentro is not None:
                return str(dentro["user_id"])
        if hasattr(pres, "keys"):
            return str(pres["user_id"])
    except Exception:
        return None
    return None


def pegar(h, uid, objetivo_uid):
    """Pone al jugador uid justo encima de otro jugador/bot (para poder hablarle)."""
    p = h.py(h.state["players"][objetivo_uid]["pos"])
    h.state["players"][uid]["pos"] = h.lua.table(x=p["x"], y=p.get("y", 0.0), z=p["z"])


def scenario_aliados():
    print("\n[aliados: un dueno por bot, maximo 3, y solo hablan a su dueno]")
    h = Harness()
    u1 = h.presence("u1", "Uno"); u2 = h.presence("u2", "Dos")
    h.init(); h.join(u1, u2)
    h.tick(2)
    estado = h.py(h.state)
    amigos = sorted(uid for uid, p in estado["players"].items() if p.get("side") == "amigo")
    check("hay 3 candidatos", len(amigos) == 3, str(amigos))
    nombres = {estado["players"][a]["username"] for a in amigos}
    check("los candidatos tienen nombres distintos", len(nombres) == 3, str(nombres))
    check("ninguno empieza con dueno",
          all(not estado["players"][a].get("owner") for a in amigos), str(amigos))

    # U1 recluta al primero
    primero = amigos[0]
    pegar(h, "u1", primero)
    h.sent.clear()
    h.tick(3, msgs=[(88, u1, {"user_id": primero})])
    estado = h.py(h.state)
    check("reclutar funciona", estado["players"][primero].get("friend") is True)
    check("el aliado sabe quien es su dueno", estado["players"][primero].get("owner") == "u1",
          str(estado["players"][primero].get("owner")))
    check("se confirma con el total de aliados", any(p.get("total") == 1 for p in h.ops(89)),
          str(h.ops(89)))

    # U2 no puede robarlo
    pegar(h, "u2", primero)
    h.sent.clear()
    h.tick(4, msgs=[(88, u2, {"user_id": primero})])
    estado = h.py(h.state)
    check("nadie roba el aliado de otro", estado["players"][primero].get("owner") == "u1",
          str(estado["players"][primero].get("owner")))
    check("al que intenta robarlo se le avisa", any("otro jugador" in str(p.get("text", ""))
          for p in h.ops(OP["TEAM_ALERT"])), str(h.ops(OP["TEAM_ALERT"])))

    # El aliado solo le habla a su dueno. La sala tiene un presupuesto de charla por
    # segundo (3 frases); en el test se limpia para no depender de quien hablo antes.
    charla = []
    for t in (5, 6, 7):
        h.state["say_win"] = h.lua.table(t0=0, n=0)
        h.sent.clear()
        h.tick(t, msgs=[(88, u1, {"user_id": primero})])
        charla = [(p, pres) for o, p, pres in h.sent if o == 93 and p.get("user_id") == primero]
        if charla:
            break
    check("el aliado habla al reclutarlo", len(charla) >= 1, str(len(charla)))
    destinos = [destino(pres) for _, pres in charla]
    check("solo se lo dice a su dueno", len(destinos) >= 1 and all(d == "u1" for d in destinos),
          str(destinos))
    check("el otro jugador no recibe el mensaje", all(d != "u2" for d in destinos), str(destinos))

    # U1 llega a 3 aliados
    for extra in amigos[1:]:
        pegar(h, "u1", extra)
        h.tick(9, msgs=[(88, u1, {"user_id": extra})])
    estado = h.py(h.state)
    de_u1 = [a for a in amigos if estado["players"][a].get("owner") == "u1"]
    check("un jugador puede llevar 3 aliados", len(de_u1) == 3, str(de_u1))

    # Un cuarto candidato (se convierte un pandillero en buena gente) es rechazado
    otros = [uid for uid, p in estado["players"].items()
             if p.get("bot") and p.get("side") == "pandilla"]
    if otros:
        cuarto = otros[0]
        h.state["players"][cuarto]["side"] = "amigo"
        h.state["players"][cuarto]["friend"] = False
        h.state["players"][cuarto]["owner"] = None
        pegar(h, "u1", cuarto)
        h.sent.clear()
        h.tick(10, msgs=[(88, u1, {"user_id": cuarto})])
        estado = h.py(h.state)
        check("el cuarto aliado se rechaza", estado["players"][cuarto].get("friend") is not True,
              str(estado["players"][cuarto].get("friend")))
        check("se explica el tope de 3", any("3 aliados" in str(p.get("text", ""))
              for p in h.ops(OP["TEAM_ALERT"])), str(h.ops(OP["TEAM_ALERT"])))

    # Si el aliado cae, queda libre para volver a reclutarlo
    h.sent.clear()
    h.tick(11, msgs=[(85, u1, {"user_id": primero, "damage": 999})])
    estado = h.py(h.state)
    check("el aliado derribado queda libre",
          estado["players"][primero].get("dead") is True
          and not estado["players"][primero].get("friend")
          and not estado["players"][primero].get("owner"),
          str(estado["players"][primero]))

    pandilleros = [uid for uid, p in h.py(h.state)["players"].items()
                   if p.get("side") == "pandilla" and not p.get("dead")]

    # Ninguna frase de un bot se reparte a dos jugadores distintos. Antes la charla
    # salia a todos los que pasaban cerca (te llegaba charla de bots que no eran tu equipo).
    if pandilleros:
        pegar(h, "u2", pandilleros[0])   # a distancia de charla, no al otro lado del mapa
    dichos = {}
    for t in range(12, 60):
        h.clock += 2          # el reloj del servidor avanza: los bots vuelven a hablar
        h.sent.clear()
        h.tick(t, msgs=[(85, u2, {"user_id": pandilleros[0] if pandilleros else primero, "damage": 1})])
        for o, p, pres in h.sent:
            if o == 93:
                clave = (str(p.get("user_id", "")), str(p.get("text", "")))
                dichos.setdefault(clave, set()).add(destino(pres))
        if len(dichos) >= 3:
            break
    repetidos = {k: v for k, v in dichos.items() if len(v) > 1}
    check("ninguna frase de bot se manda a dos jugadores", not repetidos, str(list(repetidos.items())[:2]))
    check("los bots siguen hablando", len(dichos) > 0, str(len(dichos)))


def scenario_basic_flow():
    print("\n[flujo basico: oleada, dano, recompensa]")
    h = Harness()
    a = h.presence("a", "Ana")
    h.init(); h.join(a)
    h.start_wave()
    waves = h.ops(OP["WAVE_STATE"])
    check("arranca la oleada 1", any(w.get("event") == "wave_started" for w in waves))
    started = next(w for w in waves if w.get("event") == "wave_started")
    check("oleada normal sin anuncio", started["kind"] == "normal")
    h.tick(msgs=[(OP["SPAWN"], a, {"pos": {"x": 0, "y": 1, "z": 0}})])
    check("spawn aceptado", len(h.ops(OP["SPAWN_OK"])) == 1)
    enemy = started["enemies"][0]
    h.tick(msgs=[(OP["DAMAGE"], a, {"enemy_id": enemy["id"], "damage": 40})])
    check("dano parcial emite vida restante", len(h.ops(OP["ENEMY_HEALTH"])) >= 1)
    h.tick(msgs=[(OP["DAMAGE"], a, {"enemy_id": enemy["id"], "damage": 9999})])
    check("dano absurdo rechazado", any(p.get("reason") == "absurd_damage" for p in h.ops(OP["ERROR"])))


def scenario_opcode_collision():
    print("\n[el estado de posicion ya no mata al jugador]")
    h = Harness()
    a = h.presence("a", "Ana"); b = h.presence("b", "Beto")
    h.init(); h.join(a, b)
    h.start_wave()
    h.tick(msgs=[(OP["SPAWN"], a, {"pos": {"x": 0, "y": 1, "z": 0}}),
                 (OP["SPAWN"], b, {"pos": {"x": 2, "y": 1, "z": 0}})])
    h.sent.clear()
    for _ in range(5):
        h.tick(msgs=[(OP["PLAYER_STATE"], a, {"pos": {"x": 1, "y": 1, "z": 1}, "yaw": 0.5})])
    check("mandar posicion no genera muertes", len(h.ops(OP["PLAYER_DEATH"])) == 0)
    check("mandar posicion no cierra la partida", len(h.ops(OP["MATCH_CLOSE"])) == 0)


def scenario_down_and_revive():
    print("\n[derribo, aviso al equipo y revivir]")
    h = Harness()
    a = h.presence("a", "Ana"); b = h.presence("b", "Beto")
    h.init(); h.join(a, b)
    h.start_wave()
    h.tick(msgs=[(OP["SPAWN"], a, {"pos": {"x": 0, "y": 1, "z": 0}}),
                 (OP["SPAWN"], b, {"pos": {"x": 2, "y": 1, "z": 0}})])
    h.sent.clear()
    h.tick(msgs=[(OP["DEATH"], a, {"pos": {"x": 0, "y": 1, "z": 0}, "cause": "monster"})])
    alerts = h.ops(OP["TEAM_ALERT"])
    down = [x for x in alerts if x.get("kind") == "player_down"]
    check("aviso de jugador caido a todo el equipo", len(down) == 1)
    check("el aviso incluye nombre y posicion", down and down[0]["username"] == "Ana" and "pos" in down[0])
    check("indica que se puede revivir", down and down[0]["can_revive"] is True)
    check("un caido no cierra la partida si queda otro vivo", len(h.ops(OP["MATCH_CLOSE"])) == 0)
    h.sent.clear()
    h.tick(msgs=[(OP["REVIVE"], b, {"target_id": "a", "medic_pos": {"x": 1, "y": 1, "z": 0},
                                    "target_pos": {"x": 0, "y": 1, "z": 0}})])
    check("revivir cercano funciona", len(h.ops(OP["REVIVE_OK"])) == 1)
    check("aviso de que vuelve a la pelea", any(x.get("kind") == "revived" for x in h.ops(OP["TEAM_ALERT"])))
    h.sent.clear()
    h.tick(msgs=[(OP["DEATH"], a, {"pos": {"x": 0, "y": 1, "z": 0}})])
    h.clock += 1
    h.tick(msgs=[(OP["REVIVE"], b, {"target_id": "a", "medic_pos": {"x": 40, "y": 1, "z": 40},
                                    "target_pos": {"x": 0, "y": 1, "z": 0}})])
    check("revivir desde lejos se rechaza", any(p.get("reason") in ("too_far", "cooldown")
                                              for p in h.ops(OP["REVIVE_REJECT"])))


def scenario_bleedout():
    print("\n[desangrado]")
    h = Harness()
    a = h.presence("a", "Ana"); b = h.presence("b", "Beto")
    h.init(); h.join(a, b)
    h.start_wave()
    h.tick(msgs=[(OP["SPAWN"], a, {"pos": {"x": 0, "y": 1, "z": 0}}),
                 (OP["SPAWN"], b, {"pos": {"x": 2, "y": 1, "z": 0}})])
    h.tick(msgs=[(OP["DEATH"], a, {"pos": {"x": 0, "y": 1, "z": 0}})])
    h.sent.clear()
    h.clock += 50
    h.tick()
    check("tras 45 s se avisa que se desangro", any(x.get("kind") == "player_lost" for x in h.ops(OP["TEAM_ALERT"])))
    h.sent.clear()
    h.tick(msgs=[(OP["REVIVE"], b, {"target_id": "a", "medic_pos": {"x": 1, "y": 1, "z": 0},
                                    "target_pos": {"x": 0, "y": 1, "z": 0}})])
    check("ya no se puede revivir a quien se desangro", any(p.get("reason") == "bled_out"
                                                          for p in h.ops(OP["REVIVE_REJECT"])))


def scenario_help():
    print("\n[llamada de ayuda y pings]")
    h = Harness()
    a = h.presence("a", "Ana"); b = h.presence("b", "Beto")
    h.init(); h.join(a, b)
    h.start_wave()
    h.tick(msgs=[(OP["SPAWN"], a, {"pos": {"x": 0, "y": 1, "z": 0}})])
    h.sent.clear()
    h.tick(msgs=[(OP["HELP_CALL"], a, {"reason": "monster", "pos": {"x": 3, "y": 1, "z": 3}})])
    al = [x for x in h.ops(OP["TEAM_ALERT"]) if x.get("kind") == "help"]
    check("la ayuda llega al equipo con nombre y posicion", al and al[0]["username"] == "Ana" and "pos" in al[0])
    check("monstruo = severidad maxima", al and al[0]["severity"] == 3)
    h.sent.clear()
    h.tick(msgs=[(OP["HELP_CALL"], a, {"reason": "help"})])
    check("spam de ayuda bloqueado por cooldown", any(p.get("reason") == "help_cooldown" for p in h.ops(OP["ERROR"])))
    h.sent.clear()
    h.tick(msgs=[(OP["PING"], a, {"pos": {"x": 5, "y": 1, "z": 5}, "kind": "danger"})])
    check("ping visible para el equipo", len(h.ops(OP["PING"])) == 1)
    h.sent.clear()
    h.tick(msgs=[(OP["PING"], a, {"pos": {"x": 999, "y": 1, "z": 5}})])
    check("ping fuera del mapa se ignora", len(h.ops(OP["PING"])) == 0)


def scenario_strong_waves():
    print("\n[oleadas fuertes: elite, horda, jefe]")
    h = Harness()
    a = h.presence("a", "Ana")
    h.init(); h.join(a)
    h.tick(msgs=[(OP["SPAWN"], a, {"pos": {"x": 0, "y": 1, "z": 0}})])
    kinds = {}
    for wave in range(1, 7):
        h.state.wave = wave - 1
        h.state.phase = "break"
        h.state.break_ends_at = 0
        h.sent.clear()
        h.tick(tick=wave)
        ws = [w for w in h.ops(OP["WAVE_STATE"]) if w.get("event") == "wave_started"]
        if ws:
            kinds[wave] = ws[0]
            for e in list(h.state.enemies.values()):
                e.dead = True
            h.state.enemies = h.lua.table()
            h.state.phase = "break"
    check("oleada 3 es de elites", kinds.get(3, {}).get("kind") == "elite")
    check("oleada 4 es horda", kinds.get(4, {}).get("kind") == "horde")
    check("oleada 5 es jefe", kinds.get(5, {}).get("kind") == "boss")
    check("la horda trae mas enemigos que la anterior", kinds[4]["enemy_count"] > kinds[2]["enemy_count"])
    boss_enemies = kinds[5]["enemies"]
    check("el jefe existe y tiene mucha mas vida", any(e.get("boss") for e in boss_enemies) and
          max(e["max_hp"] for e in boss_enemies) > 1000)


def scenario_modes():
    print("\n[modos de juego]")
    h = Harness()
    a = h.presence("a", "Ana"); b = h.presence("b", "Beto")
    h.init("survival"); h.join(a, b)
    h.start_wave()
    h.tick(msgs=[(OP["SPAWN"], a, {"pos": {"x": 0, "y": 1, "z": 0}}),
                 (OP["SPAWN"], b, {"pos": {"x": 2, "y": 1, "z": 0}})])
    h.tick(msgs=[(OP["DEATH"], a, {"pos": {"x": 0, "y": 1, "z": 0}})])
    d = h.ops(OP["PLAYER_DEATH"])
    check("en supervivencia no se puede revivir", d and d[0]["can_revive"] is False)
    h.sent.clear()
    h.tick(msgs=[(OP["REVIVE"], b, {"target_id": "a", "medic_pos": {"x": 1, "y": 1, "z": 0},
                                    "target_pos": {"x": 0, "y": 1, "z": 0}})])
    check("revivir rechazado por el modo", any(p.get("reason") == "mode_no_revive" for p in h.ops(OP["REVIVE_REJECT"])))
    hh = Harness()
    hh.init("horde"); n_horde = hh.py(hh.state)["mode"]
    check("el modo horda se reconoce", n_horde == "horde")


def scenario_final_stats():
    print("\n[estadisticas finales para logros]")
    h = T_h = Harness()
    h.init("coop_waves")
    a, b = h.presence("ua", "Ana"), h.presence("ub", "Beto")
    h.join(a, b)
    for p in (a, b):
        h.tick(msgs=[(OP["SPAWN"], p, {"pos": {"x": 0, "y": 1, "z": 0}})])
    h.start_wave()
    # Ana mata un enemigo normal; despues cae Beto, Ana lo levanta y Beto pide ayuda
    enemy_id = next(iter(h.py(h.state.enemies)))
    h.tick(msgs=[(OP["DAMAGE"], a, {"enemy_id": enemy_id, "damage": 1000, "pos": {"x": 0, "y": 1, "z": 0}})])
    h.tick(msgs=[(OP["DEATH"], b, {"pos": {"x": 1, "y": 1, "z": 0}, "cause": "monster"})])
    h.clock += 9
    h.tick(msgs=[(OP["REVIVE"], a, {"target_id": "ub", "medic_pos": {"x": 1, "y": 1, "z": 0}, "target_pos": {"x": 1, "y": 1, "z": 0}})])
    h.clock += 5
    h.tick(msgs=[(OP["HELP_CALL"], b, {"reason": "help", "pos": {"x": 1, "y": 1, "z": 0}})])
    h.sent.clear()
    h.tick(msgs=[(OP["MATCH_CLOSE"], a, {"force": False}), (OP["MATCH_CLOSE"], b, {})])
    res = h.ops(OP["MATCH_RESULT"])
    check("al cerrar se envia un resultado con bloque stats", bool(res) and "stats" in res[0])
    stats = {x["user_id"]: x for x in res[0]["stats"]} if res else {}
    check("Ana: 1 kill y 1 revive", stats.get("ua", {}).get("p_kills") == 1 and stats.get("ua", {}).get("p_revives") == 1)
    check("Beto: 1 derribo y 1 peticion de ayuda", stats.get("ub", {}).get("p_downed") == 1 and stats.get("ub", {}).get("p_help_calls") == 1)
    check("las claves coinciden con record_match_result", set(stats.get("ua", {})) >= {
        "p_kills", "p_elite_kills", "p_boss_kills", "p_revives", "p_downed", "p_help_calls", "p_wave", "p_won", "p_seconds"})


def scenario_capacity():
    print("\n[aforo de sala]")
    def accepted(setup, tries):
        h = Harness()
        state, _, _ = h.M.match_init(h.lua.table(), h.lua.table(**setup))
        h.state = state
        n = 0
        for i in range(tries):
            p = h.presence(f"c{i}")
            _s, ok, *_ = h.M.match_join_attempt(h.lua.table(), h.dispatcher, 1, h.state, p, h.lua.table())
            if ok:
                h.join(p)
                n += 1
        return n
    check("aforo por defecto = 20", accepted({}, 30) == 20)
    check("sala configurada a 8 jugadores", accepted({"max_players": 8}, 12) == 8)
    check("el techo duro limita a 40 aunque se pida 500", accepted({"max_players": 500}, 60) == 40)
    check("el minimo es 1 jugador", accepted({"max_players": 0}, 5) == 1)


def scenario_matchmaker():
    print("\n[emparejador: un modo por sala]")
    created = []
    h = Harness()
    h.lua.globals().nk.match_create = lambda name, setup: created.append(h.py(setup)) or f"match-{len(created)}"

    def user(i, mode, via="props"):
        pres = h.lua.table(user_id=f"u{i}", session_id=f"s{i}", username=f"U{i}")
        if via == "props":
            return h.lua.table(presence=pres, string_properties=h.lua.table(mode=mode))
        return h.lua.table(presence=pres, query=f"+properties.mode:{mode}")

    for mode in ("coop_waves", "survival", "horde", "boss_rush"):
        created.clear()
        mid = h.M.matchmaker_matched(h.lua.table(), h.lua.table_from([user(1, mode), user(2, mode)]))
        check(f"el modo {mode} crea su propia sala", bool(mid) and created and created[0]["mode"] == mode)
    created.clear()
    h.M.matchmaker_matched(h.lua.table(), h.lua.table_from([user(1, "horde", "query"), user(2, "horde", "query")]))
    check("el modo tambien se reconoce por la query", created and created[0]["mode"] == "horde")
    created.clear()
    h.M.matchmaker_matched(h.lua.table(), h.lua.table_from([user(1, "survival"), user(2, "survival"), user(3, "horde")]))
    check("grupo mixto: gana el modo con mas jugadores", created and created[0]["mode"] == "survival")
    check("grupo mixto: no se pierde a nadie del modo ganador", created and len(created[0]["invited"]) == 2)
    created.clear()
    h.M.matchmaker_matched(h.lua.table(), h.lua.table_from([user(1, "modo_inventado")]))
    check("un modo desconocido cae a oleadas, sin romper", created and created[0]["mode"] == "coop_waves")
    created.clear()
    h.M.matchmaker_matched(h.lua.table(), h.lua.table_from([user(i, "coop_waves") for i in range(30)]))
    check("30 jugadores emparejados: la sala admite a todos (aforo 30)", created and created[0]["max_players"] == 30)
    created.clear()
    h.M.matchmaker_matched(h.lua.table(), h.lua.table_from([user(i, "coop_waves") for i in range(60)]))
    check("60 emparejados: aforo topado al techo duro de 40", created and created[0]["max_players"] == 40)
    check("el emparejador no revienta con lista vacia", h.M.matchmaker_matched(h.lua.table(), h.lua.table()) is None)


def scenario_join_or_create():
    print("\n[RPC join_or_create: salas publicas]")
    h = Harness()
    made = []
    h.lua.globals().nk.match_create = lambda name, setup: made.append(h.py(setup)) or f"nueva-{len(made)}"

    def room(mid, mode, size, mx=20, open_=True, humans=None, age=600, mapa="recycling_plant"):
        # age: segundos desde que nacio la sala (las viejas de bots no deben reutilizarse)
        # misma hora que ve el Lua del servidor (el arnes la simula)
        _ahora = int(h.lua.eval("os.time")())
        label = json.dumps({"mode": mode, "open": open_, "max": mx,
                            "players": size if humans is None else humans,
                            "map": mapa, "t": _ahora - age})
        return h.lua.table(match_id=mid, size=size, label=label)

    def call(mode, private=False):
        out = h.M.rpc_join_or_create(h.lua.table(), json.dumps({"mode": mode, "private": private}))
        return json.loads(out)

    h.listed = h.lua.table_from([])
    r = call("coop_waves")
    check("sin salas: crea una nueva", r["created"] is True and r["match_id"] == "nueva-1")
    check("la sala nueva nace con el modo pedido", made[-1]["mode"] == "coop_waves")
    h.listed = h.lua.table_from([room("a", "coop_waves", 5), room("b", "coop_waves", 12), room("c", "horde", 15)])
    r = call("coop_waves")
    check("con salas abiertas: entra en la mas llena del modo", r["created"] is False and r["match_id"] == "b")
    r = call("horde")
    check("respeta el modo: horda entra en la de horda", r["match_id"] == "c")
    h.listed = h.lua.table_from([room("a", "coop_waves", 20), room("b", "coop_waves", 8, open_=False)])
    r = call("coop_waves")
    check("sala llena o cerrada: se crea otra", r["created"] is True)
    h.listed = h.lua.table_from([room("a", "coop_waves", 5)])
    r = call("coop_waves", private=True)
    check("una sala privada nunca se mezcla con las publicas", r["created"] is True and made[-1]["private"] is True)
    r = call("modo_raro")
    check("modo desconocido cae a oleadas", r["mode"] == "coop_waves")
    # Regresion: una sala recien creada (0 jugadores conectados) debe reutilizarse;
    # antes min_size=1 la ignoraba y dos jugadores acababan en salas distintas.
    h.listed = h.lua.table_from([room("nueva", "coop_waves", 0, humans=0, age=2)])
    out = json.loads(h.M.rpc_join_or_create(h.lua.table(), json.dumps({"mode": "coop_waves", "private": False})))
    check("reutiliza la sala vacia recien creada", out["match_id"] == "nueva" and out["created"] is False, str(out))
    h.listed = h.lua.table_from([room("botera", "coop_waves", 3, humans=0, age=900)])
    out = json.loads(h.M.rpc_join_or_create(h.lua.table(), json.dumps({"mode": "coop_waves"})))
    check("no entra en una sala vieja llena de bots", out["created"] is True, str(out))
    # si pides un mapa y la unica sala con gente es de otro mapa, se crea una del tuyo
    h.listed = h.lua.table_from([room("defecto", "coop_waves", 6)])
    out = json.loads(h.M.rpc_join_or_create(h.lua.table(), json.dumps({"mode": "coop_waves", "map": "mapa_x"})))
    check("no te mete en la sala de otro mapa", out["created"] is True, str(out))
    # el mapa manda: si hay sala con gente en tu mapa, entras ahi
    h.listed = h.lua.table_from([room("otro_mapa", "coop_waves", 9, mapa="otro"),
                                 room("mi_mapa", "coop_waves", 2, mapa="mapa_x")])
    out = json.loads(h.M.rpc_join_or_create(h.lua.table(), json.dumps({"mode": "coop_waves", "map": "mapa_x"})))
    check("prefiere la sala de tu mapa", out["created"] is False, str(out))
    out = json.loads(h.M.rpc_join_or_create(h.lua.table(), ""))
    check("payload vacio no revienta", out["mode"] == "coop_waves")
    out = json.loads(h.M.rpc_join_or_create(h.lua.table(), "esto no es json"))
    check("payload corrupto no revienta", out["mode"] == "coop_waves")


def scenario_position_relay():
    """El servidor debe reenviar el movimiento de cada jugador al resto del equipo.

    Sin esto el juego online 'funciona' pero no se ve moverse a nadie: era el bug
    que dejaba a los jugadores clavados en el punto de aparicion de los demas.
    """
    print("\n[reenvio de posiciones]")
    h = Harness()
    a = h.presence("a", "Ana")
    b = h.presence("b", "Beto")
    h.init(); h.join(a, b)
    h.sent.clear()
    h.tick(msgs=[(OP["PLAYER_STATE"], a, {"pos": {"x": 3, "y": 1, "z": 4}, "rot": 1.5})])
    relay = [(cuerpo, destinos) for op, cuerpo, destinos in h.sent if op == OP["PLAYER_STATE"]]
    check("el movimiento se reenvia al equipo", len(relay) == 1, str(relay))
    if relay:
        cuerpo, destinos = relay[0]
        destinos_py = h.py(destinos) or []
        if isinstance(destinos_py, dict): destinos_py = [destinos_py]
        destinatarios = [pr["user_id"] for pr in destinos_py]
        check("llega al companero (no a uno mismo)", destinatarios == ["b"], str(destinatarios))
        pos = cuerpo.get("pos") or {}
        check("conserva la posicion enviada", pos.get("x") == 3 and pos.get("z") == 4, str(cuerpo))
        check("dice quien se movio", cuerpo.get("user_id") == "a", str(cuerpo))
    h.sent.clear()
    h.tick(msgs=[(OP["PLAYER_STATE"], a, {"pos": {"x": 999, "y": 1, "z": 999}})])
    check("no reenvia posiciones fuera del mapa", len(h.ops(OP["PLAYER_STATE"])) == 0)
    h.tick(msgs=[(OP["PLAYER_STATE"], a, {"p": [1, 0, 2]})])
    check("acepta el formato corto p=[x,y,z]", len(h.ops(OP["PLAYER_STATE"])) == 1)


def scenario_handshake_multiplayer():
    """El cliente NakamaMultiplayerBridge solo arranca la partida si recibe el handshake.

    Necesita dos mensajes del op 9001: uno del host (type 0) y otro con su peer id
    (type 1). Sin ellos la sala se creaba pero el juego se quedaba en "creado".
    """
    print("\n[handshake del cliente]")
    h = Harness()
    a = h.presence("a", "Ana")
    b = h.presence("b", "Beto")
    h.init()
    h.sent.clear()
    h.join(a)
    meta_a = [(cuerpo, destinos) for op, cuerpo, destinos in h.sent if op == 9001]
    tipos_a = [c.get("type") for c, _ in meta_a]
    check("el primero recibe 'soy host' y su peer id", tipos_a[:2] == [0, 1], str(tipos_a))
    if len(meta_a) >= 2:
        check("el host queda con peer id 1", meta_a[1][0].get("peer_id") == 1, str(meta_a[1][0]))
    h.sent.clear()
    h.join(b)
    meta_b = [(cuerpo, destinos) for op, cuerpo, destinos in h.sent if op == 9001]
    asignados_b = [c.get("peer_id") for c, _destinos in meta_b
                   if c.get("type") == 1 and c.get("session_id") == "s-b"]
    check("el segundo recibe un peer id distinto de 1",
          bool(asignados_b) and asignados_b[-1] != 1, str(asignados_b))
    check("el host se entera del peer nuevo", any(c.get("type") == 1 for c, _ in meta_b))
    check("nadie queda sin 'soy host'", any(c.get("type") == 0 for c, _ in meta_b))


def scenario_wipe():
    print("\n[fin de partida]")
    h = Harness()
    a = h.presence("a", "Ana")
    h.init(); h.join(a)
    h.start_wave()
    h.tick(msgs=[(OP["SPAWN"], a, {"pos": {"x": 0, "y": 1, "z": 0}})])
    h.sent.clear()
    h.tick(msgs=[(OP["DEATH"], a, {"pos": {"x": 0, "y": 1, "z": 0}})])
    check("si todos caen se cierra la partida", len(h.ops(OP["MATCH_CLOSE"])) >= 1)
    check("se envia el resultado final", len(h.ops(OP["MATCH_RESULT"])) == 1)


if __name__ == "__main__":
    for fn in (scenario_basic_flow, scenario_opcode_collision, scenario_down_and_revive, scenario_bleedout,
               scenario_help, scenario_strong_waves, scenario_modes, scenario_final_stats, scenario_capacity, scenario_matchmaker, scenario_join_or_create, scenario_position_relay, scenario_handshake_multiplayer, scenario_wipe, scenario_freestylers, scenario_calle, scenario_aliados):
        try:
            fn()
        except Exception as exc:  # una excepcion en un escenario cuenta como fallo
            failed += 1
            print(f"  EXCEPCION en {fn.__name__}: {type(exc).__name__}: {exc}")
    print(f"\n{passed} correctas, {failed} fallidas")
    sys.exit(1 if failed else 0)


def scenario_voice():
    """Chat de voz: el servidor decide quien oye a quien."""
    print("\n== chat de voz ==")
    h = Harness()
    a = h.presence("u-a", "A"); b = h.presence("u-b", "B"); c = h.presence("u-c", "C")
    h.init(); h.join(a, b, c); h.tick(3)
    h.tick(4, msgs=[(70, a, {"pos": {"x": 0, "y": 1, "z": 0}, "rot": 0}),
                    (70, b, {"pos": {"x": 6, "y": 1, "z": 0}, "rot": 0}),
                    (70, c, {"pos": {"x": 30, "y": 1, "z": 0}, "rot": 0})])

    def oyentes():
        gente = set()
        for op, payload, target in h.sent:
            if op == 92:
                for pr in (h._to_py(target) or []):
                    if isinstance(pr, dict):
                        gente.add(pr.get("user_id"))
        return gente

    h.sent.clear()
    h.tick(5, msgs=[(92, a, {"channel": "prox", "data": "AAAA"})])
    cerca = oyentes()
    print("   proximidad ->", sorted(cerca))
    check("la voz de proximidad llega al de al lado", "u-b" in cerca)
    check("la voz de proximidad no llega al que esta lejos", "u-c" not in cerca)
    check("la voz no se devuelve al que habla", "u-a" not in cerca)

    h.sent.clear()
    h.tick(6, msgs=[(92, a, {"channel": "all", "data": "BBBB"})])
    todos = oyentes()
    print("   todos ->", sorted(todos))
    check("el canal todos llega a los dos", {"u-b", "u-c"} <= todos)

    h.sent.clear()
    h.tick(7, msgs=[(92, a, {"channel": "team", "data": "CCCC"})])
    equipo = oyentes()
    print("   equipo ->", sorted(equipo))
    check("el canal equipo llega a los companeros de equipo", {"u-b"} <= equipo, f"oyentes={sorted(equipo)}")

    h.sent.clear()
    h.tick(8, msgs=[(92, a, {"channel": "prox", "data": ""})])
    check("la voz vacia se ignora", not h.sent)

    h.sent.clear()
    for _ in range(70):
        h.tick(9, msgs=[(92, a, {"channel": "all", "data": "DDDD"})])
    relayados = len([1 for op, _, _ in h.sent if op == 92])
    check("el limite de ritmo corta la inundacion", relayados <= 61, f"relayados={relayados}")
