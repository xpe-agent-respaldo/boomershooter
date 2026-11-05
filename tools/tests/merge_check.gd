extends Node
## Comprueba que la fusion reduce nodos y NO rompe la colision (rayo al suelo y a las paredes).
func _ready() -> void:
	var inst: Node = (load(OS.get_environment("NIVEL")) as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	var mapa: Node3D = inst.get_node_or_null("Map") as Node3D
	if mapa == null: mapa = inst as Node3D
	var antes: int = mapa.find_children("*", "CSGShape3D", true, false).size()
	var cuerpos_antes: int = mapa.find_children("*", "CollisionShape3D", true, false).size()
	# rayos antes de fusionar
	var sp := mapa.get_world_3d().direct_space_state
	var pts: Array = []
	for i in 40:
		pts.append(Vector3(randf_range(-40, 40), 30, randf_range(-40, 40)))
	for _f in 3: await get_tree().physics_frame
	var antes_hits: Array = []
	for p in pts:
		var q := PhysicsRayQueryParameters3D.create(p, p + Vector3(0, -60, 0))
		var r := sp.intersect_ray(q)
		antes_hits.append(snappedf(r["position"].y, 0.5) if not r.is_empty() else -999.0)
	var st: Dictionary = MapOptimizer.optimize(mapa)
	for _f in 4: await get_tree().physics_frame
	var despues: int = mapa.find_children("*", "CSGShape3D", true, false).size()
	var cuerpos_despues: int = mapa.find_children("*", "CollisionShape3D", true, false).size()
	var difieren := 0
	for i in pts.size():
		var q2 := PhysicsRayQueryParameters3D.create(pts[i], pts[i] + Vector3(0, -60, 0))
		var r2 := sp.intersect_ray(q2)
		var y2: float = snappedf(r2["position"].y, 0.5) if not r2.is_empty() else -999.0
		if absf(y2 - float(antes_hits[i])) > 0.6: difieren += 1
	print("CSG: ", antes, " -> ", despues, " | colisiones: ", cuerpos_antes, " -> ", cuerpos_despues)
	print("piezas fusionadas=", st.get("pieces"), " mallas=", st.get("materials"), " tris=", st.get("triangles"))
	print("rayos que cambian de altura tras fusionar: ", difieren, " de ", pts.size())
	get_tree().quit()
