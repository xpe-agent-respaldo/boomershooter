extends Node
## Carga de escenas en segundo plano con pantalla de carga propia.
##
## Antes, cambiar de mapa era `change_scene_to_file`: el motor cargaba todo el nivel
## en un solo frame (cientos de milisegundos) y justo despues la fusion CSG y la
## compilacion de shaders dejan mas tirones. El jugador veia la pantalla congelada.
##
## Ahora el nivel se carga en un hilo, con una pantalla de carga con el estilo del
## juego, y esa pantalla se queda unos frames de mas para tapar la fusion del mapa.

signal carga_terminada(ruta: String)

const FONT_PATH := "res://Assets/Fonts/Geizer.otf"
const MINIMO_EN_PANTALLA := 0.45      # si carga muy rapido, no parpadea
const FRAMES_TAPANDO_EL_MAPA := 4     # la fusion CSG ocurre en estos frames

var _ruta: String = ""
var _pantalla: CanvasLayer
var _raiz: Control
var _barra: ProgressBar
var _etiqueta: Label
var _t0: int = 0
var _terminando := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


## Cambia de escena sin congelar el juego. Si ya hay una carga en marcha, se ignora.
func cambiar(ruta: String) -> void:
	if _ruta != "" or _terminando or ruta.is_empty():
		return
	if not ResourceLoader.exists(ruta):
		push_warning("No se pudo cargar la escena: %s" % ruta)
		return
	_ruta = ruta
	_t0 = Time.get_ticks_msec()
	_crear_pantalla()
	var err := ResourceLoader.load_threaded_request(ruta, "PackedScene", true)
	if err != OK:
		# Sin hilos disponibles: se hace como siempre, pero al menos avisamos.
		_escribir("CARGANDO…")
		get_tree().change_scene_to_file(ruta)
		_ruta = ""
		await _cerrar_pantalla()
		return
	set_process(true)


func _process(_delta: float) -> void:
	if _ruta == "":
		return
	var progreso: Array = []
	var estado := ResourceLoader.load_threaded_get_status(_ruta, progreso)
	if progreso.size() > 0:
		_barra.value = clampf(float(progreso[0]), 0.0, 1.0)
	if estado == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if estado == ResourceLoader.THREAD_LOAD_FAILED or estado == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		push_warning("Fallo la carga en segundo plano de %s" % _ruta)
		_ruta = ""
		set_process(false)
		await _cerrar_pantalla()
		return
	# Cargado: se instala la escena y se deja la pantalla tapando la fusion del mapa
	var packed := ResourceLoader.load_threaded_get(_ruta) as PackedScene
	var destino := _ruta
	_ruta = ""
	set_process(false)
	if packed == null:
		await _cerrar_pantalla()
		return
	_barra.value = 1.0
	_escribir("PREPARANDO EL MAPA…")
	get_tree().change_scene_to_packed(packed)
	await get_tree().process_frame
	for i in FRAMES_TAPANDO_EL_MAPA:
		await get_tree().process_frame
	await _cerrar_pantalla()
	carga_terminada.emit(destino)


# --------------------------------------------------------------------------
# Pantalla de carga (mismo lenguaje visual: fondo oscuro, Geizer, acentos brasa)
# --------------------------------------------------------------------------

func _crear_pantalla() -> void:
	if _pantalla != null and is_instance_valid(_pantalla):
		return
	_pantalla = CanvasLayer.new()
	_pantalla.name = "CapaCarga"
	_pantalla.layer = 210
	_pantalla.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pantalla)

	_raiz = Control.new()
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_raiz.mouse_filter = Control.MOUSE_FILTER_STOP
	_pantalla.add_child(_raiz)

	var fondo := ColorRect.new()
	fondo.color = Color(0.015, 0.01, 0.012, 1.0)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	_raiz.add_child(fondo)

	var centro := VBoxContainer.new()
	centro.set_anchors_preset(Control.PRESET_CENTER)
	centro.anchor_left = 0.5
	centro.anchor_right = 0.5
	centro.anchor_top = 0.5
	centro.anchor_bottom = 0.5
	centro.offset_left = -260.0
	centro.offset_right = 260.0
	centro.offset_top = -50.0
	centro.offset_bottom = 50.0
	centro.add_theme_constant_override("separation", 14)
	_raiz.add_child(centro)

	_etiqueta = Label.new()
	_etiqueta.text = "CARGANDO…"
	_etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_etiqueta.add_theme_font_size_override("font_size", 26)
	_etiqueta.add_theme_color_override("font_color", Color(1.0, 0.42, 0.12))
	if ResourceLoader.exists(FONT_PATH):
		_etiqueta.add_theme_font_override("font", load(FONT_PATH))
	centro.add_child(_etiqueta)

	_barra = ProgressBar.new()
	_barra.max_value = 1.0
	_barra.value = 0.0
	_barra.show_percentage = false
	_barra.custom_minimum_size = Vector2(0, 8)
	var fondo_barra := StyleBoxFlat.new()
	fondo_barra.bg_color = Color(0.1, 0.06, 0.06, 1.0)
	var relleno := StyleBoxFlat.new()
	relleno.bg_color = Color(0.72, 0.1, 0.07, 1.0)
	relleno.border_color = Color(1.0, 0.42, 0.12, 1.0)
	_barra.add_theme_stylebox_override("background", fondo_barra)
	_barra.add_theme_stylebox_override("fill", relleno)
	centro.add_child(_barra)

	var pie := Label.new()
	pie.text = "© 2026 xpe.nettt · Stealth Proyects"
	pie.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pie.add_theme_font_size_override("font_size", 11)
	pie.add_theme_color_override("font_color", Color(0.55, 0.45, 0.4))
	centro.add_child(pie)

	_raiz.modulate.a = 0.0
	var tw := _raiz.create_tween()
	tw.tween_property(_raiz, "modulate:a", 1.0, 0.18)


func _escribir(texto: String) -> void:
	if _etiqueta != null and is_instance_valid(_etiqueta):
		_etiqueta.text = texto


func _cerrar_pantalla() -> void:
	if _pantalla == null or not is_instance_valid(_pantalla):
		return
	var transcurrido := float(Time.get_ticks_msec() - _t0) / 1000.0
	if transcurrido < MINIMO_EN_PANTALLA:
		await get_tree().create_timer(MINIMO_EN_PANTALLA - transcurrido, true, false, true).timeout
	_terminando = true
	var capa := _pantalla
	var raiz := _raiz
	_pantalla = null
	_raiz = null
	if raiz != null and is_instance_valid(raiz):
		var tw := raiz.create_tween()
		tw.tween_property(raiz, "modulate:a", 0.0, 0.22)
		await tw.finished
	if is_instance_valid(capa):
		capa.queue_free()
	_terminando = false


func cargando() -> bool:
	return _ruta != "" or _terminando
