extends Node
func _ready() -> void:
	# se cuelga de la raiz para sobrevivir al cambio de escena
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()

func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	arbol.change_scene_to_file(OS.get_environment("NIVEL"))
	for _i in 15: await arbol.process_frame
	var esc := arbol.current_scene
	print("escena: ", esc.name, " | CSG vivos: ", esc.find_children("*", "CSGShape3D", true, false).size(), " | fusionado: ", esc.find_child("MergedGeometry", true, false) != null, " | escondites: ", esc.has_node("Escondites"))
	arbol.quit()
