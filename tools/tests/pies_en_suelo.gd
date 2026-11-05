extends Node
## Pone un RemotePlayer (como un bot online) en celdas con escalon de cada mapa, con la Y que mandaria
## el servidor, y comprueba con rayos que sus PIES (punto mas bajo del modelo) tocan el suelo del juego.
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()
func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	arbol.change_scene_to_file(OS.get_environment("NIVEL"))
	await arbol.create_timer(8.0).timeout
	var esc := arbol.current_scene as Node3D
	var space := esc.get_world_3d().direct_space_state
	var celdas: Array = JSON.parse_string(FileAccess.get_file_as_string("/tmp/celdas_" + str(esc.name) + ".json"))
	var escalones := celdas.filter(func(c): return absf(c[1]) > 0.15)
	var llanas := celdas.filter(func(c): return absf(c[1]) <= 0.15)
	escalones.shuffle(); llanas.shuffle()
	var prueba: Array = escalones.slice(0, 12) + llanas.slice(0, 12)
	var Remote: PackedScene = load("res://Player/RemotePlayer.tscn")
	var mal := 0; var peor := 0.0
	for c in prueba:
		var r: Node3D = Remote.instantiate()
		esc.add_child(r)
		r.call("setup", "Bot", Color.WHITE, "neko_base")
		r.call("push_transform", Vector3(c[0], c[1], c[2]), 0.0)
		await arbol.process_frame
		# suelo real bajo el bot (mascara 1 = mundo), ignorando al propio bot
		var q := PhysicsRayQueryParameters3D.create(Vector3(c[0], c[1] + 3.0, c[2]), Vector3(c[0], c[1] - 3.0, c[2]), 1)
		var h := space.intersect_ray(q)
		var suelo: float = h.position.y if h else NAN
		var pies := r.global_position.y
		var d := pies - suelo
		peor = maxf(peor, absf(d))
		if is_nan(suelo) or absf(d) > 0.15: mal += 1; print("  MAL en ", c, " pies=", pies, " suelo=", suelo)
		r.queue_free()
	print("PIES ", esc.name, " | probados=", prueba.size(), " (", mini(12, escalones.size()), " en escalon) | fuera de suelo=", mal, " | peor desvio=", snappedf(peor, 0.01), " m")
	arbol.quit()
