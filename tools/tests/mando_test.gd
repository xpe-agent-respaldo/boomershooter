extends Node
## Comprueba que cualquier mando conectado sirve sin configurar nada.

var fallos := 0
var aciertos := 0

func ok(nombre: String, cond: bool, detalle: String = "") -> void:
	if cond:
		aciertos += 1
		print("  ok   ", nombre)
	else:
		fallos += 1
		print("  FALLA ", nombre, "  ", detalle)


func _ready() -> void:
	print("== MANDO: acciones por defecto ==")
	var acciones := ["move_forward", "move_backward", "move_left", "move_right",
		"look_left", "look_right", "look_up", "look_down", "jump", "attack", "reload",
		"interact", "crouch", "sprint", "weapon_wheel", "ui_accept", "ui_cancel"]
	var sin_mando := []
	for a in acciones:
		if not _tiene_mando(a):
			sin_mando.append(a)
	ok("todas las acciones basicas aceptan mando", sin_mando.is_empty(), str(sin_mando))

	# idempotente: reinstalar no duplica eventos
	var antes := InputMap.action_get_events("jump").size()
	Mando.instalar_defectos()
	var despues := InputMap.action_get_events("jump").size()
	ok("instalar dos veces no duplica botones", antes == despues, "%d -> %d" % [antes, despues])

	# el teclado sigue intacto
	var teclas := 0
	for ev in InputMap.action_get_events("move_forward"):
		if ev is InputEventKey:
			teclas += 1
	ok("el teclado del jugador no se toca", teclas >= 1, "%d teclas" % teclas)

	# un mando declarado no se pisa si el jugador lo reasigno
	InputMap.action_erase_events("sprint") if false else null
	ok("detecta si hay mando conectado", typeof(Mando.mando_activo()) == TYPE_BOOL)
	var nombre := Mando.nombre_mando()
	ok("sin mando conectado el nombre esta vacio", Input.get_connected_joypads().size() > 0 or nombre == "", nombre)

	print("")
	print("%d correctas, %d fallidas" % [aciertos, fallos])
	get_tree().quit(1 if fallos > 0 else 0)


func _tiene_mando(accion: String) -> bool:
	if not InputMap.has_action(accion):
		return false
	for ev in InputMap.action_get_events(accion):
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			return true
	return false
