extends Node
## Simula las dos causas del "me vuelve a pedir actualizar".
func _ready() -> void:
	var um = load("res://Scripts/update_manager.gd")
	# A) el exe es 1.2.2 pero queda montado un parche VIEJO (1.1.6) en user://patch
	PatchLoader.mounted_version = "1.1.6"
	var v_exe := str(ProjectSettings.get_setting("application/config/version", ""))
	var inst = um.new()
	print("A) exe=", v_exe, " | parche viejo montado=1.1.6 | _current_version()=", inst._current_version(), " | pide actualizar a 1.2.2? ", inst._version_is_newer("1.2.2", inst._current_version()))
	# B) parche NUEVO montado: la version del parche manda y es correcta
	PatchLoader.mounted_version = "1.2.2"
	print("B) parche 1.2.2 montado | _current_version()=", inst._current_version(), " | pide actualizar a 1.2.2? ", inst._version_is_newer("1.2.2", inst._current_version()))
	get_tree().quit()
