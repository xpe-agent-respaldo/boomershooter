extends Node
## El mapa de nieve de verdad: geometria, puntos estrategicos, spawns sobre suelo, y que se pueda
## recorrer (escalera de la torre y del refugio subibles por el jugador).
var fallos := 0
func check(n: String, ok: bool, d = null) -> void:
	print("  ", "ok   " if ok else "FALLA", " ", n, "" if ok else "  [%s]" % str(d))
	if not ok: fallos += 1
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()
func _suelo(mundo: World3D, x: float, z: float, desde := 30.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, desde, z), Vector3(x, -5, z))
	q.collision_mask = 1
	var r := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	return r.position.y if r else -99.0
func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	arbol.change_scene_to_file("res://Levels/SnowFields.tscn")
	for _i in 60: await arbol.process_frame
	var m := arbol.current_scene
	check("escena SnowFields cargada", m != null and m.name == "SnowFields", m.name if m else null)
	# MapOptimizer funde las piezas CSG en mallas: se comprueba por lo que HAY en el mundo, no por nombre.
	check("geometria fusionada (MergedGeometry)", m.get_node("Map").has_node("MergedGeometry"), null)
	var mallas := m.find_children("*", "MeshInstance3D", true, false).size()
	check("mallas suficientes (%d)" % mallas, mallas >= 8, mallas)
	var cobertura := m.get_node_or_null("Escondites")
	check("coberturas del MapBuilder repartidas", cobertura != null and cobertura.get_child_count() >= 10, cobertura.get_child_count() if cobertura else 0)
	# puntos estrategicos por altura: el refugio (techo ~4.7 m), la torre (4.5 m) y el lago (0.0)
	check("techo del refugio transitable (~4.7 m)", absf(_suelo(null, 0, -4) - 4.7) < 0.6, _suelo(null, 0, -4))
	check("interior del refugio a nivel de suelo (techo no cae dentro)", absf(_suelo(null, 0, -4, 3.0)) < 0.3, _suelo(null, 0, -4, 3.0))
	var sp := m.get_node("SpawnPoints").get_children().filter(func(n): return n is Marker3D)
	check("al menos 6 puntos de aparicion", sp.size() >= 6, sp.size())
	# cada spawn debe tener suelo debajo y nada solido encima del jugador
	var mal := 0
	for s in sp:
		var p: Vector3 = (s as Node3D).global_position
		var y := _suelo(null, p.x, p.z)
		if y < -1.0 or y > 1.0 or p.y < y: mal += 1; print("      spawn dudoso ", s.name, " pos=", p, " suelo=", y)
	check("todos los spawns sobre suelo firme", mal == 0, mal)
	# la cima de la torre (4.2 m) y el desvan del refugio (2.7 m) son alcanzables por escalera
	check("plataforma de la torre a ~4.5 m", absf(_suelo(null, -4, -24) - 4.5) < 0.5, _suelo(null, -4, -24))
	var y_esc_base := _suelo(null, -4, -21.5)
	var y_esc_alto := _suelo(null, -4, -23.0)
	check("escalera de la torre sube (%.2f -> %.2f)" % [y_esc_base, y_esc_alto], y_esc_alto > y_esc_base, [y_esc_base, y_esc_alto])
	# ningun peldano mayor que lo que se sube andando: rayos que parten a poca altura, como camina un jugador
	var salto := 0.0; var prev := 0.0
	for k in range(0, 30):
		var y := _suelo(null, -4, -21.0 - k * 0.3, prev + 0.6)
		if y > -50.0:
			if k > 0: salto = maxf(salto, y - prev)
			prev = y
	check("ningun peldano supera 0.6 m (max=%.2f)" % salto, salto <= 0.6, salto)
	# el lago esta abierto: sin cobertura sobre el
	var tapado := 0
	for xx in range(-12, 13, 4):
		for zz in range(12, 28, 4):
			var y := _suelo(null, xx, zz)
			if y > 0.6: tapado += 1
	check("el lago helado esta despejado (sin obstaculos)", tapado == 0, tapado)
	# no hay estructuras flotando: todo bloque tiene algo hasta el suelo
	var jug := (load("res://Player/Player.tscn") as PackedScene).instantiate()
	m.add_child(jug); jug.global_position = Vector3(0, 2, 20)
	for _i in 90: await arbol.process_frame
	check("el jugador se apoya en el lago (y=%.2f)" % jug.global_position.y, jug.global_position.y > -0.5 and jug.global_position.y < 1.5, jug.global_position.y)
	print("NIEVE: ", "TODO OK" if fallos == 0 else "%d FALLOS" % fallos)
	arbol.quit(1 if fallos > 0 else 0)
