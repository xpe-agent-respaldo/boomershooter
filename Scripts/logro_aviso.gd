extends Node
## Aviso de logro conseguido dentro de la partida.
##
## Aparece a la derecha, justo debajo del contador de KILLS, sin tapar nada del
## HUD original: panel oscuro, barra a la izquierda y el color de la rareza.
## Si caen varios logros a la vez se encolan y se muestran de uno en uno.

const FONT_PATH := "res://Assets/Fonts/Geizer.otf"
const SOUND_PATH := "res://Assets/Sounds/SFX/logro.wav"
const ANCHO := 392.0
const SEPARACION := 10.0
const DURACION := 3.4

var _capa: CanvasLayer
var _caja: VBoxContainer
var _cola: Array = []
var _mostrando: bool = false
var _jugador: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capa = CanvasLayer.new()
	_capa.layer = 120
	_capa.name = "CapaAvisoLogros"
	add_child(_capa)

	_caja = VBoxContainer.new()
	_caja.name = "Avisos"
	_caja.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_caja.anchor_left = 1.0
	_caja.anchor_right = 1.0
	_caja.offset_left = -ANCHO - 28.0
	_caja.offset_right = -28.0
	# el contador de KILLS ocupa la esquina superior derecha: el aviso empieza debajo
	_caja.offset_top = 96.0
	_caja.offset_bottom = 96.0
	_caja.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caja.add_theme_constant_override("separation", int(SEPARACION))
	_capa.add_child(_caja)

	_jugador = AudioStreamPlayer.new()
	_jugador.name = "SonidoLogro"
	_jugador.volume_db = -4.0
	if ResourceLoader.exists(SOUND_PATH):
		_jugador.stream = load(SOUND_PATH)
	add_child(_jugador)

	if not Achievements.unlocked.is_connected(_on_logro):
		Achievements.unlocked.connect(_on_logro)


func _on_logro(_id: String, nombre: String, premio: int, rareza: String, secreto: bool) -> void:
	_cola.append({"nombre": nombre, "premio": premio, "rareza": rareza, "secreto": secreto})
	if not _mostrando:
		_siguiente()


func _siguiente() -> void:
	if _cola.is_empty():
		_mostrando = false
		return
	_mostrando = true
	var dato: Dictionary = _cola.pop_front()
	var panel := _panel(dato)
	_caja.add_child(panel)
	if _jugador.stream != null:
		_jugador.play()

	# entra desde la derecha y se coloca
	panel.modulate.a = 0.0
	panel.position.x = 26.0
	var tw := panel.create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.22)
	tw.tween_property(panel, "position:x", 0.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(DURACION)
	tw.chain().tween_property(panel, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free()
		_siguiente()
	)


func _panel(dato: Dictionary) -> Control:
	var color := _color(dato["rareza"])
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ANCHO, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.03, 0.02, 0.025, 0.93)
	st.border_color = color
	st.set_border_width_all(1)
	st.border_width_left = 6
	st.content_margin_left = 16.0
	st.content_margin_right = 16.0
	st.content_margin_top = 10.0
	st.content_margin_bottom = 10.0
	st.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	st.shadow_size = 10
	panel.add_theme_stylebox_override("panel", st)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)

	var cab := _label("LOGRO DESBLOQUEADO", 11, Color(0.66, 0.56, 0.5, 1.0))
	cab.add_theme_constant_override("outline_size", 0)
	v.add_child(cab)

	# Sin autowrap: dentro de un contenedor el ancho de calculo es 0 y la altura
	# minima se disparaba (el aviso se comia media pantalla).
	var nombre := _label(str(dato["nombre"]), 21, color, true)
	nombre.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.add_child(nombre)

	var pie := _label("+%d MONEDAS  ·  %s" % [int(dato["premio"]), str(dato["rareza"]).to_upper()], 12, Color(1.0, 0.42, 0.12, 1.0))
	v.add_child(pie)
	return panel


func _color(rareza: String) -> Color:
	var r: Dictionary = Achievements.RAREZAS.get(rareza, Achievements.RAREZAS["comun"])
	return r["color"]


func _label(texto: String, tam: int, color: Color, con_fuente: bool = false) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	if con_fuente and ResourceLoader.exists(FONT_PATH):
		l.add_theme_font_override("font", load(FONT_PATH))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
