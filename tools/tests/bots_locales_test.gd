extends Node
## Bots locales: tope de 5 por mapa y el dano exige linea de vision (no atraviesan paredes).
var fallos := 0
func _ok(c: bool, m: String) -> void:
	print(("  ok   " if c else "  FALLA ") + m)
	if not c: fallos += 1
func _ready() -> void:
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	_correr.call_deferred()
func _correr() -> void:
	var a := get_tree()
	await a.process_frame
	for mapa in ["SpaceArena", "StormVillage", "RecyclingPlant"]:
		a.change_scene_to_file("res://Levels/%s.tscn" % mapa)
		await a.create_timer(9.0).timeout
		var total: int = BotManager.allies.size() + BotManager.hostiles.size()
		var reclut := a.get_nodes_in_group("recruitable_bot").size()
		var cuenta := 0
		for n in a.current_scene.get_children():
			if n is Bot: cuenta += 1
		var todos: int = maxi(total, cuenta)
		_ok(todos <= 5, "%s: %d bots (max 5)" % [mapa, todos])
		_ok(todos >= 1, "%s: hay bots (no se quedo vacio)" % mapa)
		# vision: bot junto al jugador en campo abierto vs bot con pared de por medio
		var p: Player = Global.player
		var bot: Bot = null
		for n in a.current_scene.get_children():
			if n is Bot: bot = n; break
		if bot == null and not BotManager.hostiles.is_empty():
			bot = BotManager.hostiles[0]
		if bot != null and p != null:
			# pared de prueba entre ambos
			var cerca := p.global_position + Vector3(0, 0, 6)
			bot.global_position = cerca
			await a.physics_frame
			var pared := StaticBody3D.new()
			var forma := CollisionShape3D.new()
			var caja := BoxShape3D.new(); caja.size = Vector3(10, 8, 0.5)
			forma.shape = caja; pared.add_child(forma)
			pared.collision_layer = 1
			a.current_scene.add_child(pared)
			pared.global_position = p.global_position + Vector3(0, 2, 3)
			await a.physics_frame
			await a.physics_frame
			var pecho := p.global_position + Vector3(0, 1.2, 0)
			_ok(not bot.ve_al_objetivo(pecho), "%s: con una pared en medio el bot NO ve al jugador" % mapa)
			a.current_scene.remove_child(pared)
			pared.free()
			for _i in 4:
				await a.physics_frame
			# El mapa tiene cobertura real (cajas, columnas): se prueba desde varias direcciones y se exige
			# que AL MENOS una tenga vista libre, y que el rayo coincida con la fisica del mundo.
			var libres := 0
			var coinciden := true
			for ang in 8:
				var dir := Vector3(cos(ang * TAU / 8.0), 0, sin(ang * TAU / 8.0))
				bot.global_position = p.global_position + dir * 6.0
				await a.physics_frame
				var origen: Vector3 = bot.global_position + Vector3(0, 1.35, 0)
				var q := PhysicsRayQueryParameters3D.create(origen, pecho, 1)
				var g := bot.get_world_3d().direct_space_state.intersect_ray(q)
				var esperado: bool = g.is_empty() or (g["position"] as Vector3).distance_to(pecho) < 0.6
				if bot.ve_al_objetivo(pecho) != esperado:
					coinciden = false
				if esperado:
					libres += 1
			_ok(libres >= 1, "%s: desde alguna direccion el bot SI ve al jugador (%d de 8 libres)" % [mapa, libres])
			_ok(coinciden, "%s: ve_al_objetivo coincide con el rayo fisico en las 8 direcciones" % mapa)
	print("BOTS_LOCALES: ", "TODO BIEN" if fallos == 0 else "%d FALLOS" % fallos)
	a.quit(0 if fallos == 0 else 1)
