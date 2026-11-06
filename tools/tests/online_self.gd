extends Node
## Autodiagnostico del flujo online real (SDK de Godot, no Python).

func _ready() -> void:
	OnlineManager.status_changed.connect(func(m: String) -> void: print("ESTADO: ", m))
	OnlineManager.match_ready.connect(func(id: String) -> void:
		print("SALA LISTA: ", id)
		get_tree().quit(0))
	var ok: bool = await OnlineManager.join_room("", "survival", "recycling_plant", 3)
	print("join_room devolvio: ", ok)
	await get_tree().create_timer(18.0).timeout
	print("TIMEOUT: la sala nunca confirmo")
	# Sin online_defaults.cfg (la clave se inyecta al publicar) no hay conexion posible: se dice claro.
	if not FileAccess.file_exists("res://online_defaults.cfg"):
		print("OMITIDA: falta res://online_defaults.cfg (clave del servidor); esta prueba solo corre en CI o con la clave.")
		get_tree().quit(0)
		return
	get_tree().quit(2)
