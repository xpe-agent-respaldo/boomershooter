extends Node3D

## Replica el estado de los jugadores de la partida.
##
## Antes este script instanciaba un Player.tscn completo por cada peer: eso metia
## camaras y controles duplicados en la arena y ademas nadie veia al otro jugador.
## Ahora cada peer remoto es un RemotePlayer (avatar + nombre) y el transform viaja
## por mensajes de partida de Nakama (op 70). No hay peers ni rpc() de Godot: el servidor
## autoritativo es el unico que decide quien esta en la sala.

const REMOTE_PLAYER_SCENE := preload("res://Player/RemotePlayer.tscn")
## Si un jugador deja de enviar estado, se retira su avatar.
const STALE_SECONDS := 8.0

@onready var primary_player: Player = $Player1

var _remote: Dictionary = {}
var _last_seen: Dictionary = {}
var _state_timer: float = 0.0


func _ready() -> void:
	OnlineManager.player_state_received.connect(_on_player_state)
	OnlineManager.entrenado_hit_received.connect(_on_entrenado_hit)
	OnlineManager.wave_state_received.connect(_on_estado_partida)
	OnlineManager.bot_positions_received.connect(_on_posiciones_bots)
	OnlineManager.bot_dijo.connect(_on_bot_dijo)
	OnlineManager.entrenado_disparo.connect(_on_entrenado_disparo)
	OnlineManager.match_result_received.connect(_on_final_de_partida)


## Un bot del servidor dispara: se oye desde su posicion y se ve la traza hacia quien apunta.
## Sin esto el servidor quitaba vida y el cliente no mostraba ni sonaba nada.
func _on_entrenado_disparo(desde: Vector3, objetivo_id: String, acerto: bool, _nombre: String) -> void:
	var jugador: Player = Global.player
	var boca := desde + Vector3(0, 1.35, 0)
	var d := 0.0
	if jugador != null and is_instance_valid(jugador):
		d = jugador.global_position.distance_to(desde)
	if d > 60.0:
		return
	SfxArmas.sonar_en(self, ["rifle", "subfusil", "escopeta"][int(abs(hash(_nombre))) % 3], boca, -4.0 - d * 0.12, 60.0)
	# traza visible hacia el objetivo (si es el jugador local, hacia su pecho)
	var destino := boca + Vector3(0, 0, -8)
	if jugador != null and is_instance_valid(jugador) and objetivo_id == OnlineManager.get_local_user_id():
		destino = jugador.global_position + Vector3(0, 1.1, 0)
	elif jugador != null and is_instance_valid(jugador):
		destino = boca + (jugador.global_position + Vector3(0, 1.1, 0) - boca).normalized() * 12.0
	_traza(boca, destino, acerto)


func _traza(desde: Vector3, hasta: Vector3, acerto: bool) -> void:
	var largo := desde.distance_to(hasta)
	if largo < 0.5 or get_tree().current_scene == null:
		return
	var haz := MeshInstance3D.new()
	var cil := CylinderMesh.new()
	cil.top_radius = 0.02
	cil.bottom_radius = 0.02
	haz.mesh = cil
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.35) if acerto else Color(0.85, 0.85, 0.9, 0.7)
	haz.material_override = mat
	haz.add_to_group("traza_bot")
	get_tree().current_scene.add_child(haz)
	haz.global_position = (desde + hasta) * 0.5
	haz.look_at(hasta, Vector3.UP)
	haz.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	haz.scale = Vector3(1, largo, 1)
	get_tree().create_timer(0.06).timeout.connect(haz.queue_free)


## Lo que dicen los bots llega al chat de la partida. Si el chat no existe, no pasa nada.
func _on_bot_dijo(nombre: String, texto: String, rol: String) -> void:
	var chat = get_node_or_null("/root/GameChat")
	if chat != null and chat.has_method("receive_bot_message"):
		chat.receive_bot_message(nombre, texto, rol)


func _process(delta: float) -> void:
	_state_timer += delta
	var interval: float = 1.0 / maxf(1.0, OnlineManager.PLAYER_STATE_HZ)
	if _state_timer >= interval:
		_state_timer = 0.0
		_broadcast_local_state()
	_prune_stale(delta)


func _broadcast_local_state() -> void:
	if primary_player == null:
		return
	OnlineManager.send_player_state(primary_player.global_position, primary_player.rotation.y)


func _on_player_state(session_id: String, world_position: Vector3, yaw: float, display_name: String) -> void:
	# Uno mismo no se dibuja como remoto (el servidor reenvia al resto, no al emisor,
	# pero se comprueba por si acaso).
	if session_id == OnlineManager.get_local_match_session_id():
		return
	var remote: RemotePlayer = _remote.get(session_id)
	if remote == null:
		remote = REMOTE_PLAYER_SCENE.instantiate()
		remote.name = "Remote_%s" % session_id.substr(0, 8)
		add_child(remote)
		remote.setup(display_name, RemotePlayer.color_for(session_id), OnlineManager.skin_de(session_id))
		_remote[session_id] = remote
	elif not display_name.is_empty() and remote.display_name != display_name:
		remote.setup(display_name, RemotePlayer.color_for(session_id), OnlineManager.skin_de(session_id))
	_dar_cuerpo_de_duelo(remote, session_id)
	remote.push_transform(world_position, yaw)
	_last_seen[session_id] = 0.0


func _prune_stale(delta: float) -> void:
	for session_id in _last_seen.keys():
		_last_seen[session_id] = float(_last_seen[session_id]) + delta
		if float(_last_seen[session_id]) < STALE_SECONDS:
			continue
		_remove_remote(session_id)


## En un duelo los demas jugadores se pueden disparar: se les da un cuerpo de colision en la capa 4
## (la que mira el AimCast), con su user_id. Fuera del duelo no se anade: nadie puede danar a nadie.
func _dar_cuerpo_de_duelo(remote: Node3D, user_id: String) -> void:
	if remote == null or user_id.is_empty() or not DuelClient.es_duelo():
		return
	# Se reconcilia en cada llamada: el equipo puede llegar DESPUES de que aparezca el avatar. En
	# equipos los companeros no se apuntan ni danan (el servidor tampoco lo permite).
	var existente := remote.get_node_or_null("CuerpoDuelo")
	if not DuelClient.es_rival(user_id):
		if existente != null:
			remote.remove_child(existente)
			existente.queue_free()
		return
	if existente != null:
		return
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "CuerpoDuelo"
	cuerpo.collision_layer = 8
	cuerpo.collision_mask = 0
	cuerpo.add_to_group("rival_duelo")
	cuerpo.set_meta("rival_id", user_id)
	var forma := CollisionShape3D.new()
	var capsula := CapsuleShape3D.new()
	capsula.radius = 0.45
	capsula.height = 1.8
	forma.shape = capsula
	forma.position = Vector3(0, 0.9, 0)
	cuerpo.add_child(forma)
	remote.add_child(cuerpo)


func _remove_remote(session_id: String) -> void:
	var remote: Node = _remote.get(session_id)
	if remote != null and is_instance_valid(remote):
		remote.queue_free()
	_remote.erase(session_id)
	_last_seen.erase(session_id)


## Los jugadores humanos tambien viajan en el estado de partida del servidor (la fuente de
## verdad). Se dibujan desde aqui ademas de por el op 70: si un paquete de posicion se pierde,
## nadie desaparece ni se queda congelado.
func _sincronizar_humanos(lista: Array) -> void:
	var mi_user := OnlineManager.get_local_user_id()
	var presentes := {}
	for entrada in lista:
		if not entrada is Dictionary or bool(entrada.get("bot", false)):
			continue
		var uid := str(entrada.get("user_id", ""))
		if uid.is_empty() or uid == mi_user:
			continue
		var p = entrada.get("pos", {})
		if not p is Dictionary:
			continue
		presentes[uid] = true
		var destino := Vector3(float(p.get("x", 0)), float(p.get("y", 0)), float(p.get("z", 0)))
		var nombre := str(entrada.get("username", "Jugador"))
		var remote: RemotePlayer = _remote.get(uid)
		if remote == null:
			remote = REMOTE_PLAYER_SCENE.instantiate()
			remote.name = "Remote_%s" % uid.substr(0, 8)
			add_child(remote)
			remote.setup(nombre, RemotePlayer.color_for(uid), str(entrada.get("skin", "")))
			_remote[uid] = remote
		elif str(entrada.get("skin", "")) != "" and remote._skin_id != str(entrada.get("skin", "")):
			remote.set_skin(str(entrada.get("skin", "")), RemotePlayer.color_for(uid))
		remote.visible = bool(entrada.get("alive", true)) and not bool(entrada.get("dead", false))
		_dar_cuerpo_de_duelo(remote, uid)
		remote.push_transform(destino, float(entrada.get("yaw", remote.rotation.y)))
		_last_seen[uid] = 0.0
	# quien ya no esta en la lista (se fue de la sala) se retira
	for clave in _remote.keys():
		if str(clave).begins_with("entrenado_"):
			continue
		if not presentes.has(str(clave)):
			_remove_remote(clave)


## Daño que llega de un jugador entrenado (Sala de los Freestylers).
func _on_entrenado_hit(damage: int, from: Vector3, _nombre: String) -> void:
	if primary_player == null or damage <= 0:
		return
	primary_player.take_damage(damage, from)


## Los jugadores entrenados viajan en el estado de partida: se dibujan igual que
## un jugador humano (avatar y nombre), porque en el juego son jugadores.
func _on_estado_partida(estado: Dictionary) -> void:
	var lista = estado.get("players", [])
	if not lista is Array:
		return
	var vistos := {}
	_sincronizar_humanos(lista)
	for entrada in lista:
		if not entrada is Dictionary or not bool(entrada.get("bot", false)):
			continue
		var uid := str(entrada.get("user_id", ""))
		if uid.is_empty():
			continue
		var clave := "entrenado_" + uid
		vistos[clave] = true
		var p = entrada.get("pos", {})
		var destino := Vector3(float(p.get("x", 0)), float(p.get("y", 0)), float(p.get("z", 0)))
		var remote: RemotePlayer = _remote.get(clave)
		if remote == null:
			remote = REMOTE_PLAYER_SCENE.instantiate()
			remote.name = "Entrenado_" + uid
			add_child(remote)
			# Quien es quien se ve de un vistazo: pandilla en rojo con su nombre de banda,
			# el que va por libre en naranja y los buenos en verde (y si ya es tu amigo, se nota).
			var lado := str(entrada.get("side", "entrenado"))
			var etiqueta := str(entrada.get("username", "Jugador"))
			var tinte := RemotePlayer.color_for(clave)
			match lado:
				"pandilla":
					etiqueta = "[%s] %s" % [str(entrada.get("gang", "PANDILLA")).to_upper(), etiqueta]
					tinte = Color(0.95, 0.22, 0.18)
				"solo":
					etiqueta = "[POR LIBRE] " + etiqueta
					tinte = Color(1.0, 0.6, 0.15)
				"amigo":
					if bool(entrada.get("friend", false)):
						etiqueta = "[TU AMIGO] " + etiqueta
						tinte = Color(0.4, 1.0, 0.55)
					else:
						etiqueta = "[BUENA GENTE] " + etiqueta
						tinte = Color(0.35, 0.85, 0.55)
			remote.setup(etiqueta, tinte, str(entrada.get("skin", "")))
			# cuerpo de colision propio de la capa 4 (la que mira el AimCast del jugador):
			# asi se les puede disparar como a cualquier otro, que es lo que son.
			var cuerpo := StaticBody3D.new()
			cuerpo.collision_layer = 8
			cuerpo.collision_mask = 0
			cuerpo.add_to_group("entrenado")
			cuerpo.set_meta("entrenado_id", uid)
			var forma := CollisionShape3D.new()
			var capsula := CapsuleShape3D.new()
			capsula.radius = 0.45
			capsula.height = 1.8
			forma.shape = capsula
			forma.position = Vector3(0, 0.9, 0)
			cuerpo.add_child(forma)
			remote.add_child(cuerpo)
			_remote[clave] = remote
		remote.visible = bool(entrada.get("alive", true))
		remote.push_transform(destino, float(entrada.get("yaw", 0.0)))
		_last_seen[clave] = 0.0
	for clave in _remote.keys():
		if str(clave).begins_with("entrenado_") and not vistos.has(clave):
			_remote[clave].queue_free()
			_remote.erase(clave)
			_last_seen.erase(clave)


## Posiciones de los bots a 10 Hz: mueven a los avatares que el snapshot (1 Hz) ya creo. Sin esto
## los bots daban un salto por segundo y parecian estatuas.
func _on_posiciones_bots(lista: Array) -> void:
	for e in lista:
		if not e is Dictionary:
			continue
		var clave := "entrenado_" + str(e.get("id", ""))
		var remote: RemotePlayer = _remote.get(clave)
		if remote == null:
			continue
		remote.visible = int(e.get("a", 1)) == 1
		remote.push_transform(Vector3(float(e.get("x", 0)), float(e.get("y", 0)), float(e.get("z", 0))), float(e.get("yaw", 0)))
		_last_seen[clave] = 0.0


## El servidor termino la partida (victoria, derrota o fin de duelo): se cuenta que paso y se
## deja volver al lobby. Antes este resultado llegaba y nadie lo mostraba.
var _final_mostrado := false

func _on_final_de_partida(resultado: Dictionary) -> void:
	if _final_mostrado:
		return
	_final_mostrado = true
	var pantalla := EndScreen.new()
	add_child(pantalla)
	pantalla.mostrar(resultado, OnlineManager.get_local_user_id())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pantalla.salir_pulsado.connect(_volver_al_lobby)


func _volver_al_lobby() -> void:
	get_tree().paused = false
	OnlineManager.leave_online()
	LobbyAudio.change_scene(get_tree(), "res://Levels/Lobby.tscn")
