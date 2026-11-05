extends Node
## Auditoria de rendimiento al empezar una partida.
##
## Mide lo que el jugador nota como "bajon": cuanto tarda en aparecer el mapa,
## cuanto se atasca el primer segundo (fusion CSG + compilacion de shaders + carga
## de escenas de enemigos desde disco) y como va luego en reposo.
##
## Uso: xvfb-run -s "-screen 0 1280x720x24" godot --path . tools/tests/rendimiento_test.tscn

const NIVEL := "res://Levels/SpaceArena.tscn"
const FRAMES_ARRANQUE := 90
const FRAMES_REPOSO := 120

var _deltas: Array[float] = []
var _midiendo := false


func _process(delta: float) -> void:
	if _midiendo:
		_deltas.append(delta)


func _ready() -> void:
	print("== RENDIMIENTO: arranque de partida ==")
	print("GPU: ", RenderingServer.get_video_adapter_name())
	print("Nucleos: ", OS.get_processor_count(), "  RAM: %.1f GB" % (float(OS.get_memory_info().get("physical", 0)) / 1073741824.0))

	var t0 := Time.get_ticks_msec()
	var escena: PackedScene = load(NIVEL)
	var carga_ms := Time.get_ticks_msec() - t0
	print("cargar la escena del mapa: %d ms" % carga_ms)

	_deltas.clear()
	_midiendo = true
	add_child(escena.instantiate())
	var arranque := await _medir(FRAMES_ARRANQUE)
	_reportar("primer segundo y medio (fusion del mapa + shaders)", arranque)

	# Reposo: ya no deberia haber picos
	var reposo := await _medir(FRAMES_REPOSO)
	_reportar("en reposo", reposo)

	print("  draw calls: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	print("  objetos dibujados: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	print("  nodos totales: ", get_tree().root.get_child_count(), " en la escena: ", escena.instantiate().get_child_count())
	print("  CSG que quedan sin fusionar: ", _contar_csg(get_tree().current_scene))

	# Aparicion de enemigos: si se cargan escenas desde disco en caliente, se nota.
	print("== enemigos ==")
	var rutas := ["res://Scenes/Enemies/Nuevos/AshCrawler.tscn"]
	_deltas.clear()
	for i in 10:
		var t1 := Time.get_ticks_msec()
		for r in rutas:
			if ResourceLoader.exists(r):
				var ps: PackedScene = load(r)
				var e = ps.instantiate()
				add_child(e)
		print("  oleada de 1 enemigo, carga en caliente: %d ms" % (Time.get_ticks_msec() - t1))

	var maximo := 0.0
	for d in _deltas:
		maximo = maxf(maximo, d)
	print("  peor frame instanciando enemigos: %.1f ms" % (maximo * 1000.0))

	print("")
	print("Lectura: un pico de mas de 100 ms se nota como congelacion al empezar.")
	get_tree().quit()


func _medir(frames: int) -> Dictionary:
	_deltas.clear()
	_midiendo = true
	for i in frames:
		await get_tree().process_frame
	_midiendo = false
	var copia := _deltas.duplicate()
	copia.sort()
	var suma := 0.0
	for d in copia:
		suma += d
	var n := maxi(1, copia.size())
	return {
		"max": copia[n - 1] * 1000.0,
		"p95": copia[int(n * 0.95) - 1 if int(n * 0.95) > 0 else 0] * 1000.0,
		"mediana": copia[n / 2] * 1000.0,
		"media": (suma / n) * 1000.0,
	}


func _reportar(nombre: String, datos: Dictionary) -> void:
	print("%s:" % nombre)
	print("  peor frame %.1f ms | p95 %.1f ms | mediana %.1f ms | media %.1f ms" % [
		datos["max"], datos["p95"], datos["mediana"], datos["media"]])


func _contar_csg(nodo: Node) -> int:
	if nodo == null:
		return 0
	var n := 0
	if nodo is CSGShape3D:
		n += 1
	for h in nodo.find_children("*", "CSGShape3D", true, false):
		n += 1
	return n
