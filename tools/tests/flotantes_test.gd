extends Node
## Busca estructuras que flotan: cada pieza solida del mapa debe apoyarse en el suelo o en
## otra pieza. Se lanza un rayo hacia abajo desde la base de la pieza y se mide el hueco.

const NIVELES := ["res://Levels/SpaceArena.tscn", "res://Levels/StormVillage.tscn", "res://Levels/RecyclingPlant.tscn"]
const HUECO_MAX := 0.35      # metros de aire permitidos bajo una pieza (escalones y bordes)
var fallos := 0
var total_piezas := 0

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	for ruta in NIVELES:
		if not ResourceLoader.exists(ruta):
			print("  (no existe) ", ruta)
			continue
		await _revisar(ruta)
	print("")
	print("%d piezas revisadas, %d flotando" % [total_piezas, fallos])
	get_tree().quit(1 if fallos > 0 else 0)


func _revisar(ruta: String) -> void:
	var nivel: Node = load(ruta).instantiate()
	get_tree().root.add_child(nivel)
	for i in 50:
		await get_tree().physics_frame
	var espacio := get_viewport().world_3d.direct_space_state
	var flotan: Array = []
	var cuerpos: Array = []
	_recoger(nivel, cuerpos)
	for pieza in cuerpos:
		var caja := _caja(pieza)
		if caja.size == Vector3.ZERO:
			continue
		# solo piezas que "sobresalen" (cualquier cosa por encima del suelo, no el suelo mismo)
		var base: float = caja.position.y
		if base < 0.4 and caja.size.y > 0.0:
			total_piezas += 1
			continue
		total_piezas += 1
		var centro := Vector3(caja.position.x + caja.size.x * 0.5, base + 0.05, caja.position.z + caja.size.z * 0.5)
		# Una pieza esta sostenida si hay algo tocandola: por debajo (suelo, columna) o por
		# los lados (un techo se apoya en las paredes, una pasarela en sus soportes).
		# Se lanzan rayos desde el centro de la pieza hacia abajo y hacia las 4 esquinas/lados.
		var apoyos := 0
		var c := caja.get_center()
		var mitad := caja.size * 0.5
		var margen := 0.25
		var dirs: Array = [
			Vector3.DOWN,
			Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
			Vector3(1, -0.6, 0), Vector3(-1, -0.6, 0), Vector3(0, -0.6, 1), Vector3(0, -0.6, -1),
		]
		for d in dirs:
			var largo: float = 0.0
			if d == Vector3.DOWN:
				largo = mitad.y + HUECO_MAX
			else:
				largo = maxf(absf(d.x) * mitad.x, absf(d.z) * mitad.z) + margen
			var o: Vector3 = c
			var q := PhysicsRayQueryParameters3D.create(o, o + d.normalized() * largo, 0xFFFFF)
			if pieza is CollisionObject3D:
				q.exclude = [pieza.get_rid()]
			var r := espacio.intersect_ray(q)
			if not r.is_empty():
				apoyos += 1
		# Y si la propia pieza ya toca el suelo (su base esta a ras), esta bien.
		if base <= 0.3:
			apoyos += 1
		if apoyos == 0:
			flotan.append("%s en (%.1f, %.1f, %.1f) tam (%.1f, %.1f, %.1f)" % [pieza.name, caja.position.x, caja.position.y, caja.position.z, caja.size.x, caja.size.y, caja.size.z])
	print("== %s: %d piezas, %d flotando" % [ruta.get_file(), cuerpos.size(), flotan.size()])
	for f in flotan.slice(0, 12):
		print("   FLOTA ", f)
	fallos += flotan.size()
	nivel.queue_free()
	await get_tree().process_frame


func _recoger(n: Node, out: Array) -> void:
	if n is CSGShape3D and (n as CSGShape3D).use_collision:
		out.append(n)
	elif n is MeshInstance3D and n.get_parent() is StaticBody3D:
		out.append(n)
	for h in n.get_children():
		_recoger(h, out)


func _caja(n: Node) -> AABB:
	if n is CSGShape3D:
		var a: AABB = (n as CSGShape3D).get_aabb()
		return (n as Node3D).global_transform * a
	if n is MeshInstance3D:
		return (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
	return AABB()
