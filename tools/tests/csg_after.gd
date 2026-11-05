extends Node
func _ready() -> void:
	var inst: Node = (load(OS.get_environment("NIVEL")) as PackedScene).instantiate()
	add_child(inst)
	for i in 5: await get_tree().process_frame
	print("CSG vivos tras 5 frames: ", inst.find_children("*", "CSGShape3D", true, false).size(), " | MergedGeometry: ", inst.find_child("MergedGeometry", true, false) != null)
	get_tree().quit()
