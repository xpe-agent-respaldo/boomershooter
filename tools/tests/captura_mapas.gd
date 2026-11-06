extends Node
## Captura una imagen real de cada mapa con el jugador dentro (necesita ventana: usar xvfb-run).
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()
func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	for par in [["RecyclingPlant", "planta"], ["StormVillage", "aldea"], ["SpaceArena", "espacial"], ["SnowFields", "nieve"]]:
		arbol.change_scene_to_file("res://Levels/%s.tscn" % par[0])
		for _i in 20: await arbol.process_frame
		var jug := (load("res://Player/Player.tscn") as PackedScene).instantiate()
		arbol.current_scene.add_child(jug); jug.global_position = Vector3(0, 2, 0)
		for _i in 90: await arbol.process_frame
		get_viewport().get_texture().get_image().save_png("/tmp/mapa_%s.png" % par[1])
		print("CAPTURA ", par[1])
	arbol.quit()
