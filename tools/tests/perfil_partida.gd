extends Node
## Partida real: arena + jugador + oleadas + bots. Reporta ms por frame por sistema.
func _ready() -> void:
	GameSettings.performance_profile = 0
	var ps: PackedScene = load(OS.get_environment("NIVEL"))
	var esc := ps.instantiate()
	get_tree().root.add_child.call_deferred(esc)
	for _f in 20: await get_tree().process_frame
	var jug := (load("res://Player/Player.tscn") as PackedScene).instantiate()
	esc.add_child(jug)
	jug.global_position = Vector3(0, 2, 0)
	for _f in 20: await get_tree().process_frame
	# fuerza oleada alta para ver el peor caso
	var sm = esc.find_child("SpawnPoints", true, false)
	print("jugador en escena: ", jug.is_inside_tree(), " | SpawnManager: ", sm != null)
	var s_proc := 0.0; var s_fis := 0.0; var n := 0
	var peor := 0.0
	for _f in 600:
		var t := Time.get_ticks_usec()
		await get_tree().process_frame
		var dt := (Time.get_ticks_usec() - t) / 1000.0
		peor = maxf(peor, dt)
		s_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		s_fis += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		n += 1
	print("script ", snappedf(s_proc / n, 0.01), " ms | fisica ", snappedf(s_fis / n, 0.01), " ms | peor frame ", snappedf(peor, 0.1), " ms")
	print("enemigos=", get_tree().get_nodes_in_group("enemy").size(), " bots=", get_tree().get_nodes_in_group("bot").size(), " nodos=", int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	get_tree().quit()
