extends Node
## Cuenta que cuesta cada tipo de nodo en un nivel (luces, mallas, particulas, fisica).
func _ready() -> void:
	var nivel: String = OS.get_environment("NIVEL")
	var inst: Node = (load(nivel) as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	var tipos := {}
	var luces := 0; var sombras := 0; var mallas := 0; var tris := 0
	var particulas := 0; var cuerpos := 0; var mats := {}
	var pila: Array = [inst]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		tipos[n.get_class()] = int(tipos.get(n.get_class(), 0)) + 1
		if n is Light3D:
			luces += 1
			if (n as Light3D).shadow_enabled: sombras += 1
		if n is MeshInstance3D:
			mallas += 1
			var m: Mesh = (n as MeshInstance3D).mesh
			if m != null:
				for s in m.get_surface_count():
					var arr = m.surface_get_arrays(s)
					if arr.size() > 0 and arr[Mesh.ARRAY_INDEX] != null:
						tris += int(arr[Mesh.ARRAY_INDEX].size() / 3)
					elif arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null:
						tris += int(arr[Mesh.ARRAY_VERTEX].size() / 3)
					var mt: Material = m.surface_get_material(s)
					if mt != null: mats[mt.get_instance_id()] = true
		if n is GPUParticles3D or n is CPUParticles3D: particulas += 1
		if n is PhysicsBody3D: cuerpos += 1
		for c in n.get_children(): pila.append(c)
	var orden: Array = tipos.keys()
	orden.sort_custom(func(a, b): return tipos[a] > tipos[b])
	print("TOP tipos:")
	for k in orden.slice(0, 8): print("  ", k, " x", tipos[k])
	print("luces=", luces, " con sombra=", sombras, " mallas=", mallas, " triangulos~", tris)
	print("materiales unicos=", mats.size(), " particulas=", particulas, " cuerpos fisicos=", cuerpos)
	get_tree().quit()
