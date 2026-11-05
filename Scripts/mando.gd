extends Node
## Mando (gamepad): el juego detecta y usa cualquier mando conectado sin configurar nada.
##
## Los ajustes del juego ya permiten reasignar teclas y botones, pero el proyecto no
## traia ningun mando por defecto: quien enchufaba un control no podia jugar hasta
## cambiarlo a mano. Aqui se instalan las acciones basicas la primera vez que arranca
## el juego, sin pisar lo que el jugador haya reasignado (solo se anade si la accion
## no tiene ya ningun evento de mando).

signal mando_conectado(nombre: String)
signal mando_desconectado(nombre: String)

## (accion, tipo, indice, valor). tipo "boton" o "eje".
## Los indices son el estandar de Godot para mandos tipo Xbox/PlayStation:
## 0 A/cruz, 1 B/circulo, 2 X/cuadrado, 3 Y/triangulo, 9 LB/L1, 10 RB/R1,
## 11 dpad arriba, 12 abajo, 13 izquierda, 14 derecha; ejes 0/1 palanca izquierda,
## 2/3 palanca derecha, 4/5 gatillos.
const DEFECTOS := [
	{"accion": "move_forward", "tipo": "eje", "indice": 1, "valor": -1.0},
	{"accion": "move_backward", "tipo": "eje", "indice": 1, "valor": 1.0},
	{"accion": "move_left", "tipo": "eje", "indice": 0, "valor": -1.0},
	{"accion": "move_right", "tipo": "eje", "indice": 0, "valor": 1.0},
	{"accion": "look_left", "tipo": "eje", "indice": 2, "valor": -1.0},
	{"accion": "look_right", "tipo": "eje", "indice": 2, "valor": 1.0},
	{"accion": "look_up", "tipo": "eje", "indice": 3, "valor": -1.0},
	{"accion": "look_down", "tipo": "eje", "indice": 3, "valor": 1.0},
	{"accion": "jump", "tipo": "boton", "indice": 0},
	{"accion": "crouch", "tipo": "boton", "indice": 1},
	{"accion": "reload", "tipo": "boton", "indice": 2},
	{"accion": "interact", "tipo": "boton", "indice": 3},
	{"accion": "attack", "tipo": "boton", "indice": 10},
	{"accion": "attack", "tipo": "eje", "indice": 5, "valor": 1.0},
	{"accion": "aim", "tipo": "eje", "indice": 4, "valor": 1.0},
	{"accion": "sprint", "tipo": "boton", "indice": 8},
	{"accion": "weapon_wheel", "tipo": "boton", "indice": 9},
	{"accion": "help_call", "tipo": "boton", "indice": 11},
	{"accion": "ping_mark", "tipo": "boton", "indice": 12},
	{"accion": "ui_accept", "tipo": "boton", "indice": 0},
	{"accion": "ui_cancel", "tipo": "boton", "indice": 1},
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	instalar_defectos()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## Instala los botones por defecto. Es idempotente: si la accion ya tiene eventos de
## mando (aunque sean otros), no se toca.
func instalar_defectos() -> void:
	for d in DEFECTOS:
		var accion := str(d["accion"])
		if not InputMap.has_action(accion):
			InputMap.add_action(accion)
		if _tiene_mando(accion):
			continue
		InputMap.action_add_event(accion, _evento(d))


func _evento(d: Dictionary) -> InputEvent:
	if str(d["tipo"]) == "boton":
		var b := InputEventJoypadButton.new()
		b.button_index = int(d["indice"])
		b.pressed = true
		return b
	var m := InputEventJoypadMotion.new()
	m.axis = int(d["indice"])
	m.axis_value = float(d.get("valor", 1.0))
	return m


func _tiene_mando(accion: String) -> bool:
	for ev in InputMap.action_get_events(accion):
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			return true
	return false


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	var nombre := Input.get_joy_name(device)
	if nombre.strip_edges() == "":
		nombre = "Mando %d" % device
	if connected:
		avisar("MANDO CONECTADO: " + nombre)
		mando_conectado.emit(nombre)
	else:
		avisar("MANDO DESCONECTADO")
		mando_desconectado.emit(nombre)


## Aviso en pantalla reutilizando el sistema de mensajes del juego.
func avisar(texto: String) -> void:
	if OS.is_debug_build():
		print(texto)
	var alerts := get_node_or_null("/root/TeamAlerts")
	if alerts != null and alerts.has_method("banner_del_sistema"):
		alerts.banner_del_sistema(texto, 1)
		return
	if alerts != null and alerts.has_method("_show_banner"):
		alerts._show_banner(texto, 1)
		return
	var chat := get_node_or_null("/root/GameChat")
	if chat != null and chat.has_method("show_system_message"):
		chat.show_system_message(texto)


func mando_activo() -> bool:
	return Input.get_connected_joypads().size() > 0


func nombre_mando() -> String:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return ""
	return Input.get_joy_name(int(pads[0]))
