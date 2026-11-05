extends SceneTree
func _init() -> void:
	var s = load("res://Scripts/game_settings.gd")
	print("CARGA game_settings.gd: ", "OK" if s != null and s.can_instantiate() else "FALLA")
	quit()
