extends Node

# This manager keeps public connection data in the player's local settings.
# Never put a database password, service key, or Supabase secret in this file.
const CONFIG_PATH := "user://online.cfg"

signal status_changed(message: String)
signal authenticated
signal match_ready(match_id: String)
signal connection_failed(message: String)
signal voice_signal_received(sender_session_id: String, payload: Dictionary)
## Audio de voz ya comprimido (mu-law en base64) que reenvia el servidor.
signal voice_frame_received(sender_session_id: String, channel: String, data_b64: String)
signal player_state_received(sender_session_id: String, world_position: Vector3, yaw: float, display_name: String)
signal player_left(sender_session_id: String)
## Aviso del servidor para todo el equipo (jugador caido, ayuda, oleada fuerte...).
signal team_alert_received(alert: Dictionary)
## Un bot del servidor dice algo (texto ya armado, ya filtrado por distancia).
signal bot_dijo(nombre: String, texto: String, rol: String)
signal ping_received(ping: Dictionary)
signal wave_state_received(state: Dictionary)
## Codigo corto de la sala en la que estas (para decirselo a un amigo). Vacio si no hay.
signal room_code_changed(code: String)
## Posiciones de los bots a 10 Hz (lista de {id,x,y,z,yaw,a}).
signal bot_positions_received(lista: Array)
signal reward_received(reward: Dictionary)
signal match_result_received(result: Dictionary)
signal revive_result(ok: bool, info: Dictionary)
signal player_down_changed(user_id: String, is_down: bool, info: Dictionary)
signal entrenado_hit_received(damage: int, from: Vector3, nombre: String)
## Duelo: golpe, baja o reaparicion que decide el servidor (kind: hit | kill | respawn).
signal duel_event_received(evento: Dictionary)
signal entrenado_cayo(nombre: String)
## Un bot del servidor disparo: posicion de su arma, a quien apuntaba y si dio. Sirve para oirlo y verlo.
signal entrenado_disparo(desde: Vector3, objetivo_id: String, acerto: bool, nombre: String)
## Aviso de la calle: se acerca una pandilla, viene uno por libre o alguien quiere hablar.
signal gang_alert_received(datos: Dictionary)
signal amistad_hecha(nombre: String, total: int)

# Reservado para señalizacion de voz; no colisiona con los codigos 9001/9002
# que utiliza NakamaMultiplayerBridge internamente.
const VOICE_SIGNAL_OP_CODE := 4100

## Estado del personaje (posicion + orientacion + nombre) para que los demas
## jugadores vean tu cuerpo en la arena. Era 20, que el servidor autoritativo usa
## para "este jugador murio": cada paquete de posicion marcaba al jugador como muerto.
## 70 esta libre y no colisiona con voz (4100) ni con NakamaMultiplayerBridge (9001/9002).
const PLAYER_STATE_OP_CODE := 70

## Protocolo del servidor autoritativo (infra/nakama/modules/match_coop.lua).
const OP_DEATH := 20
const OP_PLAYER_DEATH := 21
const OP_REVIVE := 30
const OP_REVIVE_OK := 31
const OP_REVIVE_REJECT := 32
const OP_REWARD := 40
const OP_WAVE_STATE := 50
const OP_MATCH_STATE := 60
const OP_HELP_CALL := 80
const OP_ENTRENADO_HIT := 83
const OP_ENTRENADO_SHOT := 84
const OP_GANG_ALERT := 87
const OP_BOT_SAY := 93
const OP_BEFRIEND := 88
const OP_BEFRIEND_OK := 89
const OP_HIT_BOT := 85
const OP_BOT_DEATH := 86
const OP_TEAM_ALERT := 81
const OP_PING := 82
const OP_MATCH_RESULT := 91
const OP_VOICE := 92
const OP_BOT_POS := 94
const OP_HIT_PLAYER := 95
const OP_DUEL_EVENT := 96
const PLAYER_STATE_HZ := 12.0

var host := "boomershooter.onrender.com"
var port := 443
var scheme := "https"
## Clave del cliente. NO se escribe aqui: la inyecta la compilacion en
## res://online_defaults.cfg (tools/write_online_defaults.sh, variable CI enmascarada).
## Sin ese archivo queda vacia y el juego no intenta conectar (en vez de mandar una clave
## inventada). Un repo publico no puede llevar la clave del servidor.
## Codigo de 5 caracteres de la sala actual y si es privada.
var room_code: String = ""
var room_private: bool = false
var server_key := ""
const DEFAULT_USERNAME := "xpe.nettt"

var username := ""

var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket
## Sala activa. Antes lo guardaba NakamaMultiplayerBridge; ahora el cliente habla directo
## con el servidor autoritativo (join_match + op codes) y no hay peers de Godot de por medio.
var match_id: String = ""
## Skin que lleva cada jugador de la sala (clave = user_id/session_id), la manda el servidor.
var _skins_vistas: Dictionary = {}

func skin_de(clave: String) -> String:
	return str(_skins_vistas.get(clave, ""))
var _entrando_a: String = ""
## Mi propio session_id dentro de la sala (lo da el servidor al hacer join_match).
var _mi_session_en_sala: String = ""


func _ready() -> void:
	_load_config()


func configure(server_host: String, public_server_key: String, display_name: String = "", server_port: int = 443, server_scheme: String = "https") -> void:
	var cleaned_host := server_host.strip_edges().trim_prefix("https://").trim_prefix("http://").trim_suffix("/")
	host = cleaned_host if not cleaned_host.is_empty() else host
	server_key = public_server_key.strip_edges() if not public_server_key.strip_edges().is_empty() else server_key
	username = _clean_username(display_name)
	port = server_port
	scheme = server_scheme
	_save_config()


## Despierta el servidor si estaba dormido (el hosting gratuito lo duerme tras ~15 min sin uso y
## tarda 30-60 s en volver). Sin esto el primer jugador veia "servidores no disponibles".
## Devuelve true en cuanto el servidor responde.
func _despertar_servidor(max_segundos: float = 80.0) -> bool:
	var url := "%s://%s%s/healthcheck" % [scheme, host, "" if port in [80, 443] else ":%d" % port]
	var t0 := Time.get_ticks_msec()
	var intento := 0
	while (Time.get_ticks_msec() - t0) / 1000.0 < max_segundos:
		intento += 1
		var http := HTTPRequest.new()
		http.timeout = 12.0
		add_child(http)
		var err := http.request(url)
		if err == OK:
			var r = await http.request_completed
			http.queue_free()
			if int(r[0]) == HTTPRequest.RESULT_SUCCESS and int(r[1]) == 200:
				return true
		else:
			http.queue_free()
		var pasados := int((Time.get_ticks_msec() - t0) / 1000.0)
		if intento == 1 or intento % 2 == 0:
			status_changed.emit("Despertando el servidor... %d s (la primera vez tarda un poco)" % pasados)
		await get_tree().create_timer(2.5).timeout
	return false


func connect_device() -> bool:
	# Si el lobby ya conecto al listar salas, se reutiliza la sesion y el socket.
	if client != null and session != null and socket != null and socket.is_connected_to_host() and match_id.is_empty():
		return true
	if host.is_empty() or server_key.is_empty():
		_fail("El servicio online no esta configurado todavia.")
		return false
	status_changed.emit("Conectando al servicio online...")
	if not await _despertar_servidor():
		_fail("El servidor no responde ahora mismo. Revisa tu internet e intentalo en un minuto.")
		return false
	# Varios intentos: justo despues de despertar, el primero puede fallar aunque el servidor ya este arriba.
	for intento in 3:
		client = Nakama.create_client(server_key, host, port, scheme, 15, NakamaLogger.LOG_LEVEL.ERROR)
		session = await client.authenticate_device_async(Nakama.get_device_id(), username if not username.is_empty() else null, true)
		if session != null and not session.is_exception():
			break
		session = null
		if intento < 2:
			status_changed.emit("Reintentando conexion (%d/3)..." % (intento + 2))
			await get_tree().create_timer(3.0).timeout
	if session == null:
		_fail("No se pudo iniciar sesion en el servicio online. Comprueba que tu juego este actualizado.")
		return false
	var result = null
	for intento in 3:
		socket = Nakama.create_socket_from(client)
		result = await socket.connect_async(session, true, 15)
		if result != null and not result.is_exception():
			break
		if intento < 2:
			await get_tree().create_timer(2.5).timeout
	if result == null or result.is_exception():
		_fail("No se pudo abrir la conexion en tiempo real. Intentalo de nuevo en unos segundos.")
		return false
	socket.received_match_state.connect(_on_received_match_state)
	socket.closed.connect(_on_socket_closed)
	authenticated.emit()
	status_changed.emit("Conectado. Buscando escuadron...")
	return true


## Entra a una sala con join_match directo. Devuelve true solo cuando el servidor la acepta.
func _entrar_a_sala(id: String) -> bool:
	if socket == null or id.is_empty():
		return false
	_entrando_a = id
	var res = await socket.join_match_async(id)
	_entrando_a = ""
	if res == null or res.is_exception():
		_fail("No se pudo entrar a la sala. Intentalo otra vez.")
		return false
	match_id = id
	_mi_session_en_sala = str(res.self_user.session_id) if res.self_user != null else ""
	status_changed.emit("Partida encontrada. Entrando a la arena...")
	match_ready.emit(match_id)
	status_changed.emit("Sala conectada.")
	VoiceManager.begin_match()
	return true


func _on_socket_closed() -> void:
	if match_id.is_empty():
		return
	match_id = ""
	_mi_session_en_sala = ""
	_fail("Se perdio la conexion con la sala.")


## Modos que el servidor sabe crear (ver MODES en infra/nakama/modules/match_coop.lua).
const GAME_MODES := {
	"coop_waves": "Oleadas",
	"survival": "Supervivencia",
	"horde": "Horda",
	"boss_rush": "Jefes",
}
## Jugadores por sala al emparejar. Minimo 1: con 2 una persona sola esperaba sin limite.
const QUEUE_MIN_PLAYERS := 1
const QUEUE_MAX_PLAYERS := 20


func queue_for_mode(mode: String = "coop_waves") -> void:
	if socket == null:
		_fail("Preparando el servicio online. Intentalo de nuevo.")
		return
	if not GAME_MODES.has(mode):
		mode = "coop_waves"
	status_changed.emit("Buscando una partida de %s..." % GAME_MODES[mode])
	# El modo viaja como propiedad de texto Y en la query: el servidor lee ambas y solo
	# junta a jugadores que pidieron el mismo modo.
	var ticket = await socket.add_matchmaker_async(
		"+properties.mode:%s" % mode, QUEUE_MIN_PLAYERS, QUEUE_MAX_PLAYERS, {"mode": mode})
	if ticket == null or ticket.is_exception():
		_fail("No se pudo entrar a la cola. Intentalo otra vez.")
		return
	# El servidor responde al ticket con un match: se entra cuando llegue.
	var m = await socket.received_matchmaker_matched
	if m != null and m.match_id != "":
		await _entrar_a_sala(str(m.match_id))


## Sala publica: pide al servidor una sala abierta del modo (o la crea) y entra directamente.
## A diferencia de la cola de emparejamiento, NO exige 2 jugadores: una persona sola entra.
## El servidor reparte a los jugadores en salas de ~20, asi cientos de usuarios caben.
func play_public(mode: String = "coop_waves", private_room: bool = false) -> void:
	if socket == null or client == null:
		_fail("Preparando el servicio online. Intentalo de nuevo.")
		return
	if not GAME_MODES.has(mode):
		mode = "coop_waves"
	status_changed.emit("Buscando una sala de %s..." % GAME_MODES[mode])
	var reply = await client.rpc_async(session, "join_or_create", JSON.stringify({"mode": mode, "private": private_room}))
	if reply == null or reply.is_exception():
		# Servidor sin el RPC (version antigua): se cae a la cola clasica en vez de dejar al jugador sin partida.
		push_warning("join_or_create no disponible, usando la cola clasica")
		await queue_for_mode(mode)
		return
	var parsed = JSON.parse_string(reply.payload)
	if typeof(parsed) != TYPE_DICTIONARY or str(parsed.get("match_id", "")).is_empty():
		_fail("El servidor no devolvio una sala valida.")
		return
	await _entrar_a_sala(str(parsed["match_id"]))


## Compatibilidad: el boton "Partida rapida" sigue entrando a oleadas.
func queue_coop_waves() -> void:
	await queue_for_mode("coop_waves")


func quick_play(display_name: String, mode: String = "coop_waves") -> void:
	username = _clean_username(display_name)
	_save_config()
	if await connect_device():
		await play_public(mode)


## Lista de salas publicas para el lobby: mapa, modo, jugadores y bots.
## Devuelve Array[Dictionary] vacio si algo falla (el lobby muestra "sin salas").
func fetch_rooms(mode: String = "") -> Array:
	if client == null or session == null:
		if not await connect_device():
			return []
	var payload := {}
	if mode != "":
		payload["mode"] = mode
	var res = await client.rpc_async(session, "list_rooms", JSON.stringify(payload))
	if res == null or res.is_exception():
		return []
	var parsed = JSON.parse_string(res.payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	# Lua devuelve {} cuando esta vacio: puede llegar como diccionario, no como lista.
	var rooms = parsed.get("rooms", [])
	if typeof(rooms) == TYPE_ARRAY:
		return rooms
	var list: Array = []
	if typeof(rooms) == TYPE_DICTIONARY:
		for key in rooms:
			list.append(rooms[key])
	return list



## CREAR una sala nueva (nunca se mete en otra). Devuelve {ok, code, private, error}.
## privada = true: no sale en la lista, solo entra quien tenga el codigo.
func create_room(mode: String, map_id: String, privada: bool, nombre_sala: String = "", opciones: Dictionary = {}) -> Dictionary:
	if not await connect_device():
		return {"ok": false, "error": "Sin conexion con el servicio online."}
	var payload := {"mode": mode, "map": map_id, "private": privada, "bots": 3}
	# Opciones de sala (monstruos, bots, aforo): el servidor las valida y recorta.
	for k in ["monsters", "bots", "max_players"]:
		if opciones.has(k):
			payload[k] = opciones[k]
	if nombre_sala.strip_edges() != "":
		payload["name"] = nombre_sala.strip_edges()
	var reply = await client.rpc_async(session, "create_room", JSON.stringify(payload))
	if reply == null or reply.is_exception():
		return {"ok": false, "error": "No se pudo crear la sala. Intentalo otra vez."}
	var parsed = JSON.parse_string(reply.payload)
	if typeof(parsed) != TYPE_DICTIONARY or str(parsed.get("match_id", "")).is_empty():
		return {"ok": false, "error": "El servidor no devolvio una sala valida."}
	_guardar_sala(str(parsed.get("code", "")), bool(parsed.get("private", false)))
	_discord_partida(mode, map_id)
	status_changed.emit("Entrando a la sala %s..." % room_code)
	if not await _entrar_a_sala(str(parsed["match_id"])):
		return {"ok": false, "error": "No se pudo entrar a la sala creada."}
	return {"ok": true, "code": room_code, "private": room_private}


## UNIRSE a una sala que ya existe, con su codigo. Nunca crea nada. Devuelve {ok, error}.
func join_by_code(codigo: String) -> Dictionary:
	var limpio := codigo.to_upper().strip_edges()
	if limpio.length() < 5:
		return {"ok": false, "error": "El codigo tiene 5 caracteres."}
	if not await connect_device():
		return {"ok": false, "error": "Sin conexion con el servicio online."}
	var reply = await client.rpc_async(session, "join_room", JSON.stringify({"code": limpio}))
	if reply == null or reply.is_exception():
		return {"ok": false, "error": "No se pudo entrar. Intentalo otra vez."}
	var parsed = JSON.parse_string(reply.payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Respuesta invalida del servidor."}
	match str(parsed.get("error", "")):
		"code_invalid":
			return {"ok": false, "error": "Ese codigo no es valido. Son 5 letras o numeros."}
		"code_not_found":
			return {"ok": false, "error": "No existe ninguna sala con ese codigo."}
		"match_full":
			return {"ok": false, "error": "Esa sala esta llena."}
		"match_closed":
			return {"ok": false, "error": "Esa sala ya termino."}
	var target := str(parsed.get("match_id", ""))
	if target.is_empty():
		return {"ok": false, "error": "El servidor no devolvio una sala valida."}
	_guardar_sala(str(parsed.get("code", limpio)), bool(parsed.get("private", false)))
	_discord_partida(str(parsed.get("mode", "coop_waves")), str(parsed.get("map", "recycling_plant")))
	status_changed.emit("Entrando a la sala %s..." % room_code)
	if not await _entrar_a_sala(target):
		return {"ok": false, "error": "No se pudo entrar a la sala."}
	return {"ok": true, "code": room_code}


func _guardar_sala(codigo: String, privada: bool) -> void:
	room_code = codigo
	room_private = privada
	room_code_changed.emit(room_code)

## Entra a una sala concreta (la de un amigo) o crea una nueva con ese mapa y bots.
func join_room(match_id: String = "", mode: String = "coop_waves", map_id: String = "recycling_plant", bots: int = 3) -> bool:
	if not await connect_device():
		return false
	if client == null or session == null:
		_fail("Sin conexion con el servicio online.")
		return false
	var payload := {"mode": mode, "map": map_id, "bots": bots}
	if match_id != "":
		payload["match_id"] = match_id
	var reply = await client.rpc_async(session, "join_or_create", JSON.stringify(payload))
	if reply == null or reply.is_exception():
		_fail("No se pudo entrar a la sala. Intentalo otra vez.")
		return false
	var parsed = JSON.parse_string(reply.payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("Respuesta invalida del servidor.")
		return false
	_discord_partida(mode, map_id)
	if parsed.get("error", "") == "match_full":
		_fail("Esa sala esta llena. Prueba otra.")
		return false
	if parsed.get("error", "") == "match_not_found":
		_fail("Esa sala ya no existe.")
		return false
	var target := str(parsed.get("match_id", ""))
	if target.is_empty():
		_fail("El servidor no devolvio una sala valida.")
		return false
	status_changed.emit("Entrando a la sala...")
	return await _entrar_a_sala(target)


## Rich Presence de Discord: nunca debe poder romper el juego, asi que todo va protegido.
func _discord_partida(mode_id: String, map_id: String) -> void:
	var d = get_node_or_null("/root/DiscordPresence")
	if d != null and d.has_method("en_partida_id"):
		d.en_partida_id(mode_id, map_id, 1)


func _discord_menu() -> void:
	var d = get_node_or_null("/root/DiscordPresence")
	if d != null and d.has_method("menu"):
		d.menu()


func leave_online() -> void:
	room_code = ""
	room_private = false
	_discord_menu()
	if VoiceManager:
		VoiceManager.end_match()
	if socket and not match_id.is_empty():
		socket.leave_match_async(match_id)
	if socket:
		socket.close()
	match_id = ""
	_mi_session_en_sala = ""
	socket = null
	session = null
	client = null


func send_voice_signal(payload: Dictionary, recipients: Array = []) -> bool:
	if socket == null or match_id.is_empty():
		return false
	var encoded := JSON.stringify(payload)
	var result = await socket.send_match_state_async(match_id, VOICE_SIGNAL_OP_CODE, encoded, recipients)
	return result != null and not result.is_exception()


## Manda un paquete de voz (mu-law 8 kHz ya en base64). El servidor decide
## quien lo recibe segun el canal: "prox" (24 m), "team" o "all".
func send_voice_frame(channel: String, data_b64: String) -> void:
	if data_b64.is_empty():
		return
	await _send_op(OP_VOICE, {"channel": channel, "data": data_b64})


## True mientras haya una partida online activa con el servidor.
func is_in_match() -> bool:
	return socket != null and not match_id.is_empty()


func get_local_user_id() -> String:
	return str(session.user_id) if session != null else ""


func get_local_match_session_id() -> String:
	return _mi_session_en_sala


func _on_received_match_state(match_state) -> void:
	if match_id.is_empty() or match_state.match_id != match_id:
		return
	# El servidor autoritativo manda los mensajes sin remitente: sin este guardia
	# cada paquete de estado lanzaba un error y no se procesaba nada.
	var session_id := ""
	if match_state.presence != null:
		session_id = str(match_state.presence.session_id)
	if match_state.op_code == VOICE_SIGNAL_OP_CODE:
		var voice_json := JSON.new()
		if voice_json.parse(str(match_state.data)) != OK:
			return
		var voice_payload = voice_json.get_data()
		if voice_payload is Dictionary:
			voice_signal_received.emit(session_id, voice_payload)
		return
	if match_state.op_code == OP_VOICE:
		var voz := {}
		var crudo := str(match_state.data)
		if not crudo.is_empty():
			var parseado = JSON.parse_string(crudo)
			if parseado is Dictionary:
				voz = parseado
		if not voz.is_empty():
			voice_frame_received.emit(str(voz.get("from", session_id)), str(voz.get("channel", "prox")), str(voz.get("data", "")))
		return
	if match_state.op_code == PLAYER_STATE_OP_CODE:
		handle_player_state_payload(session_id, str(match_state.data))
		return
	handle_server_message(int(match_state.op_code), str(match_state.data))


## Decodifica los mensajes del servidor autoritativo y los reparte por senales.
## Separado del handler de red para poder probarlo sin un Nakama levantado.
func handle_server_message(op_code: int, raw_payload: String) -> void:
	var json := JSON.new()
	if json.parse(raw_payload) != OK:
		return
	var payload = json.get_data()
	if not payload is Dictionary:
		return
	match op_code:
		OP_TEAM_ALERT:
			team_alert_received.emit(payload)
		OP_GANG_ALERT:
			gang_alert_received.emit(payload)
		OP_BOT_SAY:
			bot_dijo.emit(str(payload.get("name", "")).left(24), str(payload.get("text", "")).left(200), str(payload.get("rol", "")))
		OP_BEFRIEND_OK:
			amistad_hecha.emit(str(payload.get("nombre", "")), int(payload.get("total", 0)))
		OP_BOT_DEATH:
			entrenado_cayo.emit(str(payload.get("name", "")))
		OP_ENTRENADO_SHOT:
			var pos = payload.get("pos", {})
			if pos is Dictionary:
				entrenado_disparo.emit(
					Vector3(float(pos.get("x", 0)), float(pos.get("y", 0)), float(pos.get("z", 0))),
					str(payload.get("target_user_id", "")), payload.get("hit", false) == true,
					str(payload.get("name", "")))
		OP_ENTRENADO_HIT:
			# Un jugador entrenado de la Sala de los Freestylers te acerto.
			var desde = payload.get("from", {})
			var punto := Vector3(float(desde.get("x", 0)), float(desde.get("y", 0)), float(desde.get("z", 0)))
			entrenado_hit_received.emit(int(payload.get("damage", 0)), punto, str(payload.get("name", "")))
		OP_DUEL_EVENT:
			duel_event_received.emit(payload)
		OP_PLAYER_DEATH:
			# El aviso para el jugador llega por OP_TEAM_ALERT (kind "player_down");
			# este mensaje solo sirve para actualizar quien esta caido.
			player_down_changed.emit(str(payload.get("user_id", "")), true, payload)
		OP_PING:
			ping_received.emit(payload)
		OP_BOT_POS:
			var lista = payload.get("b", [])
			if lista is Array:
				bot_positions_received.emit(lista)
		OP_WAVE_STATE, OP_MATCH_STATE:
			wave_state_received.emit(payload)
		OP_REWARD:
			reward_received.emit(payload)
		OP_MATCH_RESULT:
			match_result_received.emit(payload)
		OP_REVIVE_OK:
			player_down_changed.emit(str(payload.get("target_id", "")), false, payload)
			revive_result.emit(true, payload)
		OP_REVIVE_REJECT:
			revive_result.emit(false, payload)


## Decodifica el estado de un jugador remoto. Se separa del handler de red para
## poder probarlo sin un servidor Nakama levantado.
func handle_player_state_payload(session_id: String, raw_payload: String) -> void:
	var json := JSON.new()
	if json.parse(raw_payload) != OK:
		return
	var payload = json.get_data()
	if not payload is Dictionary:
		return
	# El servidor autoritativo reenvia {user_id, username, pos:{x,y,z}, rot} SIN remitente
	# (session_id vacio). El formato antiguo entre clientes era {p:[x,y,z], y, n}. Se aceptan
	# los dos y el jugador se identifica por user_id cuando no hay session_id.
	var quien := session_id
	if quien.is_empty():
		quien = str(payload.get("user_id", ""))
	if quien.is_empty() or quien == get_local_match_session_id() or quien == get_local_user_id():
		return
	var world_position := Vector3.ZERO
	var yaw := 0.0
	var packed = payload.get("p", null)
	if packed is Array and packed.size() >= 3:
		world_position = Vector3(float(packed[0]), float(packed[1]), float(packed[2]))
		yaw = float(payload.get("y", 0.0))
	else:
		var pos = payload.get("pos", null)
		if not pos is Dictionary:
			return
		world_position = Vector3(float(pos.get("x", 0)), float(pos.get("y", 0)), float(pos.get("z", 0)))
		yaw = float(payload.get("rot", payload.get("y", 0.0)))
	var display_name := str(payload.get("n", payload.get("username", ""))).strip_edges()
	var skin := str(payload.get("sk", payload.get("skin", "")))
	if skin != "":
		_skins_vistas[quien] = skin
	player_state_received.emit(quien, world_position, yaw, display_name)


func send_player_state(world_position: Vector3, yaw: float) -> void:
	if socket == null or match_id.is_empty():
		return
	var payload := {
		"n": username if not username.is_empty() else _clean_username(""),
		"sk": Shop.equipped,
		"p": [snappedf(world_position.x, 0.01), snappedf(world_position.y, 0.01), snappedf(world_position.z, 0.01)],
		"y": snappedf(yaw, 0.01),
		# formato que valida y reenvia el servidor autoritativo
		"pos": {"x": snappedf(world_position.x, 0.01), "y": snappedf(world_position.y, 0.01), "z": snappedf(world_position.z, 0.01)},
		"rot": snappedf(yaw, 0.01),
	}
	await socket.send_match_state_async(match_id, PLAYER_STATE_OP_CODE, JSON.stringify(payload))


## Pide ayuda al equipo. reason: help | monster | low_hp | no_ammo.
func call_for_help(reason: String, world_position: Vector3) -> void:
	await _send_op(OP_HELP_CALL, {"reason": reason, "pos": _vec(world_position)})


## Marca un punto en el mapa para el equipo. kind: here | danger | loot.
func send_ping(kind: String, world_position: Vector3) -> void:
	await _send_op(OP_PING, {"kind": kind, "pos": _vec(world_position)})


## Le diste a un jugador entrenado de la Sala de los Freestylers.
func report_entrenado_hit(entrenado_id: String, damage: int) -> void:
	if entrenado_id.is_empty():
		return
	await _send_op(OP_HIT_BOT, {"user_id": entrenado_id, "damage": damage})


## Duelo: le diste a otro jugador. El servidor valida distancia, pared y ritmo y decide el dano real.
func report_player_hit(target_user_id: String, damage: int) -> void:
	if target_user_id.is_empty():
		return
	await _send_op(OP_HIT_PLAYER, {"target_id": target_user_id, "damage": damage})


## Hacerse amigo de uno de los buenos (hay que estar cerca).
func report_befriend(bot_id: String) -> void:
	if bot_id.is_empty():
		return
	await _send_op(OP_BEFRIEND, {"user_id": bot_id})


func report_death(world_position: Vector3, cause: String) -> void:
	await _send_op(OP_DEATH, {"pos": _vec(world_position), "cause": cause})


func request_revive(target_user_id: String, medic_position: Vector3, target_position: Vector3) -> void:
	await _send_op(OP_REVIVE, {
		"target_id": target_user_id, "medic_pos": _vec(medic_position), "target_pos": _vec(target_position)})


func _send_op(op_code: int, payload: Dictionary) -> void:
	if socket == null or match_id.is_empty():
		return
	await socket.send_match_state_async(match_id, op_code, JSON.stringify(payload))


func _vec(v: Vector3) -> Dictionary:
	return {"x": snappedf(v.x, 0.01), "y": snappedf(v.y, 0.01), "z": snappedf(v.z, 0.01)}


func _fail(message: String) -> void:
	connection_failed.emit(message)
	status_changed.emit(message)


func _clean_username(value: String) -> String:
	var cleaned := value.strip_edges().replace(" ", "_")
	if cleaned.is_empty():
		# Nombre de combate por defecto del build; se puede cambiar en el lobby.
		return DEFAULT_USERNAME if not DEFAULT_USERNAME.is_empty() else "player_%s" % Nakama.get_device_id().substr(0, 6)
	return cleaned.left(24)


## Valores por defecto de red: los inyecta la compilacion en res://online_defaults.cfg
## (ver tools/write_online_defaults.sh). Antes el cliente llevaba "defaultkey", que el
## servidor rechaza con 401 "Server key invalid": el online nunca podia conectar.
const BUILD_DEFAULTS_PATH := "res://online_defaults.cfg"


func _load_config() -> void:
	var defaults := ConfigFile.new()
	if defaults.load(BUILD_DEFAULTS_PATH) == OK:
		host = str(defaults.get_value("nakama", "host", host))
		port = int(defaults.get_value("nakama", "port", port))
		scheme = str(defaults.get_value("nakama", "scheme", scheme))
		server_key = str(defaults.get_value("nakama", "server_key", server_key))
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		# La preferencia del jugador solo cambia el nombre. El servidor y su clave los fija
		# la compilacion: un online.cfg viejo con "defaultkey" ya no pisa la clave buena.
		username = str(config.get_value("nakama", "username", username))
	if username.strip_edges().is_empty():
		username = DEFAULT_USERNAME


func _save_config() -> void:
	var config := ConfigFile.new()
	# Solo el nombre: host y clave los fija la compilacion (BUILD_DEFAULTS_PATH).
	config.set_value("nakama", "username", username)
	config.save(CONFIG_PATH)
