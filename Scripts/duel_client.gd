extends CanvasLayer
## Duelo (jugador contra jugador), lado cliente. Autoload.
##
## El SERVIDOR es la autoridad: lleva la vida, valida cada impacto (distancia, pared, ritmo) y cuenta
## las bajas. Aqui solo se (1) manda "le di a X", (2) se refleja la vida que dice el servidor y
## (3) se muestra el marcador. En duelo morir no es "game over": caes 5 s y reapareces.
##
## Estilo del juego: fuente Geizer, paneles oscuros con borde de color.

const FUENTE := preload("res://Assets/Fonts/Geizer.otf")
const COLOR_OK := Color(0.55, 0.9, 0.55)
const COLOR_MAL := Color(1.0, 0.25, 0.2)
const COLOR_INFO := Color(0.85, 0.85, 0.9)
const SEGUNDOS_BANNER := 3.5
const TECLA_MARCADOR := KEY_TAB

const MODOS_EQUIPOS := ["tdm", "dominio", "caliente"]
const COL_ROJO := Color(0.92, 0.2, 0.15)
const COL_AZUL := Color(0.3, 0.6, 1.0)
const NOMBRES := {"duelo": "DUELO", "tdm": "DUELO POR EQUIPOS", "dominio": "DOMINAR EL PUNTO", "caliente": "PUNTO CALIENTE"}

var activo := false
var modo := ""                 # duelo | tdm | dominio | caliente
var mi_equipo := ""            # "rojo" | "azul" | "" (duelo individual)
var eq: Dictionary = {}        # ultimo estado de equipos que mando el servidor
var equipos_de: Dictionary = {}   # user_id -> equipo
var _marcador: Array = []
var _hud: PanelContainer
var _hud_rojo: Label
var _hud_azul: Label
var _hud_meta: Label
var _hud_info: Label
var _balizas: Dictionary = {}  # id objetivo -> Node3D
var _panel: PanelContainer
var _lista: VBoxContainer
var _avisos: VBoxContainer
var _caido_hasta := 0.0
var _aviso_caida: Label
var _yo := ""
var yo_para_pruebas := ""      # solo tools/tests: permite fijar quien soy sin sesion de red


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir()
	OnlineManager.wave_state_received.connect(_on_estado_sala)
	OnlineManager.duel_event_received.connect(_on_evento)
	visible = false


## Solo hay duelo cuando el servidor dice que la sala es de ese modo.
func _on_estado_sala(estado: Dictionary) -> void:
	var m := str(estado.get("mode", ""))
	var ahora := m == "duelo" or m in MODOS_EQUIPOS
	if ahora != activo or m != modo:
		activo = ahora
		modo = m if ahora else ""
		visible = activo
		_yo = yo_para_pruebas if not yo_para_pruebas.is_empty() else OnlineManager.get_local_user_id()
		if not activo:
			_marcador.clear()
			mi_equipo = ""
			eq = {}
			equipos_de = {}
			_limpiar_balizas()
			_pintar()
			_pintar_hud()      # oculta el marcador de equipos al salir
	if activo and estado.get("eq") is Dictionary:
		_recibir_equipos(estado["eq"], estado.get("players", []))
		_pintar_hud()


func es_duelo() -> bool:
	return activo


func _unhandled_input(event: InputEvent) -> void:
	if not activo:
		return
	if event is InputEventKey and event.keycode == TECLA_MARCADOR:
		_panel.visible = event.pressed
		if event.pressed:
			_pintar()


func _process(_delta: float) -> void:
	if not activo:
		return
	var restante := _caido_hasta - Time.get_ticks_msec() / 1000.0
	_aviso_caida.visible = restante > 0.0
	if restante > 0.0:
		_aviso_caida.text = "CAISTE  ·  REAPARECES EN %d" % int(ceil(restante))


func _on_evento(ev: Dictionary) -> void:
	if not activo:
		return
	var tipo := str(ev.get("kind", ""))
	var jugador := get_tree().get_first_node_in_group("player")
	match tipo:
		"hit":
			if str(ev.get("to", "")) == _yo and jugador != null and jugador.has_method("recibir_dano_duelo"):
				jugador.recibir_dano_duelo(int(ev.get("damage", 0)), int(ev.get("hp", 100)), _posicion_de(str(ev.get("from", ""))))
		"kill":
			_marcador = ev.get("board", [])
			var asesino := str(ev.get("killer", "?"))
			var victima := str(ev.get("victim", "?"))
			var mio_mato := str(ev.get("from", "")) == _yo
			var me_mataron := str(ev.get("to", "")) == _yo
			_aviso("%s eliminó a %s" % [asesino, victima], COLOR_OK if mio_mato else (COLOR_MAL if me_mataron else COLOR_INFO))
			if me_mataron:
				_caido_hasta = Time.get_ticks_msec() / 1000.0 + 5.0
				if jugador != null and jugador.has_method("caer_en_duelo"):
					jugador.caer_en_duelo()
		"equipos":
			_marcador = ev.get("board", _marcador)
			if ev.get("eq") is Dictionary:
				_recibir_equipos(ev["eq"], [])
				_pintar_hud()
		"captura":
			var quien := str(ev.get("equipo", ""))
			_aviso("EQUIPO %s CAPTURA UN PUNTO" % quien.to_upper(), _color_equipo(quien))
		"rota":
			_aviso("EL PUNTO CALIENTE SE HA MOVIDO", Color(1.0, 0.72, 0.25))
		"respawn":
			_marcador = ev.get("board", _marcador)
			if str(ev.get("to", "")) == _yo:
				_caido_hasta = 0.0
				_aviso_caida.visible = false
				if jugador != null and jugador.has_method("reaparecer_en_duelo"):
					jugador.reaparecer_en_duelo(int(ev.get("hp", 100)))
	if _panel.visible:
		_pintar()


func _posicion_de(uid: String) -> Vector3:
	var escena := get_tree().current_scene
	if escena != null and "_remote" in escena:
		var remoto = escena._remote.get(uid)
		if remoto is Node3D:
			return remoto.global_position
	return Vector3.ZERO


# --- dibujo -------------------------------------------------------------------
func _construir() -> void:
	_avisos = VBoxContainer.new()
	_avisos.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_avisos.offset_left = -420.0
	_avisos.offset_right = -16.0
	_avisos.offset_top = 80.0
	_avisos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avisos.add_theme_constant_override("separation", 4)
	add_child(_avisos)

	_aviso_caida = Label.new()
	_aviso_caida.set_anchors_preset(Control.PRESET_CENTER)
	_aviso_caida.offset_left = -300.0
	_aviso_caida.offset_right = 300.0
	_aviso_caida.offset_top = -40.0
	_aviso_caida.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso_caida.add_theme_font_override("font", FUENTE)
	_aviso_caida.add_theme_font_size_override("font_size", 38)
	_aviso_caida.add_theme_color_override("font_color", COLOR_MAL)
	_aviso_caida.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_aviso_caida.add_theme_constant_override("outline_size", 8)
	_aviso_caida.visible = false
	add_child(_aviso_caida)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -260.0
	_panel.offset_right = 260.0
	_panel.offset_top = -200.0
	_panel.offset_bottom = 200.0
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.03, 0.02, 0.025, 0.92)
	estilo.border_color = Color(1.0, 0.72, 0.25)
	estilo.set_border_width_all(2)
	estilo.border_width_left = 8
	estilo.set_corner_radius_all(2)
	estilo.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", estilo)
	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 6)
	_panel.add_child(_lista)
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)


func _pintar() -> void:
	for h in _lista.get_children():
		h.queue_free()
	_lista.add_child(_etiqueta("%s  ·  MARCADOR" % NOMBRES.get(modo, "DUELO"), 26, Color(1.0, 0.72, 0.25)))
	if _marcador.is_empty():
		_lista.add_child(_etiqueta("Aún no hay bajas.", 18, COLOR_INFO))
		return
	_lista.add_child(_etiqueta("%-16s %6s %8s" % ["JUGADOR", "BAJAS", "MUERTES"], 16, COLOR_INFO))
	for fila in _marcador:
		if not fila is Dictionary:
			continue
		var color := COLOR_OK if str(fila.get("user_id", "")) == _yo else COLOR_INFO
		if es_equipos() and fila.get("team") != null:
			color = _color_equipo(str(fila.get("team")))
		_lista.add_child(_etiqueta("%-16s %6d %8d" % [str(fila.get("name", "?")).left(16),
			int(fila.get("kills", 0)), int(fila.get("deaths", 0))], 20, color))


func _etiqueta(texto: String, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_override("font", FUENTE)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	return l


func _aviso(texto: String, color: Color) -> void:
	var l := _etiqueta(texto, 20, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	_avisos.add_child(l)
	while _avisos.get_child_count() > 5:
		_avisos.get_child(0).queue_free()
		_avisos.remove_child(_avisos.get_child(0))
	var tween := create_tween()
	tween.tween_interval(SEGUNDOS_BANNER)
	tween.tween_property(l, "modulate:a", 0.0, 0.6)
	tween.tween_callback(l.queue_free)


# --- equipos ------------------------------------------------------------------
func es_equipos() -> bool:
	return activo and modo in MODOS_EQUIPOS


func _color_equipo(e: String) -> Color:
	return COL_ROJO if e == "rojo" else (COL_AZUL if e == "azul" else COLOR_INFO)


## Es un rival (se le puede disparar)? En duelo individual todos lo son; en equipos solo el otro bando.
func es_rival(uid: String) -> bool:
	if not es_equipos():
		return activo
	var e := str(equipos_de.get(uid, ""))
	return e.is_empty() or mi_equipo.is_empty() or e != mi_equipo


func _recibir_equipos(datos: Dictionary, jugadores: Array) -> void:
	eq = datos
	var gente = datos.get("equipos", {})
	if gente is Dictionary:
		equipos_de = gente
	for j in jugadores:
		if j is Dictionary and j.get("team") != null:
			equipos_de[str(j.get("user_id", ""))] = str(j.get("team"))
	mi_equipo = str(equipos_de.get(_yo, mi_equipo))
	_actualizar_balizas(datos.get("objetivos", []))


func _limpiar_balizas() -> void:
	for b in _balizas.values():
		if is_instance_valid(b):
			b.queue_free()
	_balizas.clear()


## Una columna de luz por punto de captura, visible desde lejos. Color = dueno (gris si nadie).
func _actualizar_balizas(objetivos: Array) -> void:
	var escena := get_tree().current_scene
	if escena == null or not (escena is Node3D):
		return
	var vistos := {}
	for o in objetivos:
		if not o is Dictionary:
			continue
		var id := int(o.get("id", 0))
		vistos[id] = true
		var baliza: Node3D = _balizas.get(id)
		var radio := float(o.get("radio", 7.0))
		if baliza == null or not is_instance_valid(baliza):
			baliza = _crear_baliza(radio)
			escena.add_child(baliza)
			_balizas[id] = baliza
		baliza.global_position = Vector3(float(o.get("x", 0)), 0.05, float(o.get("z", 0)))
		var dueno := str(o.get("dueno", "")) if o.get("dueno") != null else ""
		var col := _color_equipo(dueno) if not dueno.is_empty() else Color(0.75, 0.75, 0.75)
		if bool(o.get("disputado", false)):
			col = Color(1.0, 0.72, 0.25)
		_pintar_baliza(baliza, col, o.get("activo", true) != false)
	for id in _balizas.keys():
		if not vistos.has(id):
			if is_instance_valid(_balizas[id]):
				_balizas[id].queue_free()
			_balizas.erase(id)


func _crear_baliza(radio: float) -> Node3D:
	var raiz := Node3D.new()
	raiz.name = "BalizaPunto"
	var anillo := MeshInstance3D.new()
	anillo.name = "Anillo"
	var malla := CylinderMesh.new()
	malla.top_radius = radio
	malla.bottom_radius = radio
	malla.height = 0.12
	malla.radial_segments = 48
	anillo.mesh = malla
	raiz.add_child(anillo)
	var haz := MeshInstance3D.new()
	haz.name = "Haz"
	var col := CylinderMesh.new()
	col.top_radius = 0.5
	col.bottom_radius = 0.9
	col.height = 40.0
	col.radial_segments = 16
	haz.mesh = col
	haz.position.y = 20.0
	raiz.add_child(haz)
	return raiz


func _pintar_baliza(baliza: Node3D, col: Color, activo_: bool) -> void:
	baliza.visible = activo_
	for nombre in ["Anillo", "Haz"]:
		var m := baliza.get_node_or_null(nombre) as MeshInstance3D
		if m == null:
			continue
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(col.r, col.g, col.b, 0.38 if nombre == "Anillo" else 0.22)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Marcador permanente arriba al centro: puntos de cada equipo y la meta.
func _construir_hud() -> void:
	_hud = PanelContainer.new()
	_hud.name = "HudEquipos"
	_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hud.offset_left = -230.0
	_hud.offset_right = 230.0
	_hud.offset_top = 10.0
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.03, 0.02, 0.025, 0.82)
	estilo.border_color = Color(0.45, 0.09, 0.06)
	estilo.set_border_width_all(2)
	estilo.border_width_top = 4
	estilo.set_content_margin_all(8)
	_hud.add_theme_stylebox_override("panel", estilo)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 2)
	_hud.add_child(caja)
	var fila := HBoxContainer.new()
	fila.alignment = BoxContainer.ALIGNMENT_CENTER
	fila.add_theme_constant_override("separation", 26)
	caja.add_child(fila)
	_hud_rojo = _etiqueta("ROJO 0", 34, COL_ROJO)
	_hud_azul = _etiqueta("0 AZUL", 34, COL_AZUL)
	_hud_meta = _etiqueta("META 0", 20, COLOR_INFO)
	fila.add_child(_hud_rojo)
	fila.add_child(_hud_meta)
	fila.add_child(_hud_azul)
	_hud_info = _etiqueta("", 18, COLOR_INFO)
	_hud_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(_hud_info)
	_hud.visible = false
	add_child(_hud)


func _pintar_hud() -> void:
	if _hud == null:
		_construir_hud()
	_hud.visible = es_equipos()
	if not es_equipos():
		return
	var pts = eq.get("puntos", {})
	_hud_rojo.text = "ROJO %d" % int(pts.get("rojo", 0))
	_hud_azul.text = "%d AZUL" % int(pts.get("azul", 0))
	_hud_meta.text = "META %d" % int(eq.get("meta", 0))
	var tu := "TU EQUIPO: %s" % mi_equipo.to_upper() if not mi_equipo.is_empty() else ""
	_hud_info.text = "%s   %s" % [NOMBRES.get(modo, ""), tu]
	_hud_info.add_theme_color_override("font_color", _color_equipo(mi_equipo))
