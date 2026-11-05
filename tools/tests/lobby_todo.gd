extends Node
## Cada combinacion modo x mapa de CREAR + UNIRSE desde la lista, pulsando botones reales.
var resultados := []
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()
func _esperar(arbol: SceneTree, cond: Callable, max_s: float) -> bool:
	var t := 0.0
	while t < max_s:
		if cond.call(): return true
		await arbol.create_timer(0.25).timeout
		t += 0.25
	return false
func _abrir_lobby(arbol: SceneTree) -> Node:
	OnlineManager.leave_online()
	arbol.change_scene_to_file("res://Levels/Lobby.tscn")
	for _i in 15: await arbol.process_frame
	var lb := arbol.current_scene
	await _esperar(arbol, func(): return not lb._refreshing and lb._rooms_status.text != "", 25.0)
	return lb
func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	var combos := [[0,0],[1,1],[2,2],[3,0],[4,1],[0,2]]   # modo, mapa (cubre los 5 modos y los 3 mapas)
	for c in combos:
		var lb: Node = await _abrir_lobby(arbol)
		lb._select_mode(c[0]); lb._select_map(c[1])
		var modo_id: String = str(lb.MODES[c[0]].id)
		var mapa_id: String = str(lb.MAPS[c[1]].id)
		var esperado: String = lb.MAPS[c[1]].level
		lb.play_button.pressed.emit()
		var ok := await _esperar(arbol, func(): return arbol.current_scene != null and arbol.current_scene.scene_file_path == esperado, 40.0)
		resultados.append(ok)
		print("CREAR modo=", modo_id, " mapa=", mapa_id, " -> ", "OK" if ok else "FALLA (escena: %s)" % (arbol.current_scene.scene_file_path if arbol.current_scene else "null"))
	# UNIRSE desde el listado: la ultima sala creada aparece como fila y se pulsa
	var lb2: Node = await _abrir_lobby(arbol)
	var filas: Array = lb2._room_list.get_children().filter(func(n): return n is Button)
	if filas.is_empty():
		print("UNIRSE: no hay filas en el listado"); resultados.append(false)
	else:
		lb2._select_map(1)
		var antes := arbol.current_scene.scene_file_path
		(filas[0] as Button).pressed.emit()
		var ok2 := await _esperar(arbol, func(): return arbol.current_scene != null and arbol.current_scene.scene_file_path != antes, 40.0)
		resultados.append(ok2)
		print("UNIRSE desde listado (", filas.size(), " filas) -> ", "OK -> " + arbol.current_scene.scene_file_path if ok2 else "FALLA")
	var buenos := resultados.filter(func(x): return x).size()
	print("RESULTADO LOBBY: ", buenos, "/", resultados.size())
	arbol.quit()
