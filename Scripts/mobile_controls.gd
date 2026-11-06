extends Control
## Controles tactiles de Boomer Shooter (iPhone, iPad y Android).
##
## Diseno: colores SOLIDOS (sin transparencias que se pierdan sobre el mapa), con la
## paleta y la fuente Geizer del resto del juego.
##   * Izquierda: palanca flotante de movimiento (aparece donde pones el dedo).
##   * Derecha: arrastrar en cualquier punto libre para apuntar.
##   * Botones: DISPARO (grande), APUNTAR, SALTO, AGACHAR, RECARGAR, CORRER, ARMA,
##     VOZ (mantener para hablar) y PAUSA.
##   * Si se conecta un mando, los controles tactiles se esconden solos; si se
##     desconecta, vuelven. Los dos funcionan a la vez sin pisarse.
## En PC (teclado y raton) este nodo esta oculto y no consume ni un ciclo.

const FONT_PATH := "res://Assets/Fonts/Geizer.otf"

const MOVE_RADIUS := 96.0
const MOVE_KNOB := 38.0
const DEADZONE := 0.18
const SPRINT_THRESHOLD := 0.92         # empujar la palanca casi al tope = correr

## Ganancia de la mira con el dedo respecto al raton (1.0 = igual que el raton). El dedo
## recorre menos pantalla que un raton sobre la mesa, asi que hace falta un poco mas.
## La friccion del aim assist se aplica encima: cerca de un enemigo la mira se frena y
## es mucho mas facil quedarse sobre el objetivo.
const LOOK_X := 1.15
const LOOK_Y := 0.85

# Paleta del juego, todo opaco.
const C_FONDO := Color(0.09, 0.05, 0.05)
const C_BORDE := Color(1.0, 0.42, 0.12)
const C_PULSADO := Color(1.0, 0.42, 0.12)
const C_FUEGO := Color(0.72, 0.1, 0.07)
const C_FUEGO_PULSADO := Color(0.95, 0.2, 0.1)
const C_TEXTO := Color(0.93, 0.86, 0.76)
const C_TEXTO_OSCURO := Color(0.09, 0.05, 0.05)
const C_PALANCA := Color(0.22, 0.12, 0.1)

## id -> {centro, radio, accion, etiqueta, color, toggle}
var _botones: Array = []
var _dedos: Dictionary = {}              # indice de dedo -> {rol, boton, inicio, actual}
var _mov_dedo := -1
var _mov_centro := Vector2.ZERO
var _mov_vec := Vector2.ZERO
var _mira_dedo := -1
var _apuntar_fijo := false
var _arma_siguiente := false
var _player: Player
var _fuente: Font
var _mando := false
var _forzar_visible := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(FONT_PATH):
		_fuente = load(FONT_PATH)
	else:
		_fuente = ThemeDB.fallback_font
	if not es_movil() and not _forzar_visible:
		visible = false
		set_process(false)
		set_process_input(false)
		return
	_mando = not Input.get_connected_joypads().is_empty()
	Input.joy_connection_changed.connect(_on_mando_cambio)
	resized.connect(_colocar_botones)
	_colocar_botones()
	_actualizar_visibilidad()


## El jugador se busca cuando hace falta, no una sola vez al arrancar: si el control
## se prepara antes de que el Player se registre en su grupo, la camara no se quedaba
## sin respuesta para siempre, pero tampoco se enteraba si el jugador se recreaba
## (al reaparecer o cambiar de mapa).
func _jugador() -> Player:
	if _player == null or not is_instance_valid(_player):
		_player = owner as Player
		if _player == null:
			_player = get_tree().get_first_node_in_group("player") as Player
	return _player


## Verdadero en iPhone, iPad y Android (y en navegadores moviles).
static func es_movil() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_ios") or OS.has_feature("web_android") \
		or DisplayServer.is_touchscreen_available() and OS.has_feature("web")


## Para pruebas y para jugar en un PC con pantalla tactil.
func forzar_visible(valor: bool) -> void:
	_forzar_visible = valor
	if valor:
		visible = true
		set_process(true)
		set_process_input(true)
		_colocar_botones()
		_actualizar_visibilidad()


func _on_mando_cambio(_dispositivo: int, _conectado: bool) -> void:
	_mando = not Input.get_connected_joypads().is_empty()
	_actualizar_visibilidad()


func _actualizar_visibilidad() -> void:
	# Con mando conectado se esconden los botones; los toques sueltos siguen sin hacer nada.
	visible = (es_movil() or _forzar_visible) and not _mando
	if not visible:
		_soltar_todo()
	queue_redraw()


## Cuanto tapan el notch / la Dynamic Island y la barra de inicio de cada lado, en
## coordenadas del juego (1920x1080). Sin notch (PC, moviles planos) devuelve ceros, asi
## que en esos equipos nada cambia. Orden: izquierda, arriba, derecha, abajo.
var _zona_simulada := Vector4(-1, -1, -1, -1)      # solo para pruebas


func zona_segura() -> Vector4:
	if _zona_simulada.x >= 0.0:
		return _zona_simulada
	var seguro: Rect2i = DisplayServer.get_display_safe_area()
	var pantalla: Vector2i = DisplayServer.screen_get_size()
	if pantalla.x <= 0 or pantalla.y <= 0 or seguro.size.x <= 0:
		return Vector4.ZERO
	var k := Vector2(size.x / float(pantalla.x), size.y / float(pantalla.y))
	var izq := maxf(0.0, float(seguro.position.x)) * k.x
	var arr := maxf(0.0, float(seguro.position.y)) * k.y
	var der := maxf(0.0, float(pantalla.x - seguro.end.x)) * k.x
	var aba := maxf(0.0, float(pantalla.y - seguro.end.y)) * k.y
	return Vector4(izq, arr, der, aba)


func _colocar_botones() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	# Todo se mide contra el alto: asi en un iPhone pequeno y en un iPad queda proporcionado.
	var u := clampf(h / 540.0, 0.8, 1.6)
	var m := 24.0 * u
	var z := zona_segura()
	# Pulgar derecho: FUEGO abajo a la derecha, rodeado por MIRA, SALTO y AGACHAR en
	# arco. Cada boton queda a mas de la suma de radios de sus vecinos (comprobado en test).
	var fuego := Vector2(w - m - z.z - 70.0 * u, h - m - z.w - 78.0 * u)
	_botones = [
		{"id": "fuego", "centro": fuego, "radio": 62.0 * u,
			"accion": "attack", "etiqueta": "FUEGO", "tipo": "fuego"},
		{"id": "apuntar", "centro": fuego + Vector2(-122.0 * u, 18.0 * u), "radio": 36.0 * u,
			"accion": "aim", "etiqueta": "MIRA", "tipo": "normal", "fijo": true},
		{"id": "salto", "centro": fuego + Vector2(-4.0 * u, -128.0 * u), "radio": 38.0 * u,
			"accion": "jump", "etiqueta": "SALTO", "tipo": "normal"},
		{"id": "agachar", "centro": fuego + Vector2(-116.0 * u, -100.0 * u), "radio": 34.0 * u,
			"accion": "crouch", "etiqueta": "AGACH", "tipo": "normal"},
		{"id": "recargar", "centro": fuego + Vector2(-214.0 * u, 36.0 * u), "radio": 34.0 * u,
			"accion": "reload", "etiqueta": "RECAR", "tipo": "normal"},
		{"id": "arma", "centro": fuego + Vector2(-214.0 * u, -66.0 * u), "radio": 34.0 * u,
			"accion": "", "etiqueta": "ARMA", "tipo": "normal"},
		{"id": "correr", "centro": Vector2(m + z.x + 56.0 * u, h - m - z.w - 258.0 * u), "radio": 34.0 * u,
			"accion": "sprint", "etiqueta": "CORRER", "tipo": "normal", "fijo": true},
		{"id": "voz", "centro": Vector2(m + z.x + 40.0 * u, z.y + 118.0 * u), "radio": 34.0 * u,
			"accion": "push_to_talk", "etiqueta": "VOZ", "tipo": "normal"},
		{"id": "pausa", "centro": Vector2(w - m - z.z - 34.0 * u, z.y + 62.0 * u), "radio": 28.0 * u,
			"accion": "", "etiqueta": "II", "tipo": "normal"},
	]
	queue_redraw()


# ---------------------------------------------------------------- dibujo

func _draw() -> void:
	if not visible:
		return
	for b in _botones:
		_dibujar_boton(b)
	if _mov_dedo >= 0:
		draw_circle(_mov_centro, MOVE_RADIUS * _escala(), C_FONDO)
		draw_arc(_mov_centro, MOVE_RADIUS * _escala(), 0.0, TAU, 48, C_BORDE, 4.0)
		var pos := _mov_centro + _mov_vec * MOVE_RADIUS * _escala()
		draw_circle(pos, MOVE_KNOB * _escala(), C_PULSADO)
	else:
		# Pista fija de donde poner el dedo para moverse (se esconde al tocar).
		var c := _centro_palanca_reposo()
		draw_circle(c, MOVE_RADIUS * _escala(), C_FONDO)
		draw_arc(c, MOVE_RADIUS * _escala(), 0.0, TAU, 48, C_BORDE, 3.0)
		draw_circle(c, MOVE_KNOB * _escala(), C_PALANCA)
		draw_arc(c, MOVE_KNOB * _escala(), 0.0, TAU, 32, C_BORDE, 2.0)


func _dibujar_boton(b: Dictionary) -> void:
	var c: Vector2 = b["centro"]
	var r: float = b["radio"]
	var pulsado := _boton_pulsado(b)
	var fuego: bool = b["tipo"] == "fuego"
	var relleno := C_FONDO
	if fuego:
		relleno = C_FUEGO_PULSADO if pulsado else C_FUEGO
	elif pulsado:
		relleno = C_PULSADO
	draw_circle(c, r, relleno)
	draw_arc(c, r, 0.0, TAU, 40, C_TEXTO if fuego else C_BORDE, 4.0)
	var tam := int(clampf(r * 0.34, 11.0, 26.0))
	var color_texto := C_TEXTO_OSCURO if (pulsado and not fuego) else C_TEXTO
	var etiqueta: String = b["etiqueta"]
	var ancho := _fuente.get_string_size(etiqueta, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	draw_string(_fuente, c + Vector2(-ancho * 0.5, tam * 0.36), etiqueta,
		HORIZONTAL_ALIGNMENT_LEFT, -1, tam, color_texto)


func _escala() -> float:
	return clampf(size.y / 540.0, 0.8, 1.6)


func _centro_palanca_reposo() -> Vector2:
	var u := _escala()
	return Vector2(40.0 * u + MOVE_RADIUS * u, size.y - 40.0 * u - MOVE_RADIUS * u)


func _boton_pulsado(b: Dictionary) -> bool:
	if b.get("fijo", false):
		if b["id"] == "apuntar":
			return _apuntar_fijo
		if b["id"] == "correr":
			return _correr_fijo
	for d in _dedos.values():
		if d["rol"] == "boton" and d["boton"] == b["id"]:
			return true
	return false


# ---------------------------------------------------------------- entrada

var _correr_fijo := false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_pulsar(t.index, t.position)
		else:
			_soltar(t.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_arrastrar(d.index, d.position, d.relative)
		get_viewport().set_input_as_handled()


func _boton_en(pos: Vector2) -> Dictionary:
	# Margen de 1.12x para el dedo gordo, pero si dos botones coinciden gana el que
	# tiene el centro mas cerca del dedo.
	var mejor := {}
	var mejor_d := INF
	for b in _botones:
		var d: float = pos.distance_to(b["centro"])
		if d <= float(b["radio"]) * 1.12 and d < mejor_d:
			mejor = b
			mejor_d = d
	return mejor


func _pulsar(indice: int, pos: Vector2) -> void:
	var b := _boton_en(pos)
	if not b.is_empty():
		_dedos[indice] = {"rol": "boton", "boton": b["id"]}
		_accion_boton(b, true)
		queue_redraw()
		return
	# Mitad izquierda: palanca de movimiento flotante. Derecha: mirar.
	if pos.x < size.x * 0.5 and _mov_dedo < 0:
		_mov_dedo = indice
		_mov_centro = pos
		_mov_vec = Vector2.ZERO
		_dedos[indice] = {"rol": "mover"}
	elif pos.x >= size.x * 0.5 and _mira_dedo < 0:
		_mira_dedo = indice
		_dedos[indice] = {"rol": "mirar"}
	queue_redraw()


func _soltar(indice: int) -> void:
	if not _dedos.has(indice):
		return
	var d: Dictionary = _dedos[indice]
	_dedos.erase(indice)
	match d["rol"]:
		"boton":
			for b in _botones:
				if b["id"] == d["boton"]:
					_accion_boton(b, false)
		"mover":
			_mov_dedo = -1
			_mov_vec = Vector2.ZERO
			_aplicar_movimiento()
		"mirar":
			_mira_dedo = -1
	queue_redraw()


func _arrastrar(indice: int, pos: Vector2, relativo: Vector2) -> void:
	if not _dedos.has(indice):
		return
	var rol: String = _dedos[indice]["rol"]
	if rol == "mover":
		var delta := pos - _mov_centro
		var radio := MOVE_RADIUS * _escala()
		_mov_vec = delta.limit_length(radio) / radio
		# Si arrastras mas alla del aro, la palanca te sigue (no hay que re-tocar).
		if delta.length() > radio * 1.6:
			_mov_centro += delta.normalized() * (delta.length() - radio * 1.6)
		_aplicar_movimiento()
		queue_redraw()
	elif rol == "mirar" and _jugador() != null:
		_girar(relativo)


## La mira con el dedo pasa por la misma ruta que el raton, asi hereda el zoom al apuntar
## y la friccion del aim assist (frena cerca de un enemigo). En movil la friccion es mas
## fuerte que en PC: con un dedo es mucho mas dificil ser preciso que con un raton.
func _girar(relativo: Vector2) -> void:
	# Misma escala que el raton: Player._unhandled_input mete -relativo * sensibilidad
	# y update_camera lo multiplica por delta. Aqui igual, sin factores extra.
	var ajuste: float = GameSettings.mouse_sensitivity if GameSettings else 0.33
	var apuntando := Input.is_action_pressed("aim")
	var jugador := _jugador()
	var factor: float = jugador._aa_friccion
	factor = lerpf(factor, factor * factor, 0.5)        # friccion reforzada en tactil
	if apuntando:
		factor *= jugador.ADS_SENSITIVITY_MULTIPLIER
	jugador._rotation_input += -relativo.x * ajuste * LOOK_X * factor
	jugador._tilt_input += -relativo.y * ajuste * LOOK_Y * factor


func _aplicar_movimiento() -> void:
	var v := _mov_vec
	_set_accion("move_left", v.x < -DEADZONE, absf(minf(v.x, 0.0)))
	_set_accion("move_right", v.x > DEADZONE, maxf(v.x, 0.0))
	_set_accion("move_forward", v.y < -DEADZONE, absf(minf(v.y, 0.0)))
	_set_accion("move_backward", v.y > DEADZONE, maxf(v.y, 0.0))
	# Empujar la palanca casi al tope hacia delante = correr, sin boton extra.
	var correr := v.length() >= SPRINT_THRESHOLD and v.y < -0.5
	_set_accion("sprint", correr or _correr_fijo, 1.0)


func _accion_boton(b: Dictionary, pulsado: bool) -> void:
	match b["id"]:
		"apuntar":
			# Apuntar es un interruptor: un toque lo deja puesto, otro lo quita.
			if pulsado:
				_apuntar_fijo = not _apuntar_fijo
				_set_accion("aim", _apuntar_fijo, 1.0)
		"correr":
			if pulsado:
				_correr_fijo = not _correr_fijo
				_set_accion("sprint", _correr_fijo, 1.0)
		"arma":
			if pulsado:
				_siguiente_arma()
		"pausa":
			if pulsado:
				_pausar()
		_:
			var accion: String = b["accion"]
			if accion != "":
				_set_accion(accion, pulsado, 1.0)


func _siguiente_arma() -> void:
	var gestor := get_tree().get_first_node_in_group("weapon_manager")
	if gestor == null or not ("current_index" in gestor):
		return
	var total: int = (gestor.weapons as Array).size()
	if total <= 1:
		return
	gestor.equip((int(gestor.current_index) + 1) % total)


func _pausar() -> void:
	# Mismo camino que la tecla ESC para que el menu de pausa abra y cierre igual.
	var ev := InputEventAction.new()
	ev.action = "exit"
	ev.pressed = true
	Input.parse_input_event(ev)
	var ev2 := InputEventAction.new()
	ev2.action = "exit"
	ev2.pressed = false
	Input.parse_input_event(ev2)


func _set_accion(accion: StringName, pulsado: bool, fuerza: float) -> void:
	if not InputMap.has_action(accion):
		return
	if pulsado:
		Input.action_press(accion, clampf(fuerza, 0.0, 1.0))
	else:
		Input.action_release(accion)


func _soltar_todo() -> void:
	for d in _dedos.keys().duplicate():
		_soltar(d)
	_dedos.clear()
	_mov_dedo = -1
	_mira_dedo = -1
	_mov_vec = Vector2.ZERO
	for a in ["move_left", "move_right", "move_forward", "move_backward", "attack", "jump",
			"crouch", "reload", "push_to_talk"]:
		_set_accion(a, false, 0.0)
	if not _apuntar_fijo:
		_set_accion("aim", false, 0.0)
	if not _correr_fijo:
		_set_accion("sprint", false, 0.0)


func _notification(what: int) -> void:
	# Al cambiar de app o pausar el sistema se sueltan todos los botones: si no, el
	# personaje se queda caminando solo al volver.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_soltar_todo()
