extends Node
## Reproduce lo que hace el usuario: abre el lobby (lista salas) y pulsa una fila.
func _ready() -> void:
	if not FileAccess.file_exists("res://online_defaults.cfg"):
		print("OMITIDA: falta res://online_defaults.cfg (clave del servidor); esta prueba solo corre en CI o con la clave.")
		get_tree().quit(0)
		return
	OnlineManager.status_changed.connect(func(m: String) -> void: print("ESTADO: ", m))
	OnlineManager.match_ready.connect(func(id: String) -> void:
		print("SALA LISTA: ", id)
		get_tree().quit(0))
	var salas: Array = await OnlineManager.fetch_rooms()
	print("salas en lista: ", salas.size())
	if salas.is_empty():
		get_tree().quit(3)
		return
	var mid := str(salas[0].get("match_id", ""))
	print("pulso la sala: ", salas[0].get("name"), " modo ", salas[0].get("mode"))
	# exactamente lo que hace el lobby: modo y mapa de la PANTALLA, no de la sala
	var ok: bool = await OnlineManager.join_room(mid, "coop_waves", "recycling_plant", 3)
	print("join_room devolvio: ", ok)
	await get_tree().create_timer(15.0).timeout
	print("TIMEOUT sin match_ready")
	get_tree().quit(2)
