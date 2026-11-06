extends SceneTree
## Monta un pack base y un parche delta y comprueba que el script del parche gana.
## Uso: godot --headless --script tools/tests/montar_parche_test.gd -- base.pck delta.pck
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var antes: float = load("res://Scripts/lobby_music.gd").FUNDIDO
	print("antes de montar: FUNDIDO=", antes)
	var ok1 := ProjectSettings.load_resource_pack(args[0], true)
	var ok2 := ProjectSettings.load_resource_pack(args[1], true)
	var despues: float = ResourceLoader.load("res://Scripts/lobby_music.gd", "", ResourceLoader.CACHE_MODE_IGNORE).FUNDIDO
	print("montados base=", ok1, " delta=", ok2, " | despues: FUNDIDO=", despues)
	quit(0 if (ok1 and ok2) else 1)
