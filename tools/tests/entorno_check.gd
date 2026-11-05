extends Node
func _ready() -> void:
	GameSettings.modo_plano = OS.get_environment("PERFIL") == "1"
	var arbol := get_tree()
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	arbol.root.add_child.call_deferred(yo)
	_correr.call_deferred()
func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	arbol.change_scene_to_file(OS.get_environment("NIVEL"))
	for _i in 15: await arbol.process_frame
	var we := arbol.current_scene.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment
	var e := we.environment
	print("modo_plano=", GameSettings.modo_plano, " fondo=", e.background_mode, " ambiente=", e.ambient_light_source, " tonemap=", e.tonemap_mode, " color=", e.background_color)
	arbol.quit()
