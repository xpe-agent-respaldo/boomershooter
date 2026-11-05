extends Node
## Decide, para cada version instalada, que haria el actualizador contra el manifiesto publicado.
func _ready() -> void:
	var um = load("res://Scripts/update_manager.gd").new()
	var remota := "1.2.4"
	var minima := "1.1.6"
	for v in ["1.0.0","1.1.0","1.1.5","1.1.6","1.1.9","1.2.0","1.2.1","1.2.2","1.2.3","1.2.4","1.2.5"]:
		var obligatoria: bool = um._version_is_newer(minima, v)
		var hay: bool = um._version_is_newer(remota, v)
		print("UPD ", v, " -> ", "BLOQUEADA, debe actualizar" if obligatoria else ("ofrece actualizar a " + remota if hay else "al dia"))
	get_tree().quit()
