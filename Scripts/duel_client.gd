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

var activo := false
var _marcador: Array = []
var _panel: PanelContainer
var _lista: VBoxContainer
var _avisos: VBoxContainer
var _caido_hasta := 0.0
var _aviso_caida: Label
var _yo := ""


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir()
	OnlineManager.wave_state_received.connect(_on_estado_sala)
	OnlineManager.duel_event_received.connect(_on_evento)
	visible = false


## Solo hay duelo cuando el servidor dice que la sala es de ese modo.
func _on_estado_sala(estado: Dictionary) -> void:
	var ahora := str(estado.get("mode", "")) == "duelo"
	if ahora != activo:
		activo = ahora
		visible = activo
		_yo = OnlineManager.get_local_user_id()
		if not activo:
			_marcador.clear()
			_pintar()


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
	_lista.add_child(_etiqueta("DUELO  ·  MARCADOR", 26, Color(1.0, 0.72, 0.25)))
	if _marcador.is_empty():
		_lista.add_child(_etiqueta("Aún no hay bajas.", 18, COLOR_INFO))
		return
	_lista.add_child(_etiqueta("%-16s %6s %8s" % ["JUGADOR", "BAJAS", "MUERTES"], 16, COLOR_INFO))
	for fila in _marcador:
		if not fila is Dictionary:
			continue
		var color := COLOR_OK if str(fila.get("user_id", "")) == _yo else COLOR_INFO
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
