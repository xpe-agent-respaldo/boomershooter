extends Node
## El lobby debe tener un boton por mapa, todos dentro del panel y sin solaparse (portatil e iPhone).
var fallos := 0
func check(nombre: String, ok: bool, dato = null) -> void:
	print("  ", "ok   " if ok else "FALLA", " ", nombre, "" if ok else "  [%s]" % str(dato))
	if not ok: fallos += 1
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()
func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	for res in [Vector2i(1280, 720), Vector2i(844, 390), Vector2i(1920, 1080), Vector2i(2532, 1170)]:
		# Como el juego real: viewport de diseno 1920x1080 y el motor lo ajusta a la ventana (canvas_items).
		arbol.root.content_scale_size = Vector2i(1920, 1080)
		arbol.root.size = res
		arbol.change_scene_to_file("res://Levels/Lobby.tscn")
		for _i in 12: await arbol.process_frame
		var lobby := arbol.current_scene
		var botones: Array = lobby._map_buttons
		var n_mapas: int = lobby.MAPS.size()
		print("[", res.x, "x", res.y, "] mapas=", n_mapas, " botones=", botones.size())
		check("un boton por mapa (%d)" % n_mapas, botones.size() == n_mapas, botones.size())
		var pantalla := Rect2(Vector2.ZERO, Vector2(1920, 1080))
		var dentro := true
		var solapan := false
		for i in botones.size():
			var r: Rect2 = (botones[i] as Control).get_global_rect()
			if not pantalla.encloses(r.grow(-1.0)): dentro = false
			for j in range(i + 1, botones.size()):
				if r.grow(-1.0).intersects((botones[j] as Control).get_global_rect().grow(-1.0)): solapan = true
		if not dentro:
			for b in botones: print("      boton ", (b as Control).get_global_rect())
			print("      pantalla ", pantalla)
		check("todos los botones dentro de la pantalla", dentro)
		check("ningun boton tapa a otro", not solapan)
		# cada mapa se puede elegir y muestra su nombre y su imagen
		# con 9 modos la lista crece: el boton de JUGAR y todos los modos deben seguir a la vista
		var modos: Array = lobby._mode_buttons
		var fuera := []
		for mb in modos:
			if not Rect2(0, 0, 1920, 1080).encloses((mb as Control).get_global_rect().grow(-1.0)): fuera.append(mb.text)
		check("los %d modos caben en pantalla" % modos.size(), fuera.is_empty(), fuera)
		var jugar: Control = lobby.play_button
		check("el boton de jugar esta a la vista", Rect2(0, 0, 1920, 1080).encloses(jugar.get_global_rect()), jugar.get_global_rect())
		for i in n_mapas:
			lobby._select_map(i)
			await arbol.process_frame
			check("mapa %d '%s' elegible, con titulo e imagen" % [i, lobby.MAPS[i].short], lobby.map_title.text == lobby.MAPS[i].name and lobby.map_preview.texture != null)
	print("LOBBY_MAPAS: ", "TODO OK" if fallos == 0 else "%d FALLOS" % fallos)
	arbol.quit(1 if fallos > 0 else 0)
