extends CanvasLayer

# Match chat presentation. Transport is intentionally separate: gameplay chat is
# only enabled after the server-side match authority is installed.
#
# El chat es de PARTIDA. Como es un autoload existe siempre, asi que se vigila la escena:
# en cualquier menu (menu principal, lobby, tienda, logros...) se oculta, se vacia y Enter
# no hace nada; al empezar otra partida arranca limpio, sin las lineas de la anterior.
const MAX_LINES := 6

## Escenas donde NO hay partida: el chat no se ve ni se puede abrir. Por archivo y no por el
## nombre del nodo: "Shop" y "Achievements" chocan con autoloads y Godot las renombra.
const ESCENAS_MENU := [
	"res://Levels/MainMenu.tscn", "res://Levels/Lobby.tscn", "res://Levels/ArenaSelect.tscn",
	"res://Levels/Shop.tscn", "res://Levels/Achievements.tscn",
]

var _panel: PanelContainer
var _history: RichTextLabel
var _entry: LineEdit
var _open := false
var _lines: Array[String] = []
var _en_partida := false
var _escena_id := 0   # instancia de la escena activa: cambia con cada mapa nuevo


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_interface()
	_vigilar_escena()


## True si la escena es un menu (sin partida).
static func es_menu_escena(escena: Node) -> bool:
	return escena != null and escena.scene_file_path in ESCENAS_MENU


func _vigilar_escena() -> void:
	# Un fotograma de margen: current_scene aun es null al arrancar el autoload.
	await get_tree().process_frame
	while true:
		await get_tree().process_frame
		_sincronizar_escena()


## Pone _en_partida al dia con la escena activa; al cambiar, limpia el chat.
func _sincronizar_escena() -> void:
	var escena := get_tree().current_scene
	if escena == null:
		return
	var en_partida := not es_menu_escena(escena)
	var nueva := escena.get_instance_id() != _escena_id
	_escena_id = escena.get_instance_id()
	# Una partida nueva (aunque venga de otra partida, sin pasar por un menu) empieza con el
	# chat limpio: las lineas de la anterior no se arrastran.
	if en_partida and nueva and _en_partida:
		_limpiar()
	if en_partida == _en_partida:
		return
	_en_partida = en_partida
	if en_partida:
		_limpiar()
	else:
		salir_de_partida()


## Al volver a un menu: cierra el chat, borra el historial y lo esconde.
func salir_de_partida() -> void:
	_limpiar()
	if _panel:
		_panel.visible = false


func _limpiar() -> void:
	_lines.clear()
	if _history:
		_history.text = ""
	_open = false
	if _entry:
		_entry.clear()
		_entry.release_focus()
	if _panel:
		_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _en_partida:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		if _open:
			_submit()
		else:
			_open_chat()
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("ui_cancel"):
		_close_chat()
		get_viewport().set_input_as_handled()


func show_system_message(message: String) -> void:
	_add_line("[color=#ffad45]SISTEMA[/color]: %s" % message)


func receive_match_message(sender: String, message: String) -> void:
	_add_line("[color=#d8e7ff]%s[/color]: %s" % [sender.strip_edges().left(24), message.strip_edges().left(180)])


## Color de cada bando en el chat, para saber de un vistazo quien habla.
const COLOR_ROL := {"pandilla": "#ff6b5b", "solo": "#ffb347", "amigo": "#7dffa1", "entrenado": "#9ec5ff"}


## Frase de un bot. El nombre y el texto vienen del servidor (y llevan nombres de jugadores), asi que se
## escapan los corchetes: sin esto un nombre con "[b]" o "[url]" rompe o manipula el formato del chat.
func receive_bot_message(nombre: String, texto: String, rol: String) -> void:
	var color: String = COLOR_ROL.get(rol, "#d8e7ff")
	_add_line("[color=%s]%s[/color]: %s" % [color, _escapar(nombre.strip_edges().left(24)), _escapar(texto.strip_edges().left(200))])


static func _escapar(t: String) -> String:
	# Un solo paso, caracter a caracter: encadenar dos replace() volvia a tocar el "]" de "[lb]".
	var salida := ""
	for c in t:
		if c == "[":
			salida += "[lb]"
		elif c == "]":
			salida += "[rb]"
		else:
			salida += c
	return salida


func _create_interface() -> void:
	_panel = PanelContainer.new()
	# El chat va arriba a la izquierda para no taparse con el contador de vida,
	# que vive abajo a la izquierda.
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(20, 20)
	_panel.size = Vector2(420, 185)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_history = RichTextLabel.new()
	_history.bbcode_enabled = true
	_history.fit_content = true
	_history.scroll_active = false
	_history.custom_minimum_size.y = 120
	_history.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_history)
	_entry = LineEdit.new()
	_entry.placeholder_text = "Escribe un mensaje..."
	_entry.max_length = 180
	_entry.text_submitted.connect(func(_value: String): _submit())
	box.add_child(_entry)
	_close_chat()


func _open_chat() -> void:
	_open = true
	_panel.visible = true
	_entry.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_chat() -> void:
	_open = false
	if _entry:
		_entry.clear()
	if _panel:
		_panel.visible = not _lines.is_empty()


func _submit() -> void:
	var message := _entry.text.strip_edges()
	if message.is_empty():
		_close_chat()
		return
	# The call site for network replication is added with the authoritative match.
	receive_match_message(OnlineManager.username if not OnlineManager.username.is_empty() else "Jugador", message)
	_entry.clear()
	_close_chat()


func _add_line(line: String) -> void:
	# Se mira la escena en este instante (no solo la ultima vigilada): asi un aviso que llega
	# en el primer fotograma de un mapa no se pierde, y uno que llega en un menu se descarta.
	_sincronizar_escena()
	if not _en_partida:
		return
	_lines.append(line)
	if _lines.size() > MAX_LINES:
		_lines.pop_front()
	_history.text = "\n".join(_lines)
	_panel.visible = true


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.02, 0.045, 0.84)
	style.border_color = Color(1.0, 0.3, 0.12, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style
