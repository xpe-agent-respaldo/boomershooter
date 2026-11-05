extends Node
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()
func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	arbol.change_scene_to_file(OS.get_environment("NIVEL"))
	for _i in 30: await arbol.process_frame
	var jug := (load("res://Player/Player.tscn") as PackedScene).instantiate()
	arbol.current_scene.add_child(jug)
	jug.global_position = Vector3(0, 2, 0)
	for _i in 3: await arbol.process_frame
	var bm0 = arbol.root.get_node("BotManager")
	var nacen_altos := 0
	for b in arbol.get_nodes_in_group("hostile_bot"):
		if b.global_position.y > 1.5: nacen_altos += 1
	print("NACEN_ALTOS=", nacen_altos, " de ", arbol.get_nodes_in_group("hostile_bot").size())
	for _i in 600: await arbol.process_frame
	var bm = arbol.root.get_node("BotManager")
	var bots := arbol.get_nodes_in_group("hostile_bot")
	var sin_suelo := 0; var muy_lejos := 0; var cayendo := 0
	for b in bots:
		var p: Vector3 = b.global_position
		if p.y < -3.0: cayendo += 1
		if Vector2(p.x, p.z).length() > 140.0: muy_lejos += 1
	print("BOTS escena=", arbol.current_scene.name, " | hostiles=", bm.hostiles.size(), " | en grupo=", bots.size(), " | aliados/reclutables=", bm.allies.size(), " | cayendo(y<-3)=", cayendo, " | lejos(>140m)=", muy_lejos, " | nodos totales=", int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	for b in bots:
		if b.global_position.y > 1.5:
			print("  ALTO: ", b.name, " pos=", b.global_position, " escuadron=", b.squad_id if "squad_id" in b else "?")
	var ys := []
	for b in bots: ys.append(snappedf(b.global_position.y, 0.1))
	print("alturas: ", ys.slice(0, 14))
	arbol.quit()
