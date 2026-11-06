extends Control
## Lobby online. Mismo lenguaje visual que el menu principal (UIKit):
## izquierda eliges modo y mapa, derecha ves el mapa y el estado.

const BACKDROP := "res://Assets/Images/menu_bg.png"
const MODES := [
	{"id": "coop_waves", "name": "OLEADAS", "desc": "Aguanta oleadas con elites, hordas y jefes cada pocas rondas."},
	{"id": "survival", "name": "SUPERVIVENCIA", "desc": "Sin descanso. Cuanto mas duras, mas puntos."},
	{"id": "horde", "name": "HORDA", "desc": "Enjambres masivos de enemigos. Dispara sin parar."},
	{"id": "boss_rush", "name": "JEFES", "desc": "Un jefe tras otro. Sin enemigos menores."},
	{"id": "freestylers", "name": "FREESTYLERS", "desc": "Sala de los Freestylers: puro enfrentamiento contra jugadores entrenados. Sin monstruos."},
	{"id": "duelo", "name": "DUELO", "pvp": true, "desc": "Tu contra tus amigos. Sin monstruos ni bots: el primero en llegar a 15 bajas gana. Tab muestra el marcador."},
	{"id": "tdm", "name": "EQUIPOS", "pvp": true, "desc": "Rojo contra Azul. Cada baja suma al equipo: el primero en llegar a 50 gana. Sin fuego amigo."},
	{"id": "dominio", "name": "DOMINAR", "pvp": true, "desc": "Tres puntos que capturar quedandote 4 s en ellos sin rivales. Cada punto tuyo suma 1 por segundo: gana el primero en llegar a 200."},
	{"id": "caliente", "name": "PUNTO CALIENTE", "pvp": true, "desc": "Un solo punto activo que cambia de sitio cada 45 s. Solo suma quien lo ocupa sin rivales dentro. Gana el primero en llegar a 150."},
]
const MAPS := [
	{"id": "recycling_plant", "short": "RECICLAJE", "name": "PLANTA DE RECICLAJE", "level": "res://Levels/RecyclingPlant.tscn", "preview": "res://Assets/Maps/References/village_scenery_idea.png"},
	{"id": "storm_village", "short": "ALDEA", "name": "ALDEA DE LA TORMENTA", "level": "res://Levels/StormVillage.tscn", "preview": "res://Assets/Maps/References/2_fog_dwell_peaks.png"},
	{"id": "space_arena", "short": "ESPACIO", "name": "ARENA ESPACIAL", "level": "res://Levels/SpaceArena.tscn", "preview": "res://Assets/Maps/References/7_level_moon.png"},
	{"id": "snow_fields", "short": "NIEVE", "name": "CAMPOS DE NIEVE", "level": "res://Levels/SnowFields.tscn", "preview": "res://Assets/Maps/References/3_frozen_snow_fields.png"},
]

var status_label: Label
var name_input: LineEdit
var map_preview: TextureRect
var map_title: Label
var mode_desc: Label
var play_button: Button
var vis_desc: Label

var _mode_index := 0
var _map_index := 0
var _mode_buttons: Array[Button] = []
var _room_list: VBoxContainer
var _rooms_status: Label
var _selected_room: String = ""
var _refreshing := false
var _map_buttons: Array[Button] = []
var _privada := false
var _entrando := false
var _vis_buttons: Array[Button] = []
var _code_input: LineEdit
var _join_button: Button
## Opciones de la sala que se crea (se mandan al servidor).
const JUGADORES_OPC := [2, 4, 8, 12, 20]
const BOTS_OPC := [0, 1, 2, 3, 5]
var _monstruos := true
var _bots_i := 3            # 3 bots por defecto (igual que el servidor)
var _jug_i := 4             # 20 jugadores por defecto
var _opt_monstruos: Button
var _opt_bots: Button
var _opt_jug: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	MenuFX.attach(self)
	OnlineManager.status_changed.connect(_on_online_status_changed)
	OnlineManager.match_ready.connect(_on_online_match_ready)
	name_input.text = OnlineManager.username
	_select_mode(0)
	_select_map(0)
	_select_vis(false)
	call_deferred("_refresh_rooms")
	play_button.grab_focus()


func _build() -> void:
	var pic := UIKit.add_backdrop(self, BACKDROP, 0.3)
	UIKit.animate_backdrop(pic)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 72)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var root := VBoxContainer.new()
	margin.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(UIKit.logo(92))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var back := UIKit.menu_button("VOLVER", "", 24)
	back.custom_minimum_size = Vector2(190, 52)
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_on_back_button_pressed)
	head.add_child(back)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 40)
	root.add_child(body)

	# ---- izquierda: modo, mapa, jugador
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(620, 0)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)

	left.add_child(UIKit.label("// 01 MODO DE JUEGO", 15, UIKit.COL_DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	left.add_child(grid)
	for i in MODES.size():
		var b := UIKit.menu_button(MODES[i].name, "", 26)
		b.custom_minimum_size = Vector2(300, 56)
		b.toggle_mode = true
		b.pressed.connect(_select_mode.bind(i))
		grid.add_child(b)
		_mode_buttons.append(b)
	mode_desc = UIKit.label("", 17, UIKit.COL_DIM)
	mode_desc.custom_minimum_size = Vector2(0, 46)
	left.add_child(mode_desc)

	left.add_child(UIKit.label("// 02 MAPA", 15, UIKit.COL_DIM))
	var maps := HBoxContainer.new()
	maps.add_theme_constant_override("separation", 8)
	left.add_child(maps)
	for i in MAPS.size():
		var m := UIKit.menu_button(str(MAPS[i].short), "", 22)
		# 4 mapas en una fila: el ancho se reparte (antes 196 fijo cabia solo para 3)
		m.custom_minimum_size = Vector2(146, 50)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.toggle_mode = true
		m.pressed.connect(_select_map.bind(i))
		maps.add_child(m)
		_map_buttons.append(m)

	left.add_child(UIKit.label("// 03 TU NOMBRE", 15, UIKit.COL_DIM))
	name_input = LineEdit.new()
	name_input.max_length = 16
	name_input.placeholder_text = "xpe.nettt"
	name_input.custom_minimum_size = Vector2(0, 48)
	name_input.add_theme_font_size_override("font_size", 24)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.04, 0.025, 0.03, 0.9)
	field.border_color = Color(0.45, 0.09, 0.06)
	field.set_border_width_all(2)
	field.content_margin_left = 14.0
	name_input.add_theme_stylebox_override("normal", field)
	name_input.add_theme_stylebox_override("focus", field)
	left.add_child(name_input)

	left.add_child(UIKit.label("// 04 VISIBILIDAD", 15, UIKit.COL_DIM))
	var vis := HBoxContainer.new()
	vis.add_theme_constant_override("separation", 8)
	left.add_child(vis)
	for i in 2:
		var v := UIKit.menu_button(["PUBLICA", "PRIVADA"][i], "", 24)
		v.custom_minimum_size = Vector2(300, 50)
		v.toggle_mode = true
		v.pressed.connect(_select_vis.bind(i == 1))
		vis.add_child(v)
		_vis_buttons.append(v)
	vis_desc = UIKit.label("", 15, UIKit.COL_DIM)
	left.add_child(vis_desc)

	left.add_child(UIKit.label("// 05 OPCIONES DE SALA", 15, UIKit.COL_DIM))
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 8)
	left.add_child(opts)
	_opt_monstruos = UIKit.menu_button("", "", 20)
	_opt_bots = UIKit.menu_button("", "", 20)
	_opt_jug = UIKit.menu_button("", "", 20)
	for ob in [_opt_monstruos, _opt_bots, _opt_jug]:
		ob.custom_minimum_size = Vector2(196, 46)
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opts.add_child(ob)
	_opt_monstruos.pressed.connect(func() -> void: _monstruos = not _monstruos; _refrescar_opciones())
	_opt_bots.pressed.connect(func() -> void: _bots_i = (_bots_i + 1) % BOTS_OPC.size(); _refrescar_opciones())
	_opt_jug.pressed.connect(func() -> void: _jug_i = (_jug_i + 1) % JUGADORES_OPC.size(); _refrescar_opciones())
	_refrescar_opciones()

	play_button = UIKit.menu_button("CREAR SALA", "", 36)
	play_button.custom_minimum_size = Vector2(0, 70)
	play_button.pressed.connect(_on_online_queue_pressed)
	left.add_child(play_button)
	status_label = UIKit.label("Listo para conectar.", 16, UIKit.COL_DIM)
	left.add_child(status_label)

	# ---- derecha: vista previa del mapa
	var right := UIKit.panel(16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)

	# --- unirse con el codigo de una sala (publica o privada)
	rv.add_child(UIKit.label("UNIRSE CON CODIGO", 18, UIKit.COL_EMBER, true))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	rv.add_child(join_row)
	_code_input = LineEdit.new()
	_code_input.max_length = 7
	_code_input.placeholder_text = "K7M2Q"
	_code_input.custom_minimum_size = Vector2(190, 52)
	_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_input.add_theme_font_size_override("font_size", 28)
	_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var campo := StyleBoxFlat.new()
	campo.bg_color = Color(0.04, 0.025, 0.03, 0.9)
	campo.border_color = Color(0.45, 0.09, 0.06)
	campo.set_border_width_all(2)
	_code_input.add_theme_stylebox_override("normal", campo)
	_code_input.add_theme_stylebox_override("focus", campo)
	_code_input.text_changed.connect(_on_codigo_cambiado)
	_code_input.text_submitted.connect(func(_t: String) -> void: _on_unirse_pressed())
	join_row.add_child(_code_input)
	_join_button = UIKit.menu_button("UNIRSE", "", 26)
	_join_button.custom_minimum_size = Vector2(170, 52)
	_join_button.disabled = true
	_join_button.pressed.connect(_on_unirse_pressed)
	join_row.add_child(_join_button)
	rv.add_child(UIKit.divider())

	# --- salas publicas abiertas ahora mismo
	var rooms_head := HBoxContainer.new()
	rv.add_child(rooms_head)
	var rt := UIKit.label("SALAS PUBLICAS", 18, UIKit.COL_EMBER, true)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rooms_head.add_child(rt)
	var refresh := UIKit.menu_button("ACTUALIZAR", "", 16)
	refresh.custom_minimum_size = Vector2(150, 38)
	refresh.pressed.connect(_refresh_rooms)
	rooms_head.add_child(refresh)

	_rooms_status = UIKit.label("Buscando salas...", 15, UIKit.COL_DIM)
	rv.add_child(_rooms_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 210)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(scroll)
	_room_list = VBoxContainer.new()
	_room_list.add_theme_constant_override("separation", 4)
	_room_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_room_list)

	map_title = UIKit.label("", 24, UIKit.COL_EMBER, true)
	rv.add_child(map_title)
	map_preview = TextureRect.new()
	map_preview.custom_minimum_size = Vector2(0, 180)
	map_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rv.add_child(map_preview)

	body.add_child(right)

	var foot := UIKit.label("© 2026 xpe.nettt · Stealth Proyects", 16, UIKit.COL_DIM)
	root.add_child(foot)



const DUELO_JUG_I := 1      # aforo inicial del duelo: 4 jugadores (amigos), se puede cambiar
var _jug_antes_duelo := -1


func _select_mode(i: int) -> void:
	var venia_de_duelo := _es_duelo()
	_mode_index = i
	# Al entrar al duelo el aforo baja a 4; al salir se devuelve el que el jugador tenia.
	if _es_duelo() and not venia_de_duelo:
		_jug_antes_duelo = _jug_i
		_jug_i = DUELO_JUG_I
	elif venia_de_duelo and not _es_duelo() and _jug_antes_duelo >= 0:
		_jug_i = _jug_antes_duelo
		_jug_antes_duelo = -1
	for k in _mode_buttons.size():
		_mode_buttons[k].button_pressed = (k == i)
	mode_desc.text = MODES[i].desc
	if _opt_monstruos != null:
		_refrescar_opciones()


func _select_map(i: int) -> void:
	_map_index = i
	for k in _map_buttons.size():
		_map_buttons[k].button_pressed = (k == i)
	map_title.text = MAPS[i].name
	map_preview.texture = LobbyAudio.load_texture(MAPS[i].preview)


func _refresh_rooms() -> void:
	if _refreshing or _room_list == null:
		return
	_refreshing = true
	_rooms_status.text = "Buscando salas..."
	for c in _room_list.get_children():
		c.queue_free()
	var rooms: Array = await OnlineManager.fetch_rooms()
	_refreshing = false
	if rooms.is_empty():
		_rooms_status.text = "No hay salas abiertas. Crea una y tus amigos se unen."
		return
	_rooms_status.text = "%d sala(s) abiertas" % rooms.size()
	for room in rooms:
		_room_list.add_child(_room_row(room))


func _room_row(room: Dictionary) -> Control:
	var row := UIKit.menu_button("", "", 17)
	var mode_label := str(room.get("mode_label", room.get("mode", "")))
	var map_label := str(room.get("map_label", room.get("map", "")))
	var players := int(room.get("players", 0))
	var bots := int(room.get("bots", 0))
	var cap := int(room.get("max", 20))
	var wave := int(room.get("wave", 0))
	# En el juego nadie es un "bot": los entrenados cuentan como jugadores.
	var total := players + bots
	var nombre := str(room.get("name", "Sala"))
	var estado := "oleada %d" % wave if bool(room.get("monsters", true)) else "SIN MONSTRUOS"
	var modo_sala := str(room.get("mode", ""))
	for m in MODES:
		if str(m.id) == modo_sala and bool(m.get("pvp", false)):
			estado = "PvP POR EQUIPOS" if modo_sala != "duelo" else "PvP ENTRE AMIGOS"   # nada de "oleada" ni "sin monstruos"
	row.text = "%s\n%s · %s — %d/%d jugadores · %s" % [nombre, mode_label.to_upper(), map_label.to_upper(), total, cap, estado]
	row.custom_minimum_size = Vector2(0, 58)
	row.add_theme_font_size_override("font_size", 16)
	var codigo := str(room.get("code", ""))
	if codigo != "":
		row.text += "   [%s]" % codigo
	row.pressed.connect(func() -> void:
		if codigo == "":
			status_label.text = "Esa sala es antigua y no tiene codigo. Crea una nueva."
			return
		_code_input.text = codigo
		_on_unirse_pressed())
	return row


func _bloquear_botones(bloqueado: bool) -> void:
	if play_button:
		play_button.disabled = bloqueado
	if _join_button:
		_join_button.disabled = bloqueado or _code_input.text.length() < 5
	if _room_list:
		for c in _room_list.get_children():
			if c is Button:
				(c as Button).disabled = bloqueado


func _select_vis(privada: bool) -> void:
	_privada = privada
	for k in _vis_buttons.size():
		_vis_buttons[k].button_pressed = ((k == 1) == privada)
	vis_desc.text = "Solo entra quien tenga el codigo. No sale en la lista. Sin bots." if privada else "Sale en la lista de salas: cualquiera puede unirse."
	if _opt_monstruos != null:
		_refrescar_opciones()


## "Duelo" aqui significa cualquier modo jugador-contra-jugador (duelo y los de equipos): sin
## monstruos ni bots, y aforo de amigos. Se lee del propio modo para que anadir otro no exija tocar esto.
func _es_duelo() -> bool:
	return bool(MODES[_mode_index].get("pvp", false))


func _refrescar_opciones() -> void:
	# En el duelo no hay monstruos ni bots: se muestra tal cual y no se puede cambiar.
	var duelo := _es_duelo()
	_opt_monstruos.text = "MONSTRUOS: " + ("NO" if duelo else ("SI" if _monstruos else "NO"))
	# Duelo y salas privadas: sin bots (y el boton se bloquea).
	_opt_bots.text = "BOTS: " + ("0" if (duelo or _privada) else str(BOTS_OPC[_bots_i]))
	_opt_monstruos.disabled = duelo
	_opt_bots.disabled = duelo or _privada
	_opt_jug.text = "MAX: %d" % JUGADORES_OPC[_jug_i]


## Las opciones elegidas, tal cual viajan al servidor.
func opciones_sala() -> Dictionary:
	if _es_duelo():
		return {"monsters": false, "bots": 0, "max_players": JUGADORES_OPC[_jug_i]}
	return {"monsters": _monstruos, "bots": 0 if _privada else BOTS_OPC[_bots_i], "max_players": JUGADORES_OPC[_jug_i]}


## CREAR: siempre abre una sala nueva con el modo, mapa y visibilidad elegidos.
func _on_online_queue_pressed() -> void:
	if _entrando:
		return
	_entrando = true
	_bloquear_botones(true)
	status_label.text = "Creando sala en %s..." % MAPS[_map_index].name
	OnlineManager.username = name_input.text.strip_edges() if name_input.text.strip_edges() != "" else OnlineManager.username
	var r: Dictionary = await OnlineManager.create_room(str(MODES[_mode_index].id), str(MAPS[_map_index].id), _privada, "", opciones_sala())
	_terminar_intento(r)


## UNIRSE: entra a una sala que ya existe, con su codigo. Nunca crea nada.
func _on_unirse_pressed() -> void:
	if _entrando:
		return
	var codigo := _code_input.text.strip_edges()
	if codigo.length() < 5:
		status_label.text = "Escribe el codigo de 5 caracteres."
		return
	_entrando = true
	_bloquear_botones(true)
	status_label.text = "Buscando la sala %s..." % codigo.to_upper()
	var r: Dictionary = await OnlineManager.join_by_code(codigo)
	_terminar_intento(r)


func _terminar_intento(r: Dictionary) -> void:
	if not is_inside_tree():
		return
	if bool(r.get("ok", false)):
		return   # match_ready cambia de escena: no hay nada que liberar
	_entrando = false
	_bloquear_botones(false)
	status_label.text = str(r.get("error", "No se pudo entrar. Pulsa de nuevo."))
	_refresh_rooms()


func _on_codigo_cambiado(texto: String) -> void:
	# mayusculas y solo letras/numeros, para que "k7m-2q" tambien valga
	var limpio := ""
	for ch in texto.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			limpio += ch
	if limpio != texto:
		var pos := _code_input.caret_column
		_code_input.text = limpio
		_code_input.caret_column = mini(pos, limpio.length())
	_join_button.disabled = _entrando or limpio.length() < 5


func _on_online_status_changed(message: String) -> void:
	if status_label:
		status_label.text = message


func _on_online_match_ready(_match_id: String) -> void:
	LobbyAudio.change_scene(get_tree(), MAPS[_map_index].level)


func _on_back_button_pressed() -> void:
	OnlineManager.leave_online()
	LobbyAudio.change_scene(get_tree(), "res://Levels/MainMenu.tscn")

