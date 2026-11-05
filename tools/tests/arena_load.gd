extends Node
## Carga el nivel como lo hace el juego tras entrar a sala y mide el tiempo y los FPS.
func _ready() -> void:
	var nivel: String = OS.get_environment("NIVEL")
	if nivel == "": nivel = "res://Levels/RecyclingPlant.tscn"
	var t0 := Time.get_ticks_msec()
	var ps: PackedScene = load(nivel)
	print("load(): ", Time.get_ticks_msec() - t0, " ms")
	var t1 := Time.get_ticks_msec()
	var inst := ps.instantiate()
	add_child(inst)
	print("instantiate+ready: ", Time.get_ticks_msec() - t1, " ms")
	var muestras: Array = []
	for i in 120:
		var f := Time.get_ticks_msec()
		await get_tree().process_frame
		muestras.append(Time.get_ticks_msec() - f)
	var tot := 0
	var peor := 0
	for m in muestras:
		tot += m
		peor = max(peor, m)
	print("frame medio: ", tot / float(muestras.size()), " ms | peor: ", peor, " ms")
	print("nodos: ", Performance.get_monitor(Performance.OBJECT_NODE_COUNT), " objetos: ", Performance.get_monitor(Performance.OBJECT_COUNT))
	print("draw calls: ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	get_tree().quit()
