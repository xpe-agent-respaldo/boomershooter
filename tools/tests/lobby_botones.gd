extends Node
## Recorre el Lobby REAL pulsando botones como un jugador, contra produccion.
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

func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	arbol.change_scene_to_file("res://Levels/Lobby.tscn")
	for _i in 20: await arbol.process_frame
	var lobby := arbol.current_scene
	print("LOBBY cargado: ", lobby.name, " | script=", lobby.get_script() != null)
	# 1) la lista de salas se rellena sola o con el boton Actualizar
	var lista = lobby._room_list
	var ok_lista := await _esperar(arbol, func(): return lista != null and lista.get_child_count() > 0 or str(lobby._rooms_status.text).begins_with("No hay"), 25.0)
	print("LISTA: estado='", lobby._rooms_status.text, "' filas=", lista.get_child_count() if lista else -1, " | respondio=", ok_lista)
	# 2) CREAR: pulsar el boton real
	var estados := []
	OnlineManager.status_changed.connect(func(m): estados.append(m))
	var inicio: String = arbol.current_scene.scene_file_path
	lobby.play_button.pressed.emit()
	var cambio := await _esperar(arbol, func(): return arbol.current_scene == null or arbol.current_scene.scene_file_path != inicio, 40.0)
	print("CREAR: cambio de escena=", cambio, " -> ", arbol.current_scene.scene_file_path if arbol.current_scene else "null")
	print("CREAR: estados=", estados)
	arbol.quit()
