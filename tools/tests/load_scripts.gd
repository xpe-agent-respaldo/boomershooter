extends SceneTree
## Carga los scripts que toca el modo online para que Godot los compile de verdad
## (con los autoloads del proyecto), no solo con --check-only.

func _init() -> void:
	var rutas := [
		"res://Scripts/online_manager.gd",
		"res://Scripts/network_game.gd",
		"res://Scripts/team_alerts.gd",
		"res://Scenes/Weapons/weapon.gd",
		"res://Scripts/remote_player.gd",
	]
	var fallos := 0
	for ruta in rutas:
		var recurso = load(ruta)
		if recurso == null:
			fallos += 1
			print("FALLO ", ruta)
		else:
			print("ok    ", ruta)
	print("fallos: ", fallos)
	quit(1 if fallos > 0 else 0)
