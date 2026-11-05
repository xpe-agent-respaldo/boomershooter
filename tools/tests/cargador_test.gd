extends Node
## Comprueba que el cambio de mapa ya no congela: carga en hilo con pantalla propia.

var soy_vigia := false
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
	if soy_vigia:
		await _vigilar()
		return
	# El nodo de pruebas muere con la escena actual: las comprobaciones las hace un
	# vigilante colgado de la raiz, que sobrevive al cambio de escena.
	var vigilante: Node = get_script().new()
	vigilante.soy_vigia = true
	get_tree().root.add_child.call_deferred(vigilante)
	await get_tree().process_frame
	await get_tree().process_frame
	Cargador.cambiar("res://Levels/SpaceArena.tscn")


func _vigilar() -> void:
	print("== CARGADOR: entrar a un mapa ==")
	ok("el cargador existe como autoload", Cargador != null)
	Cargador.cambiar("res://Levels/SpaceArena.tscn")
	await get_tree().process_frame
	var vio_pantalla := Cargador.get_node_or_null("CapaCarga") != null
	ok("aparece la pantalla de carga", vio_pantalla)

	var t0 := Time.get_ticks_msec()
	var frames_congelados := 0.0
	var peor := 0.0
	while Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
		var ms := get_process_delta_time() * 1000.0
		peor = maxf(peor, ms)
		if ms > 100.0:
			frames_congelados += 1.0
		var escena := get_tree().current_scene
		if escena != null and str(escena.name) == "SpaceArena":
			break
	var escena := get_tree().current_scene
	ok("termina en el mapa pedido", escena != null and str(escena.name) == "SpaceArena",
		str(escena.name) if escena else "sin escena")
	# La pantalla se queda unos frames tapando la fusion del mapa y luego se retira.
	var esperando := 0
	while (Cargador.cargando() or Cargador.get_node_or_null("CapaCarga") != null) and esperando < 240:
		await get_tree().process_frame
		esperando += 1
	ok("la pantalla de carga se retira sola",
		Cargador.get_node_or_null("CapaCarga") == null and not Cargador.cargando(),
		"esperando %d frames" % esperando)
	ok("se puede volver a cargar despues", not Cargador.cargando())
	print("  frames de mas de 100 ms durante la entrada: %.0f (peor %.0f ms)" % [frames_congelados, peor])
	print("")
	print("%d correctas, %d fallidas" % [aciertos, fallos])
	get_tree().quit(1 if fallos > 0 else 0)
