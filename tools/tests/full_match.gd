extends Node
## Partida completa: arena + jugador + director de bots + oleadas. Mide ms de script por frame.
func _ready() -> void:
	var inst: Node = (load(OS.get_environment("NIVEL")) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(inst)
	for _f in 30: await get_tree().process_frame
	var scene := inst
	var pl := scene.find_child("Player", true, false)
	print("jugador: ", pl != null, " | bots: ", get_tree().get_nodes_in_group("bot").size(), " | enemigos: ", get_tree().get_nodes_in_group("enemy").size())
	var picos: Array = []
	var tot_proc := 0.0; var tot_fis := 0.0; var n := 0
	for _f in 600:
		await get_tree().process_frame
		tot_proc += Performance.get_monitor(Performance.TIME_PROCESS)
		tot_fis += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		n += 1
	print("script/frame medio: ", snappedf(tot_proc / n * 1000.0, 0.01), " ms | fisica: ", snappedf(tot_fis / n * 1000.0, 0.01), " ms")
	print("bots=", get_tree().get_nodes_in_group("bot").size(), " enemigos=", get_tree().get_nodes_in_group("enemy").size(), " nodos=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT), " huerfanos=", Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	get_tree().quit()
