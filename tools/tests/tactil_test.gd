extends Node
## Controles tactiles de iPhone/Android: se simulan dedos reales dentro de una partida
## y se comprueba que cada boton llega al juego. Se ejecuta en un nivel de verdad.

var fallos := 0
var aciertos := 0
var ctrl: Control
var jugador: Player


func ok(nombre: String, cond: bool, detalle: String = "") -> void:
	if cond:
		aciertos += 1
		print("  ok   ", nombre)
	else:
		fallos += 1
		print("  FALLA ", nombre, "  ", detalle)


## Los toques reales llegan en coordenadas de VENTANA y el motor los pasa a coordenadas
## de contenido (1920x1080). Para simularlos hay que dar el camino inverso.
func _a_ventana(pos: Vector2) -> Vector2:
	var ventana := Vector2(get_window().size)
	return pos * (ventana / Vector2(1920.0, 1080.0))


func _toque(indice: int, pos: Vector2, pulsado: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = indice
	e.position = _a_ventana(pos)
	e.pressed = pulsado
	Input.parse_input_event(e)


func _arrastre(indice: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = indice
	e.position = _a_ventana(pos)
	e.relative = _a_ventana(rel)
	Input.parse_input_event(e)


func _centro(id: String) -> Vector2:
	for b in ctrl._botones:
		if b["id"] == id:
			return b["centro"]
	return Vector2(-1, -1)


func _esperar(frames: int = 3) -> void:
	for i in frames:
		await get_tree().process_frame


func _ready() -> void:
	print("== TACTIL: partida real ==")
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1920, 1080)
	var nivel: Node = load("res://Levels/SpaceArena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(nivel)
	await _esperar(40)
	jugador = get_tree().get_first_node_in_group("player") as Player
	ok("hay un jugador en la partida", jugador != null)
	if jugador == null:
		_fin()
		return
	ctrl = jugador.get_node_or_null("UI/MobileControls")
	ok("los controles tactiles existen en el jugador", ctrl != null)
	if ctrl == null:
		_fin()
		return
	ctrl.forzar_visible(true)
	ctrl._mando = false
	ctrl._actualizar_visibilidad()
	await _esperar(5)
	ok("se ven en un movil", ctrl.visible)
	ok("hay 9 botones", ctrl._botones.size() == 9, str(ctrl._botones.size()))

	var solapes: Array = []
	for a in range(ctrl._botones.size()):
		for k in range(a + 1, ctrl._botones.size()):
			var A: Dictionary = ctrl._botones[a]
			var B: Dictionary = ctrl._botones[k]
			if A["centro"].distance_to(B["centro"]) < (float(A["radio"]) + float(B["radio"])) * 1.12:
				solapes.append("%s/%s" % [A["id"], B["id"]])
	ok("ningun boton se solapa con otro", solapes.is_empty(), str(solapes))
	var fuera: Array = []
	for b in ctrl._botones:
		var c: Vector2 = b["centro"]
		var r: float = b["radio"]
		if c.x - r < 0.0 or c.y - r < 0.0 or c.x + r > ctrl.size.x or c.y + r > ctrl.size.y:
			fuera.append(b["id"])
	ok("todos los botones caben en pantalla", fuera.is_empty(), str(fuera))

	print("== TACTIL: zona segura (notch de iPhone) ==")
	var sin_notch: Dictionary = {}
	for b in ctrl._botones:
		sin_notch[b["id"]] = b["centro"]
	ctrl._zona_simulada = Vector4(120.0, 40.0, 120.0, 50.0)       # muesca lateral + barra de inicio
	ctrl._colocar_botones()
	var con_notch: Dictionary = {}
	for b in ctrl._botones:
		con_notch[b["id"]] = b["centro"]
	ok("con notch FUEGO se aleja del borde derecho", con_notch["fuego"].x < sin_notch["fuego"].x - 100.0,
		"%s -> %s" % [sin_notch["fuego"], con_notch["fuego"]])
	ok("con notch PAUSA baja para no taparse con la muesca", con_notch["pausa"].y > sin_notch["pausa"].y + 30.0)
	ok("con notch VOZ se aleja del borde izquierdo", con_notch["voz"].x > sin_notch["voz"].x + 100.0)
	var tapados: Array = []
	for b in ctrl._botones:
		var c: Vector2 = b["centro"]
		var r: float = b["radio"]
		if c.x - r < 120.0 or c.x + r > ctrl.size.x - 120.0 or c.y + r > ctrl.size.y - 50.0 or c.y - r < 40.0:
			tapados.append(b["id"])
	ok("con notch ningun boton queda bajo la muesca", tapados.is_empty(), str(tapados))
	var solapes2: Array = []
	for a in range(ctrl._botones.size()):
		for k in range(a + 1, ctrl._botones.size()):
			var A: Dictionary = ctrl._botones[a]
			var B: Dictionary = ctrl._botones[k]
			if A["centro"].distance_to(B["centro"]) < (float(A["radio"]) + float(B["radio"])) * 1.12:
				solapes2.append("%s/%s" % [A["id"], B["id"]])
	ok("con notch tampoco se solapan", solapes2.is_empty(), str(solapes2))
	ctrl._zona_simulada = Vector4(-1, -1, -1, -1)
	ctrl._colocar_botones()

	print("== TACTIL: botones ==")
	var mapa := {"fuego": "attack", "salto": "jump", "agachar": "crouch", "recargar": "reload", "voz": "push_to_talk"}
	for id in mapa:
		var pos: Vector2 = _centro(id)
		_toque(10, pos, true)
		await _esperar(2)
		ok("%s pulsa %s" % [id, mapa[id]], Input.is_action_pressed(mapa[id]))
		_toque(10, pos, false)
		await _esperar(2)
		ok("%s suelta %s" % [id, mapa[id]], not Input.is_action_pressed(mapa[id]))

	# apuntar y correr son interruptores
	_toque(11, _centro("apuntar"), true)
	await _esperar(2)
	_toque(11, _centro("apuntar"), false)
	await _esperar(2)
	ok("apuntar se queda puesto al soltar el dedo", Input.is_action_pressed("aim"))
	_toque(11, _centro("apuntar"), true)
	await _esperar(2)
	_toque(11, _centro("apuntar"), false)
	await _esperar(2)
	ok("un segundo toque quita apuntar", not Input.is_action_pressed("aim"))

	_toque(12, _centro("correr"), true)
	await _esperar(2)
	_toque(12, _centro("correr"), false)
	await _esperar(2)
	ok("correr se queda puesto", Input.is_action_pressed("sprint"))
	_toque(12, _centro("correr"), true)
	await _esperar(2)
	_toque(12, _centro("correr"), false)
	await _esperar(2)
	ok("un segundo toque quita correr", not Input.is_action_pressed("sprint"))

	print("== TACTIL: movimiento (palanca flotante) ==")
	var inicio := Vector2(200, 820)
	_toque(1, inicio, true)
	await _esperar(2)
	_arrastre(1, inicio + Vector2(0, -60), Vector2(0, -60))
	await _esperar(2)
	ok("palanca arriba camina hacia delante", Input.is_action_pressed("move_forward"))
	ok("no camina hacia atras", not Input.is_action_pressed("move_backward"))
	_arrastre(1, inicio + Vector2(80, -60), Vector2(80, 0))
	await _esperar(2)
	ok("palanca a la derecha anade strafe", Input.is_action_pressed("move_right"))
	_arrastre(1, inicio + Vector2(0, -150), Vector2(-80, -90))
	await _esperar(2)
	ok("empujar al tope arriba activa correr", Input.is_action_pressed("sprint"))
	_toque(1, inicio, false)
	await _esperar(2)
	ok("al soltar se detiene todo", not Input.is_action_pressed("move_forward")
		and not Input.is_action_pressed("move_right") and not Input.is_action_pressed("sprint"))

	print("== TACTIL: multitoque (mover + mirar + disparar a la vez) ==")
	_toque(1, inicio, true)
	_arrastre(1, inicio + Vector2(0, -70), Vector2(0, -70))
	_toque(2, Vector2(1150, 330), true)
	_toque(3, _centro("fuego"), true)
	await _esperar(3)
	ok("camina mientras apunta y dispara", Input.is_action_pressed("move_forward")
		and Input.is_action_pressed("attack"))
	var antes: float = jugador._mouse_rotation.y
	_arrastre(2, Vector2(1190, 330), Vector2(40, 0))
	await _esperar(4)
	var despues: float = jugador._mouse_rotation.y
	ok("arrastrar a la derecha gira la camara", absf(despues - antes) > 0.0001,
		"%.5f -> %.5f" % [antes, despues])
	_toque(3, _centro("fuego"), false)
	_toque(2, Vector2(1190, 330), false)
	_toque(1, inicio, false)
	await _esperar(3)
	ok("al soltar todos los dedos no queda nada pulsado", not Input.is_action_pressed("move_forward")
		and not Input.is_action_pressed("attack"))

	print("== TACTIL: aim assist ==")
	# El director de oleadas se congela: si no, spawnea enemigos reales a mitad de la prueba
	# y la medicion depende del azar.
	var congelar := get_tree().get_first_node_in_group("wave_director")
	if congelar != null:
		congelar.set_process(false)
		congelar.set_physics_process(false)
	for n in get_tree().get_nodes_in_group("enemy"):
		n.queue_free()
	await _esperar(3)
	await _giro_por_arrastre()
	var giro_libre: float = _ultimo_giro
	ok("un arrastre de 40 px gira un angulo razonable (ni trompo ni nada)",
		giro_libre > 0.02 and giro_libre < 1.2, "%.3f rad" % giro_libre)

	# Con un enemigo REAL justo delante de la mira: la friccion del aim assist debe frenar.
	var camara: Camera3D = jugador.CAMERA_CONTROLLER
	var director := get_tree().get_first_node_in_group("wave_director")
	var escena: PackedScene = director.enemy_scene if director != null else null
	ok("el nivel trae una escena de enemigo", escena != null)
	if escena == null:
		_fin()
		return
	ok("hay una direccion con 5 m de linea de vista libre", await _mirar_hacia_despejado(4.0))
	var enemigo: Node3D = escena.instantiate()
	enemigo.add_to_group("enemy")                       # igual que hace SpawnManager al spawnear
	get_tree().current_scene.add_child(enemigo)
	# Quieto: se mide el aim assist, no la IA del enemigo que se acerca al jugador.
	enemigo.set_physics_process(false)
	enemigo.set_process(false)
	var adelante: Vector3 = -camara.global_transform.basis.z
	enemigo.global_position = camara.global_position + adelante * 4.0 - Vector3.UP * 1.35
	for i in 10:
		await get_tree().physics_frame
	ok("el enemigo esta en el grupo enemy", enemigo.is_in_group("enemy"))
	var v_diag: Vector3 = enemigo.global_position + Vector3.UP * 1.35 - camara.global_position
	var q_diag := PhysicsRayQueryParameters3D.create(camara.global_position, enemigo.global_position + Vector3.UP * 1.35, 1)
	q_diag.exclude = [jugador.get_rid()]
	var hit_diag := camara.get_world_3d().direct_space_state.intersect_ray(q_diag)
	print("  (diag) objetivo=", jugador._aim_assist._objetivo, " angulo=", snappedf(rad_to_deg((-camara.global_transform.basis.z).angle_to(v_diag)), 0.1),
		" dist=", snappedf(v_diag.length(), 0.1), " rayo=", hit_diag.get("collider", null),
		" cam=", camara.global_position, " enemigo=", enemigo.global_position, " en_arbol=", enemigo.is_inside_tree())
	# se vuelve a colocar delante de la mira justo antes de medir
	# El aim assist recalcula su objetivo cada 0.05 s: se deja pasar mas que eso.
	var minimo := 1.0
	for i in 14:
		adelante = -camara.global_transform.basis.z
		enemigo.global_position = camara.global_position + adelante * 4.0 - Vector3.UP * 1.35
		await get_tree().physics_frame
		minimo = minf(minimo, jugador._aa_friccion)
	ok("con un enemigo en la mira el aim assist frena (friccion < 1)", minimo < 0.95,
		"minimo %.3f" % minimo)

	# Y el giro REAL con el dedo es menor con el enemigo delante que sin enemigo.
	for i in 8:
		adelante = -camara.global_transform.basis.z
		enemigo.global_position = camara.global_position + adelante * 4.0 - Vector3.UP * 1.35
		await get_tree().physics_frame
	await _giro_por_arrastre()
	var giro_asistido: float = _ultimo_giro
	ok("con el dedo la mira gira menos cerca de un enemigo (aim assist tactil)",
		giro_asistido < giro_libre * 0.8,
		"libre %.3f asistido %.3f" % [giro_libre, giro_asistido])
	enemigo.queue_free()
	await _esperar(3)

	print("== TACTIL: pausa, mando y seguridad ==")
	jugador._rotation_input = 0.0
	_toque(5, _centro("pausa"), true)
	await _esperar(3)
	_toque(5, _centro("pausa"), false)
	await _esperar(3)
	ok("el boton de pausa abre el menu", get_tree().paused)
	get_tree().paused = false
	var menu := jugador.get_node_or_null("PauseMenu")
	if menu:
		menu.visible = false

	# un mando conectado esconde los botones tactiles
	ctrl._mando = true
	ctrl._actualizar_visibilidad()
	ok("con mando conectado los botones tactiles se esconden", not ctrl.visible)
	ctrl._mando = false
	ctrl._actualizar_visibilidad()
	ok("al quitar el mando vuelven", ctrl.visible)

	# cambiar de app suelta todo
	_toque(7, _centro("fuego"), true)
	await _esperar(2)
	ok("disparo pulsado antes de cambiar de app", Input.is_action_pressed("attack"))
	ctrl.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _esperar(2)
	ok("al perder el foco se suelta todo (no se queda disparando)", not Input.is_action_pressed("attack"))

	# arma siguiente cicla
	var gestor := get_tree().get_first_node_in_group("weapon_manager")
	if gestor != null and gestor.weapons.size() > 1:
		var antes_arma: int = gestor.current_index
		_toque(8, _centro("arma"), true)
		await _esperar(2)
		_toque(8, _centro("arma"), false)
		await _esperar(2)
		ok("el boton ARMA cambia de arma", gestor.current_index != antes_arma,
			"%d -> %d" % [antes_arma, gestor.current_index])

	_fin()


var _ultimo_giro := 0.0


## Busca una direccion con `dist` metros de linea de vista libre y deja al jugador mirando
## hacia ella, para poder colocar un enemigo delante sin que una pared lo tape.
func _mirar_hacia_despejado(dist: float) -> bool:
	var camara: Camera3D = jugador.CAMERA_CONTROLLER
	for paso in 36:
		jugador._mouse_rotation.y = TAU * float(paso) / 36.0
		jugador._mouse_rotation.x = 0.0
		jugador.global_transform.basis = Basis.from_euler(Vector3(0.0, jugador._mouse_rotation.y, 0.0))
		await get_tree().physics_frame
		var fwd: Vector3 = -camara.global_transform.basis.z
		var q := PhysicsRayQueryParameters3D.create(camara.global_position,
			camara.global_position + fwd * (dist + 1.0), 1)
		q.exclude = [jugador.get_rid()]
		if camara.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			return true
	return false

func _giro_por_arrastre() -> void:
	# Se mide el giro REAL de la camara (lo que ve el jugador), no una variable temporal.
	var antes: float = jugador._mouse_rotation.y
	_toque(9, Vector2(1150, 330), true)
	await _esperar(1)
	_arrastre(9, Vector2(1190, 330), Vector2(40, 0))
	await _esperar(3)
	_ultimo_giro = absf(jugador._mouse_rotation.y - antes)
	_toque(9, Vector2(1190, 330), false)
	await _esperar(1)


func _fin() -> void:
	print("%d correctas, %d fallidas" % [aciertos, fallos])
	get_tree().quit()
