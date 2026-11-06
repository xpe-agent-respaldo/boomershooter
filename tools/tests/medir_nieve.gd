extends Node
## Mide el plano caminable de SnowFields (rayos al suelo cada 2 m) y lo escribe como bloque Lua
## para infra/nakama/modules/map_floor.lua. Celda valida = hay suelo y hay hueco libre para un jugador.
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()
func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	arbol.change_scene_to_file("res://Levels/SnowFields.tscn")
	for _i in 60: await arbol.process_frame
	var estado := get_viewport().world_3d.direct_space_state
	var celdas: Array = []
	for cx in range(-32, 33, 2):
		for cz in range(-32, 33, 2):
			# suelo: rayo desde 6 m (por debajo de techos de casas/torre: 4.4 / 4.5 m + margen)
			var q := PhysicsRayQueryParameters3D.create(Vector3(cx, 3.2, cz), Vector3(cx, -2, cz))
			q.collision_mask = 1
			var r := estado.intersect_ray(q)
			if r.is_empty(): continue
			var y: float = r.position.y
			# hueco para el cuerpo: nada solido entre el suelo y 1.7 m
			var h := PhysicsRayQueryParameters3D.create(Vector3(cx, y + 0.05, cz), Vector3(cx, y + 1.7, cz))
			h.collision_mask = 1
			if not estado.intersect_ray(h).is_empty(): continue
			# fuera de las paredes de las casas: el suelo no puede estar rodeado a ras por solido
			celdas.append([cx, cz, snappedf(y, 0.1)])
	var txt := "-- snow_fields: %d celdas\nM.snow_fields = {\n" % celdas.size()
	var linea := "  "
	for i in celdas.size():
		var c: Array = celdas[i]
		linea += "{%d,%d,%.1f}%s" % [c[0], c[1], c[2], "," if i < celdas.size() - 1 else ""]
		if (i + 1) % 8 == 0: txt += linea + "\n"; linea = "  "
	if linea.strip_edges() != "": txt += linea + "\n"
	txt += "}\n"
	var f := FileAccess.open(ProjectSettings.globalize_path("res://") + "infra/nakama/modules/_snow_floor.lua.txt", FileAccess.WRITE)
	f.store_string(txt); f.close()
	print("CELDAS: ", celdas.size())
	arbol.quit()
