class_name MapOptimizer
extends RefCounted
## Fusiona la geometria CSG de un mapa en mallas estaticas, una por material.
##
## Los mapas se generan con cientos de CSGBox3D (comodos de editar, caros de dibujar):
## cada pieza es un draw call propio. Esto hornea cada pieza, agrupa los triangulos por
## material y deja UNA malla y UNA colision por material. Mapas grandes pasan de cientos
## de draw calls a una decena sin cambiar como se ven ni como se recorren.
##
## Las piezas sin colision (decoracion) se fusionan igual pero sin cuerpo fisico.

const COLLISION_LAYER := 1


## Optimiza `map` (nodo con hijos CSG). Devuelve estadisticas para el log y las pruebas.
static func optimize(map: Node3D) -> Dictionary:
	var stats := {"pieces": 0, "materials": 0, "triangles": 0, "skipped": 0}
	if map == null:
		return stats
	# material -> {solid: SurfaceTool, deco: SurfaceTool}
	var solid_tools: Dictionary = {}
	var deco_tools: Dictionary = {}
	var originals: Array[CSGShape3D] = []
	for node in map.find_children("*", "CSGShape3D", true, false):
		var csg := node as CSGShape3D
		# las piezas que son hijas de otro CSG (operaciones booleanas) las absorbe su raiz
		if csg == null or csg.get_parent() is CSGShape3D:
			continue
		var mesh: ArrayMesh = csg.bake_static_mesh()
		if mesh == null or mesh.get_surface_count() == 0:
			stats.skipped += 1
			continue
		var material: Material = csg.get("material") as Material
		var key: Material = material
		var tools: Dictionary = solid_tools if csg.use_collision else deco_tools
		if not tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = st
		var st_target: SurfaceTool = tools[key]
		# la malla horneada esta en el espacio local de la pieza: se lleva al del mapa
		var xform: Transform3D = map.global_transform.affine_inverse() * csg.global_transform
		for surface in mesh.get_surface_count():
			st_target.append_from(mesh, surface, xform)
		stats.pieces += 1
		originals.append(csg)
	if originals.is_empty():
		return stats

	var root := Node3D.new()
	root.name = "MergedGeometry"
	map.add_child(root)
	for key in solid_tools:
		stats.triangles += _emit(root, solid_tools[key], key, true)
	for key in deco_tools:
		stats.triangles += _emit(root, deco_tools[key], key, false)
	stats.materials = solid_tools.size() + deco_tools.size()

	# fuera las piezas originales: ya estan fusionadas (y su colision con ellas)
	for csg in originals:
		if is_instance_valid(csg):
			var holder: Node = csg.get_parent()
			csg.queue_free()
			# los StaticBody3D vacios que envolvian a un CSG tambien sobran
			if holder is StaticBody3D and holder.get_child_count() <= 1:
				holder.queue_free()
	return stats


static func _emit(root: Node3D, tool: SurfaceTool, material: Material, with_collision: bool) -> int:
	tool.generate_normals()
	var mesh: ArrayMesh = tool.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	if material != null:
		mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = "Merged" + ("Solid" if with_collision else "Deco")
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)
	var triangles := mesh.get_faces().size() / 3
	if with_collision:
		var body := StaticBody3D.new()
		body.name = "MergedBody"
		body.collision_layer = COLLISION_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		root.add_child(body)
	return triangles
