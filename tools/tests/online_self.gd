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
	var st: int = -1
	if OnlineManager.bridge != null:
		st = OnlineManager.bridge._match_state
	print("estado interno del bridge: ", st)
	get_tree().quit(2)
