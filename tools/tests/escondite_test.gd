extends Node
## El escondite del mapa espacial: entra por la puerta, los muros son solidos, la rendija deja ver fuera.
var fallos := 0
func _ok(c: bool, m: String) -> void:
	print(("  ok   " if c else "  FALLA ") + m)
	if not c: fallos += 1
func _ready() -> void:
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	_correr.call_deferred()
func _rayo(esp: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1
	return esp.intersect_ray(q)
func _correr() -> void:
	var a := get_tree()
	await a.process_frame
	a.change_scene_to_file("res://Levels/SpaceArena.tscn")
	var t := 0.0
	while t < 20.0 and (a.current_scene == null or a.current_scene.find_child("EsconditeNorte", true, false) == null):
		await a.create_timer(0.25).timeout
		t += 0.25
	await a.create_timer(1.0).timeout
	await a.physics_frame
	await a.physics_frame
	var esp: PhysicsDirectSpaceState3D = a.current_scene.get_viewport().world_3d.direct_space_state
	var c := Vector3(-18, 0, -32)
	var h := 1.0   # altura de los ojos para los rayos
	# El optimizador de mapa (MapOptimizer) funde las piezas CSG en una malla por material y borra las
	# originales al empezar la partida: en marcha solo sobreviven la luz y la malla fusionada. Por eso las
	# 9 piezas se comprueban en el archivo de escena, y su efecto (muros, techo, rendija) con fisica real.
	var texto := FileAccess.get_file_as_string("res://Levels/SpaceArena.tscn")
	var en_archivo := 0
	for n in ["Norte", "Oeste", "EsteBajo", "EsteAlto", "SurA", "SurB", "Dintel", "Techo", "Caja"]:
		if texto.contains('[node name="Escondite%s" type="CSGBox3D"' % n): en_archivo += 1
	_ok(en_archivo == 9, "las 9 piezas del escondite estan en la escena (%d)" % en_archivo)
	_ok(a.current_scene.find_child("EsconditeLuz", true, false) != null, "tiene su luz interior")
	# 1) la PUERTA (muro sur, z=-28): un rayo de fuera a dentro por el centro de la puerta NO choca
	var por_puerta := _rayo(esp, Vector3(c.x, h, c.z + 8), Vector3(c.x, h, c.z))
	_ok(por_puerta.is_empty(), "se puede entrar por la puerta (el rayo llega al centro sin chocar)")
	# 2) los MUROS son solidos: desde fuera hacia dentro por otros lados chocan
	for lado in [["norte", Vector3(c.x, h, c.z - 8)], ["oeste", Vector3(c.x - 8, h, c.z)], ["sur (junto a la puerta)", Vector3(c.x + 3, h, c.z + 8)], ["sur (otro lado)", Vector3(c.x - 3, h, c.z + 8)]]:
		var r := _rayo(esp, lado[1], Vector3(c.x, h, c.z))
		_ok(not r.is_empty(), "el muro %s es solido" % lado[0])
	# 3) el techo existe: un rayo desde arriba choca
	var techo := _rayo(esp, Vector3(c.x, 8, c.z), Vector3(c.x, 0.2, c.z))
	_ok(not techo.is_empty() and techo.position.y > 3.0, "tiene techo (choca a %.1f m)" % (techo.position.y if not techo.is_empty() else -1.0))
	# 4) la RENDIJA (muro este, y entre 1.5 y 2.0): se ve fuera a esa altura pero no a ras de suelo ni por encima
	var xe := c.x + 4.0
	var ve := _rayo(esp, Vector3(c.x, 1.75, c.z), Vector3(xe + 6, 1.75, c.z))
	_ok(ve.is_empty(), "por la rendija (1.75 m) se ve el exterior")
	var no_ve := _rayo(esp, Vector3(c.x, 0.8, c.z), Vector3(xe + 6, 0.8, c.z))
	_ok(not no_ve.is_empty(), "a la altura del pecho el muro tapa (cobertura real)")
	# 5) el jugador cabe: entra, llega al centro y no se queda atascado
	var p: Player = Global.player
	p.global_position = Vector3(c.x, 0.3, c.z + 10)
	p.velocity = Vector3.ZERO
	await a.physics_frame
	var dentro := false
	for i in 360:
		# empuja al jugador hacia la puerta (-z) con la fisica del propio personaje; si choca con un muro no avanza
		p.velocity.x = 0.0
		p.velocity.z = -5.0
		await a.physics_frame
		if absf(p.global_position.x - c.x) < 2.0 and absf(p.global_position.z - c.z) < 2.5:
			dentro = true
			break
	p.velocity = Vector3.ZERO
	_ok(dentro, "el jugador entra caminando por la puerta hasta el centro (pos %s)" % str(p.global_position.snapped(Vector3(0.1, 0.1, 0.1))))
	# 6) no hay nada pisando el interior (el hueco libre medido)
	var estorbo := 0
	for n in a.current_scene.find_child("Map", true, false).get_children():
		if n is Node3D and not str(n.name).begins_with("Escondite") and not str(n.name).begins_with("Wall") and n.name != "Ground":
			var d := Vector2(n.global_position.x - c.x, n.global_position.z - c.z).length()
			if d < 6.0: estorbo += 1
	_ok(estorbo == 0, "ninguna pieza del mapa invade el escondite (%d)" % estorbo)
	print("ESCONDITE: ", "TODO BIEN" if fallos == 0 else "%d FALLOS" % fallos)
	a.quit(0 if fallos == 0 else 1)
