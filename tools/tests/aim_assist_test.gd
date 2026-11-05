extends Node3D
var fallos := 0
func ok(c: bool, m: String) -> void:
	print(("  ok   " if c else "  FALLA ") + m)
	if not c: fallos += 1

func _bot(modo: int, pos: Vector3) -> Bot:   # await-able
	# igual que BotManager: escena RemotePlayer con el script de Bot puesto antes de instanciar
	var nodo: Node = (load("res://Player/RemotePlayer.tscn") as PackedScene).instantiate()
	nodo.set_script(load("res://Scripts/Bots/bot.gd"))
	var b := nodo as Bot
	add_child(b)
	b.mode = modo
	b.set_physics_process(false)    # sin IA: la prueba no depende de a donde camine el bot
	b.set_process(false)
	# el bot se recoloca al arrancar: se espera a que termine y entonces se pone donde toca
	for _i in 2: await get_tree().physics_frame
	b.global_position = pos
	return b

func _crear_enemigo(pos: Vector3) -> Node3D:
	var e := Node3D.new(); e.add_to_group("enemy"); add_child(e); e.global_position = pos
	return e

func _ready() -> void:
	GameSettings.aim_assist_level = 2
	var cam := Camera3D.new(); add_child(cam); cam.global_position = Vector3(0, 1.6, 0)   # mira hacia -Z
	await get_tree().process_frame
	var aa := AimAssist.new()
	# 1) sin enemigos: nada cambia
	ok(is_equal_approx(aa.actualizar(0.2, null, cam), 1.0), "sin enemigos la sensibilidad es 1.0")
	ok(aa.empuje(0.016, cam, true, false) == Vector2.ZERO, "sin enemigos no hay empuje")
	# 2) un Node3D normal no es Enemy ni Bot; compruebo el cono con un Bot hostil de verdad
	var b: Bot = await _bot(Bot.Mode.HOSTILE, Vector3(1.0, 0.0, -15.0))    # ~3.8 grados a la derecha del centro
	await get_tree().process_frame
	for _i in 3: await get_tree().physics_frame
	aa._reloj = 0.0
	var f := aa.actualizar(0.2, null, cam)
	ok(f < 1.0 and f >= AimAssist.FRICCION_MIN, "friccion activa cerca del enemigo (%.2f)" % f)
	var e_quieto := aa.empuje(0.016, cam, false, false)
	ok(absf(e_quieto.x) < absf(aa.empuje(0.016, cam, true, false).x), "sin disparar tira menos que al disparar")
	var e_dispara := aa.empuje(0.016, cam, true, false)
	ok(e_dispara.x < 0.0, "al disparar empuja hacia la derecha (yaw negativo): %s" % str(e_dispara))
	ok(absf(e_dispara.x) <= 0.09, "el empuje por frame tiene tope")
	# 3) fuera del cono no ayuda
	b.global_position = Vector3(8.0, 0.0, -15.0)
	aa._reloj = 0.0; var f2 := aa.actualizar(0.2, null, cam)
	ok(is_equal_approx(f2, 1.0), "fuera del cono no hay friccion")
	# 4) los aliados no se apuntan
	b.global_position = Vector3(1.0, 0.0, -15.0); b.mode = Bot.Mode.ALLY
	aa._reloj = 0.0; var f3 := aa.actualizar(0.2, null, cam)
	ok(is_equal_approx(f3, 1.0), "un aliado no recibe asistencia")
	b.mode = Bot.Mode.HOSTILE
	# 5) una pared en medio bloquea la ayuda
	var muro := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(10, 6, 0.5); cs.shape = bx
	muro.add_child(cs); add_child(muro); muro.global_position = Vector3(0, 2, -7)
	for _i in 3: await get_tree().physics_frame
	aa._reloj = 0.0; var f4 := aa.actualizar(0.2, null, cam)
	ok(is_equal_approx(f4, 1.0), "una pared en medio anula la asistencia")
	# 6) apagada
	muro.queue_free(); await get_tree().physics_frame
	GameSettings.aim_assist_level = 0
	aa._reloj = 0.0
	ok(is_equal_approx(aa.actualizar(0.2, null, cam), 1.0), "apagada no hace nada")
	ok(aa.empuje(0.016, cam, true, true) == Vector2.ZERO, "apagada no empuja")
	# 7) coste: 200 llamadas con 40 enemigos
	GameSettings.aim_assist_level = 2
	for i in 40:
		await _bot(Bot.Mode.HOSTILE, Vector3(randf_range(-30,30), 0, randf_range(-60,-5)))
	await get_tree().physics_frame
	var t0 := Time.get_ticks_usec()
	for i in 600: aa.actualizar(1.0 / 60.0, null, cam)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	ok(ms / 600.0 < 0.5, "coste por frame con 40 enemigos: %.3f ms" % (ms / 600.0))
	print(("TODO OK" if fallos == 0 else "FALLOS: %d" % fallos))
	get_tree().quit(1 if fallos > 0 else 0)
