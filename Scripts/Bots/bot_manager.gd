extends Node
## Director de bots. Reparte por el mapa:
##  - aliados reclutables sueltos (te siguen si te acercas y pulsas E),
##  - escuadrones enemigos de 3 o 4 y una pareja inseparable,
## y pinta en una esquina los nombres del equipo.

const BOT_SCENE := "res://Player/RemotePlayer.tscn"
## Tope de bots por partida: 5 (antes 13 entre reclutables y escuadras, y la partida se sentia
## llena de bots). 1 reclutable + un escuadron de 2 hostiles + una pareja inseparable = 5.
const MAX_BOTS := 5
const RECRUITABLES := 1
const SQUADS := [
	{"size": 2, "id": "alfa"},
	{"size": 2, "id": "pareja", "inseparable": true},
]
const MAX_ALLIES := 3
const PROMPT_DISTANCE := 4.2
const FLOOR_PROBE := 60.0

const NAMES := [
	"Xochitl", "Zuriñe", "Kwame_77", "Dagny", "Amaterasu", "Kalani",
	"Tzunun", "Nadezhda", "Ixchel", "Oluwaseun", "Saoirse", "Rafiq_88",
	"Nefertiti", "BaoLong", "Anahi_V", "Kaimana", "Sekhmet", "Yara_9",
	"Quetzal", "Tamarindo", "Aiko", "Esperanza_X", "Zubair", "Mihaela",
	"Ileana", "Obi_Nnamdi", "Sanjay_11", "Fatoumata", "Dmitri_V", "LuciaFuego",
]

var allies: Array[Bot] = []
var hostiles: Array[Bot] = []

var _spawned_scene: Node = null
var _escena_vista: Node = null     # ultima escena ya examinada (evita buscar cada frame)
var _used_names: Dictionary = {}
var _prompt: Label
var _roster: VBoxContainer
var _roster_panel: PanelContainer
var _nearby: Bot = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()


func _process(delta: float) -> void:
	_ensure_spawned()
	# Sin bots en pantalla (menus, lobby) no hay cartel ni lista que actualizar.
	if allies.is_empty() and hostiles.is_empty() and _spawned_scene == null:
		return
	_update_prompt()
	_update_roster()
	if Input.is_action_just_pressed("recruit") and _nearby != null:
		_recruit(_nearby)


# ---------- aparicion ----------
func _ensure_spawned() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene == _spawned_scene or scene == _escena_vista:
		return
	_escena_vista = scene
	# Solo en mapas jugables (tienen director de oleadas).
	if scene.find_child("Enemies", true, false) == null and not scene.is_in_group("arena"):
		return
	_spawned_scene = scene
	allies.clear()
	hostiles.clear()
	_used_names.clear()
	# Esperar a que el mapa tenga su suelo definitivo (fusion de mallas) antes de generar.
	var espera := 0.0
	while is_instance_valid(scene) and not scene.has_meta("mapa_listo") and espera < 3.0:
		await get_tree().create_timer(0.1).timeout
		espera += 0.1
	if not is_instance_valid(scene) or get_tree().current_scene != scene:
		_spawned_scene = null
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Durante esos dos frames el jugador pudo salir del mapa: la escena ya estaria liberada.
	if not is_instance_valid(scene) or get_tree() == null or get_tree().current_scene != scene:
		_spawned_scene = null
		return
	_spawn_all(scene)


func _spawn_all(scene: Node) -> void:
	# En una sala online el servidor autoritativo ya pone a los jugadores entrenados, iguales
	# para todos. Si ademas cada cliente generaba sus 9 bots locales, una sala con varias
	# personas se llenaba de cientos de bots y nadie veia lo mismo.
	if OnlineManager.is_in_match():
		print("[bots] sala online: sin bots locales, mandan los del servidor")
		return
	var player: Player = Global.player
	var origin: Vector3 = player.global_position if player != null else Vector3.ZERO
	var creados := 0
	for i in RECRUITABLES:
		if creados >= MAX_BOTS:
			break
		_spawn(scene, _scatter(origin, 12.0, 42.0), Bot.Mode.RECRUITABLE, "")
		creados += 1
	for squad in SQUADS:
		var squad_id: String = squad["id"]
		var centre := _scatter(origin, 28.0, 65.0)
		for k in int(squad["size"]):
			if creados >= MAX_BOTS:
				break
			creados += 1
			var b := _spawn(scene, centre + Vector3(cos(k * 1.7) * 2.2, 0, sin(k * 1.7) * 2.2), Bot.Mode.HOSTILE, squad_id)
			if b != null and squad.get("inseparable", false):
				b.is_inseparable = true


func _scatter(origin: Vector3, min_d: float, max_d: float) -> Vector3:
	var player: Player = Global.player
	if player == null:
		return origin
	for _try in 30:
		var a := randf() * TAU
		var d := randf_range(min_d, max_d)
		var p := origin + Vector3(cos(a) * d, 0, sin(a) * d)
		var snapped: Variant = _ground_below(p + Vector3(0, 12.0, 0))
		# A nivel de calle: el rayo cae desde arriba y un tejado tambien cuenta como
		# "suelo", asi que se descartan los puntos mas de 1.2 m por encima del jugador.
		if snapped != null and (snapped as Vector3).y <= origin.y + 1.2 and _suelo_firme(snapped as Vector3):
			return snapped as Vector3
	# Plan B: cerca del jugador, que SI esta sobre suelo. Antes se devolvia el origen
	# a ciegas o un punto sin comprobar y el bot nacia en el vacio.
	for _try in 20:
		var a2 := randf() * TAU
		var p2 := origin + Vector3(cos(a2) * 6.0, 0, sin(a2) * 6.0)
		var s2: Variant = _ground_below(p2 + Vector3(0, 6.0, 0))
		if s2 != null and (s2 as Vector3).y <= origin.y + 1.2:
			return s2 as Vector3
	return origin


## El punto es seguro si tambien hay suelo a su alrededor (no es el borde de un hueco).
func _suelo_firme(punto: Vector3) -> bool:
	for off in [Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5)]:
		var h: Variant = _ground_below(punto + off + Vector3(0, 3.0, 0))
		if h == null or absf((h as Vector3).y - punto.y) > 1.2:
			return false
	return true


## Baja un rayo hasta el suelo para que nunca aparezcan flotando ni dentro del mapa.
func _ground_below(from: Vector3) -> Variant:
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, FLOOR_PROBE, 0))
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	return (hit["position"] as Vector3) + Vector3(0, 0.1, 0)


func _spawn(scene: Node, at: Vector3, mode: int, squad: String) -> Bot:
	var scene_res: PackedScene = load(BOT_SCENE)
	if scene_res == null:
		return null
	# La escena base es un RemotePlayer: se le cambia el script ANTES de castear,
	# porque el nodo instanciado aun es RemotePlayer y el cast a Bot fallaria.
	var node: Node = scene_res.instantiate()
	node.set_script(load("res://Scripts/Bots/bot.gd"))
	var bot: Bot = node as Bot
	if bot == null:
		node.queue_free()
		return null
	var display := _unique_name()
	# Cada bot lleva una skin de la tienda, para que no se vean todos iguales.
	# Los aliados visten la skin que el jugador tiene equipada; los hostiles
	# llevan una cualquiera, para distinguirlos de un vistazo.
	var tint: Color
	if mode == Bot.Mode.ALLY:
		tint = Shop.equipped_color()
	else:
		var skin_pool: Array = Shop.SKINS
		var sk: Dictionary = skin_pool[randi() % skin_pool.size()]
		tint = sk["color"]
	if mode == Bot.Mode.HOSTILE:
		tint = tint.lerp(Color(1.0, 0.1, 0.1), 0.35)
	scene.add_child(bot)
	bot.global_position = at
	bot.setup_bot(display, tint, mode, squad)
	if mode == Bot.Mode.HOSTILE:
		bot.add_to_group("hostile_bot")
		hostiles.append(bot)
	return bot


func _unique_name() -> String:
	for _try in 60:
		var n: String = NAMES[randi() % NAMES.size()]
		if not _used_names.has(n):
			_used_names[n] = true
			return n
	return NAMES[randi() % NAMES.size()] + str(randi_range(10, 99))


# ---------- reclutar ----------
func _update_prompt() -> void:
	var player: Player = Global.player
	if player == null or _prompt == null:
		if _prompt:
			_prompt.visible = false
		return
	_nearby = null
	var best := PROMPT_DISTANCE
	for b in get_tree().get_nodes_in_group("bot"):
		if b is Bot and b.is_recruitable():
			var d: float = b.global_position.distance_to(player.global_position)
			if d < best:
				best = d
				_nearby = b
	var slot_full := allies.size() >= MAX_ALLIES
	if _nearby != null and not slot_full:
		_prompt.visible = true
		_prompt.text = "[E]  HACER AMIGO A  %s" % _nearby.display_name
	elif _nearby != null and slot_full:
		_prompt.visible = true
		_prompt.text = "EQUIPO COMPLETO  (%d/%d)" % [allies.size(), MAX_ALLIES]
	else:
		_prompt.visible = false


func _recruit(bot: Bot) -> void:
	if bot == null or allies.size() >= MAX_ALLIES:
		return
	bot.become_ally(allies.size())
	if OnlineManager and OnlineManager.username != "":
		bot.say("%s: Un placer, %s. Vamos a limpiar el mapa." % [bot.display_name, OnlineManager.username])
	allies.append(bot)
	bot.add_to_group("ally_bot")
	if _nearby == bot:
		_nearby = null


func leave_ally(bot: Bot) -> void:
	allies.erase(bot)
	bot.say("%s: Me piro, busca a otro. Buenas suerte." % bot.display_name)
	bot.become_hostile()


# ---------- HUD ----------
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)

	_prompt = Label.new()
	_prompt.visible = false
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-260, -170)
	_prompt.custom_minimum_size = Vector2(520, 30)
	layer.add_child(_prompt)

	_roster_panel = PanelContainer.new()
	_roster_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_roster_panel.position = Vector2(18, 88)
	_roster_panel.custom_minimum_size = Vector2(210, 0)
	_roster_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.03, 0.035, 0.72)
	style.border_color = Color(0.55, 0.12, 0.08, 0.9)
	style.set_border_width_all(2)
	style.content_margin_left = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_roster_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(_roster_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_roster_panel.add_child(box)
	var title := Label.new()
	title.text = "TU EQUIPO"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
	box.add_child(title)
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 1)
	box.add_child(_roster)


func _update_roster() -> void:
	if _roster == null:
		return
	allies = allies.filter(func(b): return is_instance_valid(b))
	var player: Player = Global.player
	_roster_panel.visible = player != null and not allies.is_empty()
	if not _roster_panel.visible:
		return
	if _roster.get_child_count() != allies.size() + 1:
		for c in _roster.get_children():
			c.queue_free()
		var me := Label.new()
		me.text = "· " + (OnlineManager.username if OnlineManager.username != "" else "TU")
		me.add_theme_font_size_override("font_size", 17)
		me.add_theme_color_override("font_color", Color(0.65, 0.95, 1.0))
		_roster.add_child(me)
		for b in allies:
			var l := Label.new()
			l.text = "· " + b.display_name
			l.add_theme_font_size_override("font_size", 16)
			l.add_theme_color_override("font_color", Color(0.8, 0.82, 0.85))
			_roster.add_child(l)
