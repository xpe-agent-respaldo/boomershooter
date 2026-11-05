extends Node
func _ready() -> void:
	print("VIEJO>NUEVO 1.2.0 vs exe 1.2.3: descartar=", PatchLoader._es_mayor("1.2.3", "1.2.0"))
	print("IGUAL 1.2.3 vs 1.2.3: descartar=", PatchLoader._es_mayor("1.2.3", "1.2.3"))
	print("PARCHE NUEVO 1.2.4 sobre exe 1.2.3: descartar=", PatchLoader._es_mayor("1.2.3", "1.2.4"))
	get_tree().quit()
