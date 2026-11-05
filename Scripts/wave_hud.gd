extends CanvasLayer

## HUD de oleadas: muestra el numero de oleada y cuantos hostiles siguen vivos.
## El contador baja solo a medida que mueren y desaparece cuando no queda ninguno.

const ACCENT := Color(0.95, 0.35, 0.15)
const CREAM := Color(0.93, 0.9, 0.85)
const REFRESH := 0.15
const CLEAR_HOLD := 2.2

var _title: Label
var _detail: Label
var _box: VBoxContainer
var _director: SpawnManager
var _enemies: Node

var _state: String = "idle"
var _wave: int = 0
var _alive: int = -1
var _refresh: float = 0.0
var _clear_timer: float = 0.0
var _pending_countdown: int = -1
var _sala: Label   # rotulo fijo con el codigo de la sala, para decirselo a un amigo


func _ready() -> void:
	layer = 4
	_box = VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_box.offset_left = -420.0
	_box.offset_top = 26.0
	_box.offset_right = 420.0
	_box.offset_bottom = 140.0
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 2)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)

	_title = _make_label(38, ACCENT, 10)
	_detail = _make_label(24, CREAM, 8)
	_box.add_child(_title)
	_box.add_child(_detail)
	_box.visible = false
	_construir_rotulo_sala()
	call_deferred("_connect_director")


func _make_label(font_size: int, color: Color, outline: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.01))
	label.add_theme_constant_override("outline_size", outline)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _connect_director() -> void:
	if not is_inside_tree():
		return
	_director = get_tree().get_first_node_in_group("wave_director") as SpawnManager
	if _director == null:
		return
	_director.wave_countdown.connect(_on_wave_countdown)
	_director.wave_started.connect(_on_wave_started)
	_director.wave_completed.connect(_on_wave_completed)
	_enemies = get_tree().current_scene.find_child("Enemies", true, false) if get_tree().current_scene else null


func _process(delta: float) -> void:
	if _state == "cleared":
		_clear_timer -= delta
		if _clear_timer > 0.0:
			return
		if _pending_countdown > 0:
			_state = "countdown"
			_title.text = "OLEADA %d EN %d" % [_wave + 1, _pending_countdown]
			_detail.text = "PREPARATE"
		else:
			_state = "idle"
			_box.visible = false
		return
	if _state != "combat":
		return
	_refresh += delta
	if _refresh < REFRESH:
		return
	_refresh = 0.0
	var alive := _count_alive()
	if alive == _alive:
		return
	_alive = alive
	if alive <= 0:
		return
	_detail.text = "%d %s" % [alive, "HOSTIL" if alive == 1 else "HOSTILES"]


## Cuenta solo enemigos vivos: los cadaveres tardan un segundo en liberarse.
func _count_alive() -> int:
	if _enemies == null or not is_instance_valid(_enemies):
		if get_tree().current_scene:
			_enemies = get_tree().current_scene.find_child("Enemies", true, false)
		if _enemies == null:
			return 0
	var total := 0
	for child in _enemies.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		# Duck typing: cualquier enemigo que no este marcado como muerto cuenta.
		var is_dead = child.get("dead")
		if is_dead == null or is_dead == false:
			total += 1
	return total


func _on_wave_countdown(seconds_left: int) -> void:
	_pending_countdown = seconds_left
	# Si acaba de caer la oleada, se respeta el cartel de SUPERADA y la cuenta
	# atras aparece en la linea de abajo en vez de borrarlo.
	if _state == "cleared":
		_detail.text = "SIGUIENTE EN %d" % seconds_left
		return
	_state = "countdown"
	_wave = _director.current_wave + 1 if _director != null else _wave
	_box.visible = true
	_box.modulate.a = 1.0
	_title.text = "OLEADA %d EN %d" % [_wave, seconds_left]
	_detail.text = "PREPARATE"


func _on_wave_started(wave_number: int, enemy_count: int, has_elite: bool) -> void:
	_state = "combat"
	_wave = wave_number
	_alive = enemy_count
	_refresh = 0.0
	_box.visible = true
	_box.modulate.a = 1.0
	_title.text = "OLEADA %d" % wave_number
	_detail.text = "%d HOSTILES%s" % [enemy_count, "  ·  ELITE" if has_elite else ""]
	_flash()


func _on_wave_completed(wave_number: int) -> void:
	_state = "cleared"
	_clear_timer = CLEAR_HOLD
	_title.text = "OLEADA %d SUPERADA" % wave_number
	_detail.text = "TOMA AIRE"
	_box.modulate.a = 1.0


func _flash() -> void:
	_title.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_title, "modulate:a", 1.0, 0.22)


## Esquina superior izquierda: "SALA K7M2Q · PRIVADA". Solo aparece en partidas online.
func _construir_rotulo_sala() -> void:
	_sala = Label.new()
	_sala.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_sala.offset_left = 18.0
	_sala.offset_top = 12.0
	_sala.add_theme_font_size_override("font_size", 20)
	_sala.add_theme_color_override("font_color", CREAM)
	_sala.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.01))
	_sala.add_theme_constant_override("outline_size", 6)
	_sala.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sala)
	var om = get_node_or_null("/root/OnlineManager")
	if om != null and om.has_signal("room_code_changed"):
		om.room_code_changed.connect(_on_codigo_sala)
		_on_codigo_sala(str(om.get("room_code")))
	else:
		_sala.visible = false


func _on_codigo_sala(codigo: String) -> void:
	if _sala == null:
		return
	if codigo == "":
		_sala.visible = false
		return
	var om = get_node_or_null("/root/OnlineManager")
	var privada: bool = om != null and bool(om.get("room_private"))
	_sala.text = "SALA  %s  ·  %s" % [codigo, "PRIVADA" if privada else "PUBLICA"]
	_sala.visible = true
