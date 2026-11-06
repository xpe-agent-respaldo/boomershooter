extends Node
## Un OP_BOT_SHOT del servidor debe producir una senal, un sonido 3D y una traza visible.
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()

func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	arbol.change_scene_to_file("res://Levels/SpaceArena.tscn")
	await arbol.create_timer(6.0).timeout
	var recibido := [0, false]
	OnlineManager.entrenado_disparo.connect(func(_d, _o, acerto, _n):
		recibido[0] += 1
		recibido[1] = acerto)
	for n in arbol.get_nodes_in_group("traza_bot"):
		n.free()
	await arbol.create_timer(0.2).timeout
	var p: Player = Global.player
	var pos: Vector3 = p.global_position + Vector3(6, 0, 0)
	var json := JSON.stringify({"user_id": "bot-1", "name": "Vex-01",
		"pos": {"x": pos.x, "y": pos.y, "z": pos.z}, "target_user_id": "u1", "hit": true})
	OnlineManager.handle_server_message(84, json)
	var trazas := 0
	var voces3d := 0
	for n in arbol.current_scene.get_children():
		if n.is_in_group("traza_bot"):
			trazas += 1
		if n is AudioStreamPlayer3D and n.playing:
			voces3d += 1
	print("DISPARO_BOT: señal=", recibido[0], " acerto=", recibido[1], " | trazas visibles=", trazas, " | sonidos 3D=", voces3d)
	_volcar(arbol)
	await arbol.create_timer(0.3).timeout
	var restantes := 0
	for n in arbol.current_scene.get_children():
		if n.is_in_group("traza_bot"):
			restantes += 1
	print("DISPARO_BOT: trazas tras 0.3 s (deben haberse borrado) = ", restantes)
	arbol.quit(0 if recibido[0] == 1 and trazas >= 1 and restantes == 0 else 1)

func _volcar(arbol: SceneTree) -> void:
	for n in arbol.current_scene.get_children():
		if n is MeshInstance3D and n.mesh is CylinderMesh:
			print("  cil: ", n.name, " r=", (n.mesh as CylinderMesh).top_radius, " h=", (n.mesh as CylinderMesh).height, " scale=", n.scale, " pos=", n.global_position)
