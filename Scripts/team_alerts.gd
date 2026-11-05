extends CanvasLayer
## Avisos de equipo en partida: jugador caido, peticiones de ayuda, oleadas fuertes
## y marcadores. Escucha al servidor autoritativo (OnlineManager) y lo muestra con
## el estilo del juego: banner por severidad + flecha hacia quien necesita ayuda.
##
## Teclas (acciones del Input Map): `help_call` pide ayuda, `ping_mark` marca un punto.

const BANNER_SECONDS := 4.5
const MAX_BANNERS := 4
const ARROW_SECONDS := 12.0
const SEVERITY_COLORS := [
	Color(0.85, 0.85, 0.9),     # 0 info
	Color(0.55, 0.9, 0.55),     # 1 bien (revivido)
	Color(1.0, 0.72, 0.25),     # 2 atencion
	Color(1.0, 0.25, 0.2),      # 3 urgente
]

var _banners: VBoxContainer
var _arrows: Dictionary = {}       # user_id -> {node, pos, expires}
var _pings: Array = []             # {node, pos, expires}
var _down: Dictionary = {}         # user_id -> Vector3
var _player: Node3D
var _amigo_id: String = ""          # el bueno que tienes cerca y con el que puedes hablar
var _amigo_hasta: float = 0.0
var _f_guard: float = 0.0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_banners = VBoxContainer.new()
	_banners.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banners.offset_left = -330.0
	_banners.offset_right = 330.0
	_banners.offset_top = 90.0
	_banners.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banners.add_theme_constant_override("separation", 6)
	add_child(_banners)
	OnlineManager.team_alert_received.connect(_on_team_alert)
	OnlineManager.ping_received.connect(_on_ping)
	OnlineManager.player_down_changed.connect(_on_player_down_changed)
	OnlineManager.revive_result.connect(_on_revive_result)
	OnlineManager.reward_received.connect(_on_reward)
	OnlineManager.gang_alert_received.connect(_on_gang_alert)
	OnlineManager.amistad_hecha.connect(_on_amistad)


func _process(_delta: float) -> void:
	# En el menu, en el lobby y en partidas sin marcadores no hay nada que colocar:
	# se sale antes de pedir el jugador y la camara (eran dos busquedas por frame).
	if _arrows.is_empty() and _pings.is_empty() and _amigo_id == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _amigo_id != "" and now > _amigo_hasta:
		_amigo_id = ""
	if _amigo_id != "" and Input.is_key_pressed(KEY_F) and now > _f_guard:
		_f_guard = now + 1.5
		OnlineManager.report_befriend(_amigo_id)
		_amigo_id = ""
	_player = get_tree().get_first_node_in_group("player") as Node3D
	var camera := get_viewport().get_camera_3d()
	for id in _arrows.keys():
		var arrow: Dictionary = _arrows[id]
		if now >= arrow.expires or not is_instance_valid(arrow.node):
			_remove_marker(arrow)
			_arrows.erase(id)
			continue
		_place_marker(arrow, camera)
	for i in range(_pings.size() - 1, -1, -1):
		var ping: Dictionary = _pings[i]
		if now >= ping.expires or not is_instance_valid(ping.node):
			_remove_marker(ping)
			_pings.remove_at(i)
			continue
		_place_marker(ping, camera)


func _unhandled_input(event: InputEvent) -> void:
	if not OnlineManager.is_in_match():
		return
	if event.is_action_pressed("help_call"):
		_send_help()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ping_mark"):
		_send_ping()
		get_viewport().set_input_as_handled()


# --- salida: lo que el jugador manda al equipo -------------------------------
func _send_help() -> void:
	if _player == null:
		return
	var reason := "help"
	if "health" in _player and "MAX_HEALTH" in _player and int(_player.MAX_HEALTH) > 0:
		if float(_player.health) / float(_player.MAX_HEALTH) <= 0.3:
			reason = "low_hp"
	if _nearest_enemy_distance() < 9.0:
		reason = "monster"
	OnlineManager.call_for_help(reason, _player.global_position)
	_show_banner("Pediste ayuda al equipo.", 1)


func _send_ping() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z) * 120.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit.position if not hit.is_empty() else to
	OnlineManager.send_ping("here", target)


func _nearest_enemy_distance() -> float:
	var best := 9999.0
	if _player == null:
		return best
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is Node3D:
			best = minf(best, _player.global_position.distance_to(enemy.global_position))
	return best


# --- entrada: lo que el servidor avisa ---------------------------------------
## La calle: pandillas que se acercan, el que va por libre y buena gente que te habla.
func _on_gang_alert(datos: Dictionary) -> void:
	var kind := str(datos.get("kind", ""))
	var nombre := str(datos.get("nombre", "")).strip_edges()
	var dist := int(datos.get("dist", 0))
	match kind:
		"pandilla":
			var banda := str(datos.get("gang", "LA PANDILLA")).to_upper()
			var cuantos := int(datos.get("count", 3))
			var texto := "SE ACERCAN LOS PANDILLEROS · %s (%d) · %dm" % [banda, cuantos, dist]
			_show_banner(texto, 3)
			GameChat.show_system_message(texto)
		"solo":
			var texto2 := "OJO: %s va por libre y viene a por ti" % nombre
			_show_banner(texto2, 2)
			GameChat.show_system_message(texto2)
		"amigo":
			var texto3 := "%s quiere hablar contigo · pulsa F" % nombre
			_show_banner(texto3, 1)
			_amigo_id = str(datos.get("user_id", ""))
			_amigo_hasta = Time.get_ticks_msec() / 1000.0 + 12.0


func _on_amistad(nombre: String, total: int) -> void:
	var texto := "%s ahora es tu amigo (amigos: %d)" % [nombre, total]
	_show_banner(texto, 1)
	GameChat.show_system_message(texto)


func _on_team_alert(alert: Dictionary) -> void:
	var severity := clampi(int(alert.get("severity", 0)), 0, 3)
	var text := str(alert.get("text", "")).strip_edges()
	if text.is_empty():
		return
	_show_banner(text, severity)
	GameChat.show_system_message(text)
	var kind := str(alert.get("kind", ""))
	var pos = alert.get("pos", null)
	if pos is Dictionary and (kind == "player_down" or kind == "help"):
		var uid := str(alert.get("user_id", ""))
		if uid != OnlineManager.get_local_user_id():
			_add_arrow(uid, _to_vec3(pos), severity)
	elif kind == "revived" or kind == "player_lost":
		_clear_arrow(str(alert.get("user_id", "")))


func _on_ping(ping: Dictionary) -> void:
	var pos = ping.get("pos", null)
	if not pos is Dictionary:
		return
	var marker := _make_marker(str(ping.get("username", "")), Color(0.4, 0.8, 1.0))
	add_child(marker)
	_pings.append({"node": marker, "pos": _to_vec3(pos), "expires": Time.get_ticks_msec() / 1000.0 + 8.0})


func _on_player_down_changed(user_id: String, is_down: bool, info: Dictionary) -> void:
	if is_down:
		var pos = info.get("pos", null)
		if pos is Dictionary:
			_down[user_id] = _to_vec3(pos)
	else:
		_down.erase(user_id)
		_clear_arrow(user_id)


func _on_revive_result(ok: bool, info: Dictionary) -> void:
	if ok:
		return
	var reasons := {
		"too_far": "Acercate mas para levantarlo.",
		"cooldown": "Espera un momento antes de volver a revivir.",
		"bled_out": "Ya es tarde: se desangro.",
		"mode_no_revive": "En este modo no se puede revivir.",
		"medic_dead": "Estas caido, no puedes revivir.",
	}
	_show_banner(str(reasons.get(str(info.get("reason", "")), "No se pudo revivir.")), 2)


func _on_reward(reward: Dictionary) -> void:
	if str(reward.get("reason", "")) != "wave_clear":
		return
	for entry in reward.get("rewards", []):
		if entry is Dictionary and str(entry.get("user_id", "")) == OnlineManager.get_local_user_id():
			_show_banner("Oleada superada  +%d" % int(entry.get("amount", 0)), 1)


# --- dibujo ------------------------------------------------------------------
func _show_banner(text: String, severity: int) -> void:
	var color: Color = SEVERITY_COLORS[clampi(severity, 0, 3)]
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.02, 0.025, 0.9)
	style.border_color = color
	style.set_border_width_all(2)
	style.border_width_left = 8
	style.set_corner_radius_all(2)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 22 if severity >= 3 else 19)
	label.add_theme_color_override("font_color", color.lightened(0.25))
	panel.add_child(label)
	_banners.add_child(panel)
	while _banners.get_child_count() > MAX_BANNERS:
		_banners.get_child(0).queue_free()
		_banners.remove_child(_banners.get_child(0))
	var tween := create_tween()
	tween.tween_interval(BANNER_SECONDS)
	tween.tween_property(panel, "modulate:a", 0.0, 0.6)
	tween.tween_callback(panel.queue_free)


func _add_arrow(user_id: String, pos: Vector3, severity: int) -> void:
	_clear_arrow(user_id)
	var color: Color = SEVERITY_COLORS[clampi(severity, 0, 3)]
	var marker := _make_marker("", color)
	add_child(marker)
	_arrows[user_id] = {"node": marker, "pos": pos, "expires": Time.get_ticks_msec() / 1000.0 + ARROW_SECONDS}


func _clear_arrow(user_id: String) -> void:
	if _arrows.has(user_id):
		_remove_marker(_arrows[user_id])
		_arrows.erase(user_id)


func _make_marker(label_text: String, color: Color) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = Vector2(120, 56)
	var arrow := Label.new()
	arrow.name = "Arrow"
	arrow.text = "◆"
	arrow.add_theme_font_size_override("font_size", 30)
	arrow.add_theme_color_override("font_color", color)
	arrow.position = Vector2(46, 0)
	root.add_child(arrow)
	var distance := Label.new()
	distance.name = "Distance"
	distance.add_theme_font_size_override("font_size", 15)
	distance.add_theme_color_override("font_color", color.lightened(0.3))
	distance.position = Vector2(0, 32)
	distance.size = Vector2(120, 20)
	distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(distance)
	root.set_meta("name_text", label_text)
	return root


func _place_marker(marker: Dictionary, camera: Camera3D) -> void:
	var node: Control = marker.node
	if camera == null or _player == null:
		node.visible = false
		return
	var pos: Vector3 = marker.pos + Vector3(0, 1.6, 0)
	var viewport_size := get_viewport().get_visible_rect().size
	var behind := camera.is_position_behind(pos)
	var screen := camera.unproject_position(pos)
	var margin := 60.0
	var clamped := Vector2(
		clampf(screen.x, margin, viewport_size.x - margin),
		clampf(screen.y, margin, viewport_size.y - margin))
	if behind:
		clamped.y = viewport_size.y - margin
		clamped.x = viewport_size.x - clamped.x
	node.visible = true
	node.position = clamped - node.size * 0.5
	var distance_label := node.get_node_or_null("Distance") as Label
	if distance_label != null:
		var meters := _player.global_position.distance_to(marker.pos)
		var prefix := str(node.get_meta("name_text", ""))
		distance_label.text = ("%s %dm" % [prefix, roundi(meters)]).strip_edges()


func _remove_marker(marker: Dictionary) -> void:
	if marker.has("node") and is_instance_valid(marker.node):
		marker.node.queue_free()


func _to_vec3(d: Dictionary) -> Vector3:
	return Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
